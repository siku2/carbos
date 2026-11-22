//! Translates between `vhci_hcd` (USB/IP) and a server session (SXUPTP).

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::{Shutdown, TcpStream};
use std::os::unix::net::UnixStream;
use std::sync::Mutex;
use std::sync::atomic::{AtomicBool, Ordering};
use std::thread;
use std::time::{Duration, Instant};

use log::debug;

use crate::error::{Error, Result};
use crate::sxuptp::{Notification, ReplyHeader, Request, Transfer, status};
use crate::usbip::{Command, Reply, Submit, errno};

/// How long the sequence number of a cancelled request stays blocked. The
/// server never answers a cancel, but a reply sent before it saw the cancel
/// may still be on its way.
const ORPHAN_TTL: Duration = Duration::from_secs(10);
const REAP_INTERVAL: Duration = Duration::from_secs(1);
const RETRY_DELAY: Duration = Duration::from_millis(1);

/// A request sent to the server and not yet answered.
struct Pending {
    buffer_length: u32,
    dir_in: bool,
    partial: Vec<u8>,
    request: Request,
    usbip_seq: u32,
}

/// What a server sequence number currently stands for.
enum Slot {
    Live(Pending),
    /// The request was cancelled at the given time. A late reply is dropped.
    Orphan(Instant),
}

/// The in-flight table, shared by all threads.
#[derive(Default)]
struct State {
    by_usbip: HashMap<u32, u16>,
    next_seq: u16,
    slots: HashMap<u16, Slot>,
}

/// One bridged device.
pub(crate) struct Bridge<'a> {
    device: &'a Notification,
    server: Mutex<TcpStream>,
    state: Mutex<State>,
    stop: AtomicBool,
    vhci: Mutex<UnixStream>,
}

impl<'a> Bridge<'a> {
    pub(crate) fn new(device: &'a Notification, server: TcpStream, vhci: UnixStream) -> Self {
        Self {
            device,
            server: Mutex::new(server),
            state: Mutex::default(),
            stop: AtomicBool::new(false),
            vhci: Mutex::new(vhci),
        }
    }

    /// Runs until either side closes. Returns the error that ended it.
    pub(crate) fn run(&self) -> Result<()> {
        let mut vhci_rx = self.lock_vhci().try_clone().map_err(Error::VhciSocket)?;
        let mut server_rx = self
            .lock_server()
            .try_clone()
            .map_err(Error::ServerSocket)?;
        thread::scope(|s| {
            let down = s.spawn(|| self.finish(self.downstream(&mut server_rx)));
            let reaper = s.spawn(|| self.reaper());
            let up = self.finish(self.upstream(&mut vhci_rx));
            let down = down.join().expect("downstream thread panicked");
            reaper.join().expect("reaper thread panicked");
            up.and(down)
        })
    }

    /// Makes `run` return. In-flight URBs are not completed.
    pub(crate) fn stop(&self) {
        let _ = self.finish(Ok(()));
    }

    fn deliver(&self, reply: &Reply<'_>) -> Result<()> {
        reply
            .write(&mut *self.lock_vhci())
            .map_err(Error::VhciSocket)
    }

    /// Reads server replies and completes the matching URBs.
    fn downstream(&self, rx: &mut TcpStream) -> Result<()> {
        loop {
            let h = match ReplyHeader::read(rx) {
                Ok(h) => h,
                Err(_) if self.stop.load(Ordering::Relaxed) => return Ok(()),
                Err(e) => return Err(Error::ServerSocket(e)),
            };
            let mut data = vec![0; h.length as usize];
            rx.read_exact(&mut data).map_err(Error::ServerSocket)?;
            self.on_reply(&h, data)?;
        }
    }

    /// Shuts both sockets down when one side ends so the other threads end.
    fn finish(&self, result: Result<()>) -> Result<()> {
        if !self.stop.swap(true, Ordering::Relaxed) {
            let _ = self.lock_server().shutdown(Shutdown::Both);
            let _ = self.lock_vhci().shutdown(Shutdown::Both);
        }
        result
    }

