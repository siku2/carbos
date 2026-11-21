//! JCP, the UDP control protocol of Silex device servers.
//!
//! Every request starts with a 0x58 byte header. Commands are ASCII text
//! with their binary arguments appended directly after the text.

use std::io;
use std::net::{Ipv4Addr, SocketAddr, SocketAddrV4, UdpSocket};
use std::time::{Duration, Instant};

use crate::error::{Error, Result};
use crate::sxuptp::Notification;

pub(crate) const PORT: u16 = 19541;

const CMD_CONNECT: &str = "EXEC SCANNER CONNECT:";
const CMD_DISCONNECT: &str = "EXEC SCANNER DISCONNECT:";
const CMD_LIST: &str = "GET USB_DEVICE_LIST_EX";
const HEADER_LEN: usize = 0x58;
const MAX_CHUNK: u16 = 0x200;
const RULE: u16 = 0x9506;
const TEXT_LEN: usize = 0x50;
const TIMEOUT: Duration = Duration::from_secs(1);
const TRIES: usize = 4;

/// Packet types in the first header field.
#[derive(Clone, Copy)]
enum Kind {
    Command = 1,
    End = 3,
    Next = 2,
    Search = 4,
}

/// The verdict a server puts at the start of a command reply.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Verdict {
    Deny,
    Ng,
}

/// A connection to the JCP port of one server.
pub(crate) struct Client {
    local: Ipv4Addr,
    mac: [u8; 6],
    server: SocketAddrV4,
    sock: UdpSocket,
}

/// One USB port of a server, as reported by the device list.
pub(crate) struct Device {
    pub(crate) location: String,
    pub(crate) name: String,
    pub(crate) owner: Option<Ipv4Addr>,
    pub(crate) pid: u16,
    pub(crate) port: String,
    pub(crate) present: bool,
    pub(crate) serial: String,
    pub(crate) vid: u16,
}

