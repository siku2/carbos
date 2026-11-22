//! JCP, the UDP control protocol of Silex device servers.
//!
//! Every request starts with a 0x58 byte header. Commands are ASCII text
//! with their binary arguments appended directly after the text.

use std::io;
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr, ToSocketAddrs, UdpSocket};
use std::time::{Duration, Instant};

use zerocopy::byteorder::{BE, U16};
use zerocopy::{FromBytes, FromZeros, Immutable, IntoBytes, KnownLayout, Unaligned};

use log::debug;

use crate::error::{Error, Result};
use crate::sxuptp::Notification;

pub(crate) const PORT: u16 = 19541;

const CMD_CONNECT: &str = "EXEC SCANNER CONNECT:";
const CMD_DISCONNECT: &str = "EXEC SCANNER DISCONNECT:";
const CMD_LIST: &str = "GET USB_DEVICE_LIST_EX";
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

/// The header of every request.
#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct RequestHeader {
    kind: U16<BE>,
    /// The search rule for searches, the session (1) for commands.
    session: U16<BE>,
    /// Command text with its arguments appended, zero padded.
    text: [u8; TEXT_LEN],
    offset: U16<BE>,
    length: U16<BE>,
}

/// The start of a search reply.
#[repr(C)]
#[derive(FromBytes, Immutable, KnownLayout, Unaligned)]
struct SearchReply {
    kind: U16<BE>,
    rule: U16<BE>,
    reserved1: [u8; 0x20],
    model: [u8; 0x14],
    mac: [u8; 6],
    reserved2: [u8; 2],
    flags: U16<BE>,
    ipv4: [u8; 4],
}

/// The header of every command reply chunk.
#[repr(C)]
#[derive(FromBytes, Immutable, KnownLayout, Unaligned)]
struct ChunkHeader {
    kind: U16<BE>,
    more: U16<BE>,
    offset: U16<BE>,
    length: U16<BE>,
}

/// The verdict a server puts at the start of a command reply.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Verdict {
    Deny,
    Ng,
}

impl Verdict {
    fn of(reply: &[u8]) -> Option<Self> {
        let mut head = [0; 4];
        let n = reply.len().min(4);
        head[..n].copy_from_slice(&reply[..n]);
        head.make_ascii_lowercase();
        match &head {
            [b'e', b'r', ..] | [b'n', b'g', ..] => Some(Self::Ng),
            [b'd', b'n', ..] | b"deny" => Some(Self::Deny),
            _ => None,
        }
    }
}

/// A connection to the JCP port of one server.
pub(crate) struct Client {
    local: IpAddr,
    mac: [u8; 6],
    server: SocketAddr,
    sock: UdpSocket,
}

impl Client {
    /// Connects to the first address of `host` that answers a search.
    ///
    /// `host` is a host name or an IP literal.
    pub(crate) fn open(host: &str) -> Result<Self> {
        let addrs = (host, PORT)
            .to_socket_addrs()
            .map_err(|err| Error::ServerResolve(host.to_owned(), err))?;
        let mut last = None;
        for addr in addrs {
            match Self::new(addr) {
                Ok(client) => return Ok(client),
                Err(err) => {
                    debug!("{addr}: {err}");
                    last = Some(err);
                }
            }
        }
        Err(match last {
            Some(err) => Error::ServerUnreachable(host.to_owned(), Box::new(err)),
            None => Error::ServerUnresolved(host.to_owned()),
        })
    }

    /// Reserves the device on `port` and waits for its notification.
    pub(crate) fn connect(&self, port: &str) -> Result<Notification> {
        let notify = Notification::bind()?;
        let mut args = self.prefix(self.local)?;
        args.extend_from_slice(port.as_bytes());
        args.push(0);
        args.extend_from_slice(&crate::sxuptp::PORT.to_be_bytes());
        args.push(0);
        self.command(CMD_CONNECT, &args, Some(&[0]))?;
        Notification::receive(&notify, self.server.ip())
    }

    pub(crate) fn devices(&self) -> Result<Vec<Device>> {
        let buf = self.command(CMD_LIST, &[], None)?;
        Device::parse_list(&buf)
    }