    fn lock_server(&self) -> std::sync::MutexGuard<'_, TcpStream> {
        self.server.lock().expect("server socket lock poisoned")
    }

    fn lock_state(&self) -> std::sync::MutexGuard<'_, State> {
        self.state.lock().expect("state lock poisoned")
    }

    fn lock_vhci(&self) -> std::sync::MutexGuard<'_, UnixStream> {
        self.vhci.lock().expect("vhci socket lock poisoned")
    }

    fn on_reply(&self, h: &ReplyHeader, data: Vec<u8>) -> Result<()> {
        let mut state = self.lock_state();
        let Some(slot) = state.slots.get_mut(&h.seq) else {
            debug!("reply for unknown seq {} op {:#06x}, skipped", h.seq, h.op);
            return Ok(());
        };
        let Slot::Live(p) = slot else {
            state.slots.remove(&h.seq);
            debug!("late reply for unlinked seq {}, dropped", h.seq);
            return Ok(());
        };
        match h.status {
            status::PARTIAL => {
                p.partial.extend_from_slice(&data);
                return Ok(());
            }
            status::RETRY => {
                let bytes = p.request.encode();
                drop(state);
                thread::sleep(RETRY_DELAY);
                return self.send(&bytes);
            }
            _ => {}
        }
        let Some(Slot::Live(mut p)) = state.slots.remove(&h.seq) else {
            unreachable!("slot was live above");
        };
        state.by_usbip.remove(&p.usbip_seq);
        drop(state);

        let status = match h.status {
            status::OK => 0,
            status::STALL => errno::EPIPE,
            status::BABBLE => errno::EOVERFLOW,
            _ => errno::EPROTO,
        };
        p.partial.extend_from_slice(&data);
        let (actual, data) = if p.dir_in {
            let n = p.partial.len().min(p.buffer_length as usize);
            (n as u32, &p.partial[..n])
        } else {
            (if status == 0 { p.buffer_length } else { 0 }, &[][..])
        };
        debug!(
            "ret seq {} usbip {} status {:#06x} -> {status} actual {actual}",
            h.seq, p.usbip_seq, h.status
        );

        self.deliver(&Reply::Submit {
            actual,
            data,
            seqnum: p.usbip_seq,
            status,
        })
    }

    fn on_submit(&self, s: Submit) -> Result<()> {
        let reject = |status| {
            self.deliver(&Reply::Submit {
                actual: 0,
                data: &[],
                seqnum: s.seqnum,
                status,
            })
        };
        if s.iso_packets > 0 {
            return reject(errno::EXDEV);
        }
        let endpoint = if s.ep == 0 {
            None
        } else {
            let address = s.ep | if s.dir_in { 0x80 } else { 0 };
            match self.device.endpoints.get(&address) {
                Some(e) if e.transfer != Transfer::Isochronous => Some((address, *e)),
                Some(_) => return reject(errno::EXDEV),
                None => {
                    debug!("submit to unknown endpoint {address:#04x}");
                    return reject(errno::EPIPE);
                }
            }
        };

        let mut state = self.lock_state();
        let seq = state.allocate();
        let request = match endpoint {
            None => self.device.control(seq, s.setup, &s.data),
            Some((address, e)) => self
                .device
                .transfer(seq, address, e, s.buffer_length, &s.data),
        };
        debug!(
            "submit usbip {} -> seq {seq} ep {:#04x} in {} len {} setup {:02x?}",
            s.seqnum, s.ep, s.dir_in, s.buffer_length, s.setup
        );
        let bytes = request.encode();
        state.by_usbip.insert(s.seqnum, seq);
        state.slots.insert(
            seq,
            Slot::Live(Pending {
                buffer_length: s.buffer_length,
                dir_in: s.dir_in,
                partial: Vec::new(),
                request,
                usbip_seq: s.seqnum,
            }),
        );
        drop(state);
        self.send(&bytes)
    }

    /// Cancels the request on the server and completes the unlink without
    /// waiting, like the vendor driver. The server never answers a cancel.
    fn on_unlink(&self, seqnum: u32, target: u32) -> Result<()> {
        let mut state = self.lock_state();
        let seq = state.by_usbip.remove(&target);
        let cancel = seq.and_then(|seq| {
            let slot = state.slots.get_mut(&seq)?;
            let Slot::Live(p) = slot else {
                return None;
            };
            let frame = p.request.cancel();
            *slot = Slot::Orphan(Instant::now());
            Some(frame)
        });
        drop(state);
        debug!("unlink usbip {target} (seq {seq:?}) by {seqnum}");
        // Without a cancel the URB has already been given back.
        let status = match cancel {
            Some(frame) => {
                self.send(&frame)?;
                errno::ECONNRESET
            }
            None => 0,
        };
        self.deliver(&Reply::Unlink { seqnum, status })
    }

    /// Frees the sequence numbers of requests cancelled long ago.
    fn reaper(&self) {
        while !self.stop.load(Ordering::Relaxed) {
            thread::sleep(REAP_INTERVAL);
            self.lock_state().slots.retain(
                |_, slot| !matches!(slot, Slot::Orphan(since) if since.elapsed() > ORPHAN_TTL),
            );
        }
    }

    fn send(&self, frame: &[u8]) -> Result<()> {
        self.lock_server()
            .write_all(frame)
            .map_err(Error::ServerSocket)
    }

    /// Reads URB commands from `vhci_hcd` and forwards them.
    fn upstream(&self, rx: &mut UnixStream) -> Result<()> {
        loop {
            let cmd = match Command::read(rx) {
                Ok(Some(cmd)) => cmd,
                Ok(None) => return Ok(()),
                Err(_) if self.stop.load(Ordering::Relaxed) => return Ok(()),
                Err(e) => return Err(e),
            };
            match cmd {
                Command::Submit(s) => self.on_submit(s)?,
                Command::Unlink { seqnum, target } => self.on_unlink(seqnum, target)?,
            }
        }
    }
}

impl State {
    /// The next sequence number that is not in flight. 0 is never used.
    fn allocate(&mut self) -> u16 {
        loop {
            self.next_seq = self.next_seq.wrapping_add(1);
            if self.next_seq != 0 && !self.slots.contains_key(&self.next_seq) {
                return self.next_seq;
            }
        }
    }
}