impl Client {
    pub(crate) fn new(server: Ipv4Addr) -> Result<Self> {
        let server = SocketAddrV4::new(server, PORT);
        let sock = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).map_err(Error::JcpSocket)?;
        sock.set_read_timeout(Some(TIMEOUT))
            .map_err(Error::JcpSocket)?;
        let local = local_addr_towards(server)?;
        let mut client = Self {
            local,
            mac: [0; 6],
            server,
            sock,
        };
        client.mac = client.search()?;
        Ok(client)
    }

    /// Reserves the device on `port` and waits for its notification.
    pub(crate) fn connect(&self, port: &str) -> Result<Notification> {
        let notify = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, crate::sxuptp::PORT))
            .map_err(Error::NotifySocket)?;
        let mut args = self.prefix(self.local);
        args.extend_from_slice(port.as_bytes());
        args.push(0);
        args.extend_from_slice(&crate::sxuptp::PORT.to_be_bytes());
        args.push(0);
        self.command(CMD_CONNECT, &args, Some(&[0]))?;
        Notification::receive(&notify, *self.server.ip())
    }

    /// Releases the reservation `owner` holds on `port`.
    pub(crate) fn disconnect(&self, port: &str, owner: Ipv4Addr) -> Result<()> {
        let mut args = self.prefix(owner);
        args.extend_from_slice(port.as_bytes());
        self.command(CMD_DISCONNECT, &args, None).map(drop)
    }

    pub(crate) fn devices(&self) -> Result<Vec<Device>> {
        let buf = self.command(CMD_LIST, &[], None)?;
        Device::parse_list(&buf)
    }

    /// The device on the port or with the serial number `selector`.
    pub(crate) fn find(&self, selector: &str) -> Result<Device> {
        self.devices()?
            .into_iter()
            .find(|d| d.matches(selector))
            .ok_or_else(|| Error::NoDevice {
                selector: selector.to_owned(),
            })
    }

    pub(crate) fn local(&self) -> Ipv4Addr {
        self.local
    }

    /// Runs one command with the stop-and-wait chunk exchange.
    fn command(&self, text: &'static str, args: &[u8], data: Option<&[u8]>) -> Result<Vec<u8>> {
        let mut cmd = Vec::with_capacity(TEXT_LEN);
        cmd.extend_from_slice(text.as_bytes());
        cmd.extend_from_slice(args);
        if cmd.len() > TEXT_LEN {
            return Err(Error::JcpArgsTooLong { command: text });
        }
        cmd.resize(TEXT_LEN, 0);

        let request = |kind: Kind, offset: u16, length: u16, payload: &[u8]| {
            let mut p = Vec::with_capacity(HEADER_LEN + payload.len());
            p.extend_from_slice(&(kind as u16).to_be_bytes());
            p.extend_from_slice(&1u16.to_be_bytes());
            p.extend_from_slice(&cmd);
            p.extend_from_slice(&offset.to_be_bytes());
            p.extend_from_slice(&length.to_be_bytes());
            p.extend_from_slice(payload);
            p
        };

        let first = match data {
            Some(d) => request(Kind::Command, 0, d.len() as u16, d),
            None => request(Kind::Command, 0, MAX_CHUNK, &[]),
        };
        let mut out = Vec::new();
        let mut reply = self.exchange(&first, text)?;
        loop {
            let chunk = Chunk::parse(&reply, text)?;
            if usize::from(chunk.offset) != out.len() {
                return Err(Error::JcpBadOffset { command: text });
            }
            out.extend_from_slice(chunk.data);
            if !chunk.more {
                break;
            }
            let next = request(Kind::Next, out.len() as u16, MAX_CHUNK, &[]);
            reply = self.exchange(&next, text)?;
        }
        let end = request(Kind::End, out.len() as u16, MAX_CHUNK, &[]);
        self.exchange(&end, text)?;

        match Verdict::of(&out) {
            Some(verdict) => Err(Error::JcpRejected {
                command: text,
                verdict,
            }),
            None => Ok(out),
        }
    }

    /// Sends `packet` and returns the first reply from the server.
    fn exchange(&self, packet: &[u8], command: &'static str) -> Result<Vec<u8>> {
        let mut buf = vec![0; 0x1000];
        for _ in 0..TRIES {
            self.sock
                .send_to(packet, self.server)
                .map_err(Error::JcpSocket)?;
            let deadline = Instant::now() + TIMEOUT;
            while Instant::now() < deadline {
                match self.sock.recv_from(&mut buf) {
                    Ok((n, SocketAddr::V4(src))) if src == self.server => {
                        buf.truncate(n);
                        return Ok(buf);
                    }
                    Ok(_) => {}
                    Err(e) if is_timeout(&e) => break,
                    Err(e) => return Err(Error::JcpSocket(e)),
                }
            }
        }
        Err(Error::JcpTimeout { command })
    }

    /// The 12 byte prefix: tag 1, the server MAC and a client address.
    fn prefix(&self, client: Ipv4Addr) -> Vec<u8> {
        let mut p = vec![1, 6];
        p.extend_from_slice(&self.mac);
        p.extend_from_slice(&client.octets());
        p
    }

    /// Sends a search and returns the server MAC.
    fn search(&self) -> Result<[u8; 6]> {
        let mut req = vec![0; HEADER_LEN];
        req[0..2].copy_from_slice(&(Kind::Search as u16).to_be_bytes());
        req[2..4].copy_from_slice(&RULE.to_be_bytes());
        let reply = self.exchange(&req, "search")?;
        if reply.len() < 0x46 || reply[0..2] != [0, 2] || reply[2..4] != RULE.to_be_bytes() {
            return Err(Error::JcpBadSearchReply);
        }
        let mut mac = [0; 6];
        mac.copy_from_slice(&reply[0x38..0x3e]);
        Ok(mac)
    }
}

impl Device {
    /// Parses a `GET USB_DEVICE_LIST_EX` reply.
    fn parse_list(buf: &[u8]) -> Result<Vec<Self>> {
        let mut r = Reader { buf, pos: 0 };
        let count = r.u8()?;
        (0..count).map(|_| Self::parse_ex(&mut r)).collect()
    }