    /// Releases the reservation `owner` holds on `port`.
    pub(crate) fn disconnect(&self, port: &str, owner: IpAddr) -> Result<()> {
        let mut args = self.prefix(owner)?;
        args.extend_from_slice(port.as_bytes());
        self.command(CMD_DISCONNECT, &args, None).map(drop)
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

    pub(crate) fn local(&self) -> IpAddr {
        self.local
    }

    pub(crate) fn server(&self) -> IpAddr {
        self.server.ip()
    }

    fn new(server: SocketAddr) -> Result<Self> {
        if server.is_ipv6() {
            return Err(Error::JcpIpv6NotImplemented);
        }
        let sock = UdpSocket::bind(unspecified(server)).map_err(Error::JcpSocket)?;
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

    /// Runs one command with the stop-and-wait chunk exchange.
    fn command(&self, text: &'static str, args: &[u8], data: Option<&[u8]>) -> Result<Vec<u8>> {
        let mut header = RequestHeader::new_zeroed();
        let n = text.len() + args.len();
        if n > TEXT_LEN {
            return Err(Error::JcpArgsTooLong { command: text });
        }
        header.text[..text.len()].copy_from_slice(text.as_bytes());
        header.text[text.len()..n].copy_from_slice(args);
        header.session.set(1);

        let mut request = |kind: Kind, offset: usize, payload: &[u8]| {
            header.kind.set(kind as u16);
            header.offset.set(offset as u16);
            header.length.set(if payload.is_empty() {
                MAX_CHUNK
            } else {
                payload.len() as u16
            });
            let mut p = header.as_bytes().to_vec();
            p.extend_from_slice(payload);
            p
        };

        let first = request(Kind::Command, 0, data.unwrap_or_default());
        let mut out = Vec::new();
        let mut reply = self.exchange(&first, text)?;
        loop {
            let (chunk, rest) = ChunkHeader::ref_from_prefix(&reply)
                .map_err(|_| Error::JcpShortReply { command: text })?;
            let data = rest
                .get(..usize::from(chunk.length.get()))
                .ok_or(Error::JcpShortReply { command: text })?;
            if usize::from(chunk.offset.get()) != out.len() {
                return Err(Error::JcpBadOffset { command: text });
            }
            out.extend_from_slice(data);
            if chunk.more.get() == 0 {
                break;
            }
            reply = self.exchange(&request(Kind::Next, out.len(), &[]), text)?;
        }
        self.exchange(&request(Kind::End, out.len(), &[]), text)?;

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
                    Ok((n, src)) if src == self.server => {
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
    fn prefix(&self, client: IpAddr) -> Result<Vec<u8>> {
        let IpAddr::V4(client) = client else {
            return Err(Error::JcpIpv6NotImplemented);
        };
        let mut p = vec![1, 6];
        p.extend_from_slice(&self.mac);
        p.extend_from_slice(&client.octets());
        Ok(p)
    }

    /// Sends a search and returns the server MAC.
    fn search(&self) -> Result<[u8; 6]> {
        let mut req = RequestHeader::new_zeroed();
        req.kind.set(Kind::Search as u16);
        req.session.set(RULE);
        let reply = self.exchange(req.as_bytes(), "search")?;
        let (r, _) = SearchReply::ref_from_prefix(&reply).map_err(|_| Error::JcpBadSearchReply)?;
        if r.kind.get() != 2 || r.rule.get() != RULE {
            return Err(Error::JcpBadSearchReply);
        }
        Ok(r.mac)
    }
}

/// One USB port of a server, as reported by the device list.
pub(crate) struct Device {
    pub(crate) location: String,
    pub(crate) name: String,
    pub(crate) owner: Option<IpAddr>,
    pub(crate) pid: u16,
    pub(crate) port: String,
    pub(crate) present: bool,
    pub(crate) serial: String,
    pub(crate) vid: u16,
}

impl Device {
    pub(crate) fn matches(&self, selector: &str) -> bool {
        self.port == selector || (!self.serial.is_empty() && self.serial == selector)
    }

    /// Parses one `GET USB_DEVICE_LIST_EX` record.
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
            owner: (!owner.is_unspecified()).then_some(IpAddr::V4(owner)),
            pid,
            port,
            present: status & 0x100 != 0,
            serial,
            vid,
        })
    }

    /// Parses a `GET USB_DEVICE_LIST_EX` reply.
    fn parse_list(buf: &[u8]) -> Result<Vec<Self>> {
        let mut r = Reader { buf, pos: 0 };
        let count = r.u8()?;
        (0..count).map(|_| Self::parse_ex(&mut r)).collect()
    }
}

/// A cursor over a device list reply.
struct Reader<'a> {
    buf: &'a [u8],
    pos: usize,
}

impl Reader<'_> {
    fn array<const N: usize>(&mut self) -> Result<[u8; N]> {
        Ok(self.array_slice(N)?.try_into().expect("slice has length N"))
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
        self.array_slice(n).map(drop)
    }

    fn array_slice(&mut self, n: usize) -> Result<&[u8]> {
        let bytes = self
            .buf
            .get(self.pos..self.pos + n)
            .ok_or(Error::JcpBadDeviceList)?;
        self.pos += n;
        Ok(bytes)
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
fn local_addr_towards(server: SocketAddr) -> Result<IpAddr> {
    let sock = UdpSocket::bind(unspecified(server)).map_err(Error::JcpSocket)?;
    sock.connect(server).map_err(Error::JcpSocket)?;
    Ok(sock.local_addr().map_err(Error::JcpSocket)?.ip())
}

/// The wildcard address of the same family as `addr`, port 0.
fn unspecified(addr: SocketAddr) -> SocketAddr {
    match addr {
        SocketAddr::V4(_) => (Ipv4Addr::UNSPECIFIED, 0).into(),
        SocketAddr::V6(_) => (Ipv6Addr::UNSPECIFIED, 0).into(),
    }
}
