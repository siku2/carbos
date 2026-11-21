//! SXUPTP, the USB transport of Silex device servers.
//!
//! The server announces a reserved device with a UDP notification. The
//! client then opens a TCP session and sends one frame per USB transfer.
//! Frame headers are big-endian.

/// Reply status values.
pub(crate) mod status {
    pub(crate) const BABBLE: u16 = 0xfffc;
    pub(crate) const OK: u16 = 0x0000;
    pub(crate) const PARTIAL: u16 = 0x0002;
    pub(crate) const RETRY: u16 = 0xfffe;
    pub(crate) const STALL: u16 = 0xfffd;
}

use std::collections::BTreeMap;
use std::io::{self, Read};
use std::net::{Ipv4Addr, SocketAddr, UdpSocket};
use std::time::{Duration, Instant};

use crate::error::{Error, Result};
use crate::jcp::is_timeout;

pub(crate) const PORT: u16 = 19540;

const CANCEL: u16 = 0x4000;
const MAGICS: [u16; 6] = [0x2908, 0x2988, 0x29eb, 0x29ef, 0x2b08, 0x2beb];
const NOTIFY_TIMEOUT: Duration = Duration::from_secs(10);
const OUT: u16 = 0x8000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Speed {
    Full,
    High,
    Low,
    Super,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Transfer {
    Bulk,
    Interrupt,
    Isochronous,
}

/// An endpoint from the configuration descriptor.
#[derive(Clone, Copy, Debug)]
pub(crate) struct Endpoint {
    pub(crate) interval: u8,
    pub(crate) max_packet: u16,
    pub(crate) transfer: Transfer,
}

/// The device announcement a server sends after a connect.
pub(crate) struct Notification {
    pub(crate) addr: u8,
    pub(crate) bus: u8,
    pub(crate) crypto: u32,
    /// Endpoints keyed by address including the direction bit.
    pub(crate) endpoints: BTreeMap<u8, Endpoint>,
    pub(crate) magic: u16,
    pub(crate) server: Ipv4Addr,
    pub(crate) sessions: u8,
    pub(crate) speed: Speed,
    pub(crate) tcp_port: u16,
    pub(crate) version: u16,
}

/// The fixed part of every reply.
pub(crate) struct ReplyHeader {
    pub(crate) length: u32,
    pub(crate) op: u16,
    pub(crate) seq: u16,
    pub(crate) status: u16,
}

/// A request frame ready to send, with the header kept for cancelling.
pub(crate) struct Request {
    bytes: Vec<u8>,
    header_len: usize,
}

impl Notification {
    /// Waits for the notification of a device on `server`.
    pub(crate) fn receive(sock: &UdpSocket, server: Ipv4Addr) -> Result<Self> {
        sock.set_read_timeout(Some(Duration::from_millis(500)))
            .map_err(Error::NotifySocket)?;
        let deadline = Instant::now() + NOTIFY_TIMEOUT;
        let mut buf = vec![0; 0x400];
        while Instant::now() < deadline {
            match sock.recv_from(&mut buf) {
                Ok((n, SocketAddr::V4(src))) if *src.ip() == server => {
                    if let Some(n) = Self::parse(&buf[..n]) {
                        return n;
                    }
                }
                Ok(_) => {}
                Err(e) if is_timeout(&e) => {}
                Err(e) => return Err(Error::NotifySocket(e)),
            }
        }
        Err(Error::NotifyTimeout)
    }

    /// Returns `None` for datagrams that are not notifications.
    fn parse(b: &[u8]) -> Option<Result<Self>> {
        let magic = u16::from_be_bytes([*b.first()?, *b.get(1)?]);
        if !MAGICS.contains(&magic) {
            return None;
        }
        Some(Self::parse_body(b, magic))
    }

    fn parse_body(b: &[u8], magic: u16) -> Result<Self> {
        if b.len() < 0x89 {
            return Err(Error::NotifyTooShort { len: b.len() });
        }
        let version = std::str::from_utf8(&b[8..12])
            .ok()
            .and_then(|s| u16::from_str_radix(s, 16).ok())
            .ok_or(Error::NotifyBadVersion)?
            .clamp(0x200, 0x23f);
        let speed = match b[0x30].to_ascii_uppercase() {
            b'L' => Speed::Low,
            b'F' => Speed::Full,
            b'H' => Speed::High,
            b'S' => Speed::Super,
            other => return Err(Error::NotifyBadSpeed(other)),
        };
        let tcp_port = match u16::from_be_bytes([b[0x20], b[0x21]]) {
            0 => PORT,
            p => p,
        };
        Ok(Self {
            addr: b[3],
            bus: b[2],
            crypto: u32::from_be_bytes([b[0x0c], b[0x0d], b[0x0e], b[0x0f]]),
            endpoints: parse_endpoints(&b[0x80..]),
            magic,
            server: Ipv4Addr::new(b[4], b[5], b[6], b[7]),
            sessions: b[0x10],
            speed,
            tcp_port,
            version,
        })
    }

    /// Builds a control request. `setup` is the raw little-endian setup packet.
    pub(crate) fn control(&self, seq: u16, setup: [u8; 8], out: &[u8]) -> Request {
        let dir_in = setup[0] & 0x80 != 0;
        let length = if dir_in {
            u32::from(u16::from_le_bytes([setup[6], setup[7]]))
        } else {
            out.len() as u32
        };
        let mut b = self.header(if dir_in { 1 } else { 1 | OUT }, seq, 0);
        b.extend_from_slice(&8u16.to_be_bytes());
        b.extend_from_slice(&setup[0..2]);
        b.extend_from_slice(&u16::from_le_bytes([setup[2], setup[3]]).to_be_bytes());
        b.extend_from_slice(&u16::from_le_bytes([setup[4], setup[5]]).to_be_bytes());
        b.extend_from_slice(&length.to_be_bytes());
        Request::finish(b, if dir_in { &[] } else { out })
    }

    /// Builds a bulk or interrupt request for endpoint address `ep`.
    pub(crate) fn transfer(
        &self,
        seq: u16,
        ep: u8,
        e: Endpoint,
        length: u32,
        out: &[u8],
    ) -> Request {
        let dir_in = ep & 0x80 != 0;
        let op = match e.transfer {
            Transfer::Interrupt => 2,
            Transfer::Bulk | Transfer::Isochronous => 3,
        };
        let mut b = self.header(if dir_in { op } else { op | OUT }, seq, ep);
        b.extend_from_slice(&(0x8000 | e.max_packet).to_be_bytes());
        let f12 = if e.transfer == Transfer::Interrupt {
            u16::from(e.interval)
        } else {
            0
        };
        b.extend_from_slice(&f12.to_be_bytes());
        let length = if dir_in { length } else { out.len() as u32 };
        b.extend_from_slice(&length.to_be_bytes());
        Request::finish(b, if dir_in { &[] } else { out })
    }

    fn header(&self, op: u16, seq: u16, ep: u8) -> Vec<u8> {
        let mut b = Vec::with_capacity(22);
        b.extend_from_slice(&op.to_be_bytes());
        b.extend_from_slice(&seq.to_be_bytes());
        if self.magic != 0x2988 {
            b.extend_from_slice(&u16::from(self.bus).to_be_bytes());
        }
        b.push(self.addr);
        b.push(ep);
        b.extend_from_slice(&self.version.to_be_bytes());
        b
    }
}

impl ReplyHeader {
    pub(crate) fn read(r: &mut impl Read, legacy: bool) -> io::Result<Self> {
        let mut h = [0; 12];
        r.read_exact(&mut h[..if legacy { 12 } else { 10 }])?;
        Ok(Self {
            length: u32::from_be_bytes([h[6], h[7], h[8], h[9]]),
            op: u16::from_be_bytes([h[0], h[1]]),
            seq: u16::from_be_bytes([h[2], h[3]]),
            status: u16::from_be_bytes([h[4], h[5]]),
        })
    }
}

impl Request {
    pub(crate) fn bytes(&self) -> &[u8] {
        &self.bytes
    }

    /// The cancel frame: the same header with the cancel bit and length 0.
    pub(crate) fn cancel(&self) -> Vec<u8> {
        let mut c = self.bytes[..self.header_len].to_vec();
        let op = u16::from_be_bytes([c[0], c[1]]) | CANCEL;
        c[0..2].copy_from_slice(&op.to_be_bytes());
        let n = c.len();
        c[n - 4..].fill(0);
        c
    }

    fn finish(mut header: Vec<u8>, data: &[u8]) -> Self {
        let header_len = header.len();
        header.extend_from_slice(data);
        Self {
            bytes: header,
            header_len,
        }
    }
}

/// Reads endpoints from a configuration descriptor whose 16-bit fields are
/// big-endian.
fn parse_endpoints(config: &[u8]) -> BTreeMap<u8, Endpoint> {
    let total = config
        .get(2..4)
        .map_or(0, |t| usize::from(u16::from_be_bytes([t[0], t[1]])))
        .min(config.len());
    let mut endpoints = BTreeMap::new();
    let mut pos = 0;
    while pos + 2 <= total {
        let len = usize::from(config[pos]);
        if len < 2 || pos + len > total {
            break;
        }
        let d = &config[pos..pos + len];
        if d[1] == 5 && len >= 7 {
            let transfer = match d[3] & 3 {
                1 => Some(Transfer::Isochronous),
                2 => Some(Transfer::Bulk),
                3 => Some(Transfer::Interrupt),
                _ => None,
            };
            if let Some(transfer) = transfer {
                let max_packet = u16::from_be_bytes([d[4], d[5]]);
                endpoints.insert(
                    d[2],
                    Endpoint {
                        interval: d[6],
                        max_packet,
                        transfer,
                    },
                );
            }
        }
        pos += len;
    }
    endpoints
}