    fn parse_ex(r: &mut Reader<'_>) -> Result<Self> {
        let port = r.cstr()?;
        let name = r.cstr()?.trim_end_matches(['\r', '\n']).to_owned();
        let owner = Ipv4Addr::from(r.array::<4>()?);
        let status = u16::from_le_bytes(r.array()?);
        r.skip(2)?;
        let vid = u16::from_be_bytes(r.array()?);
        let pid = u16::from_be_bytes(r.array()?);
        let location = fixed_str(&r.array::<16>()?);
        r.skip(2)?;
        let serial = fixed_str(&r.array::<64>()?);
        r.skip(4)?;
        Ok(Self {
            location,
            name,
            owner: (!owner.is_unspecified()).then_some(owner),
            pid,
            port,
            present: status & 0x100 != 0,
            serial,
            vid,
        })
    }

    pub(crate) fn matches(&self, selector: &str) -> bool {
        self.port == selector || (!self.serial.is_empty() && self.serial == selector)
    }
}

impl Verdict {
    fn of(reply: &[u8]) -> Option<Self> {
        let head: Vec<u8> = reply.iter().take(4).map(u8::to_ascii_lowercase).collect();
        if head.starts_with(b"er") || head.starts_with(b"ng") {
            Some(Self::Ng)
        } else if head.starts_with(b"dn") || head.starts_with(b"deny") {
            Some(Self::Deny)
        } else {
            None
        }
    }
}

struct Chunk<'a> {
    data: &'a [u8],
    more: bool,
    offset: u16,
}

impl<'a> Chunk<'a> {
    fn parse(reply: &'a [u8], command: &'static str) -> Result<Self> {
        if reply.len() < 8 {
            return Err(Error::JcpShortReply { command });
        }
        let more = u16::from_be_bytes([reply[2], reply[3]]) != 0;
        let offset = u16::from_be_bytes([reply[4], reply[5]]);
        let length = usize::from(u16::from_be_bytes([reply[6], reply[7]]));
        let data = reply
            .get(8..8 + length)
            .ok_or(Error::JcpShortReply { command })?;
        Ok(Self { data, more, offset })
    }
}

struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl Reader<'_> {
    fn array<const N: usize>(&mut self) -> Result<[u8; N]> {
        let bytes = self
            .buf
            .get(self.pos..self.pos + N)
            .ok_or(Error::JcpBadDeviceList)?;
        self.pos += N;
        Ok(bytes.try_into().expect("slice has length N"))
    }

    fn cstr(&mut self) -> Result<String> {
        let rest = self.buf.get(self.pos..).ok_or(Error::JcpBadDeviceList)?;
        let len = rest
            .iter()
            .position(|&b| b == 0)
            .ok_or(Error::JcpBadDeviceList)?;
        self.pos += len + 1;
        Ok(String::from_utf8_lossy(&rest[..len]).into_owned())
    }

    fn skip(&mut self, n: usize) -> Result<()> {
        if self.pos + n > self.buf.len() {
            return Err(Error::JcpBadDeviceList);
        }
        self.pos += n;
        Ok(())
    }

    fn u8(&mut self) -> Result<u8> {
        Ok(self.array::<1>()?[0])
    }
}

fn fixed_str(bytes: &[u8]) -> String {
    let len = bytes.iter().position(|&b| b == 0).unwrap_or(bytes.len());
    String::from_utf8_lossy(&bytes[..len]).into_owned()
}

pub(crate) fn is_timeout(e: &io::Error) -> bool {
    matches!(
        e.kind(),
        io::ErrorKind::WouldBlock | io::ErrorKind::TimedOut
    )
}

/// The local address the kernel picks for traffic to `server`.
fn local_addr_towards(server: SocketAddrV4) -> Result<Ipv4Addr> {
    let sock = UdpSocket::bind((Ipv4Addr::UNSPECIFIED, 0)).map_err(Error::JcpSocket)?;
    sock.connect(server).map_err(Error::JcpSocket)?;
    match sock.local_addr().map_err(Error::JcpSocket)? {
        SocketAddr::V4(a) => Ok(*a.ip()),
        SocketAddr::V6(_) => Err(Error::JcpBadSearchReply),
    }
}
