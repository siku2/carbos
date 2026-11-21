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
use std::net::{IpAddr, Ipv4Addr, Ipv6Addr, UdpSocket};
use std::time::{Duration, Instant};

use zerocopy::byteorder::{BE, U16, U32};
use zerocopy::{FromBytes, FromZeros, Immutable, IntoBytes, KnownLayout, Unaligned};

use crate::error::{Error, Result};
use crate::jcp::is_timeout;

pub(crate) const PORT: u16 = 19540;

const CANCEL: u16 = 0x4000;
/// Notification commands. 0x2988 is the legacy dialect with a shorter
/// header, which is not supported.
const LEGACY: u16 = 0x2988;
const MAGICS: [u16; 5] = [0x2908, 0x29eb, 0x29ef, 0x2b08, 0x2beb];
const NOTIFY_TIMEOUT: Duration = Duration::from_secs(10);
const OUT: u16 = 0x8000;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum Speed {
    Full,
    High,
    Low,
    Super,
}

impl Speed {
    /// The `enum usb_device_speed` value.
    pub(crate) fn usb_number(self) -> u32 {
        match self {
            Self::Low => 1,
            Self::Full => 2,
            Self::High => 3,
            Self::Super => 5,
        }
    }
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

/// A USB endpoint descriptor with a big-endian `wMaxPacketSize`, as the
/// server sends it in notifications.
#[repr(C)]
#[derive(FromBytes, Immutable, KnownLayout, Unaligned)]
struct EndpointDescriptor {
    length: u8,
    descriptor_type: u8,
    address: u8,
    attributes: u8,
    max_packet: U16<BE>,
    interval: u8,
}

/// The fixed first 0x80 bytes of a notification. The configuration
/// descriptor follows.
#[repr(C)]
#[derive(FromBytes, Immutable, KnownLayout, Unaligned)]
struct RawNotification {
    magic: U16<BE>,
    bus: u8,
    addr: u8,
    server: [u8; 4],
    /// Four ASCII hex digits.
    version: [u8; 4],
    crypto: U32<BE>,
    sessions: u8,
    flags: u8,
    reserved1: [u8; 8],
    /// Only used for serial ports.
    mac: [u8; 6],
    /// 0 means [`PORT`].
    tcp_port: U16<BE>,
    serial_port: U16<BE>,
    reserved2: [u8; 12],
    /// The first character is the speed.
    location: [u8; 16],
    /// Device descriptor with big-endian 16-bit fields.
    device: [u8; 18],
    reserved3: [u8; 46],
}

/// The device announcement a server sends after a connect.
pub(crate) struct Notification {
    pub(crate) addr: u8,
    pub(crate) bus: u8,
    pub(crate) crypto: u32,
    /// Endpoints keyed by address including the direction bit.
    pub(crate) endpoints: BTreeMap<u8, Endpoint>,
    /// `None` when the server only gave an IPv6 address elsewhere.
    pub(crate) server: Option<Ipv4Addr>,
    pub(crate) sessions: u8,
    pub(crate) speed: Speed,
    pub(crate) tcp_port: u16,
    pub(crate) version: u16,
}

impl Notification {
    /// Binds the socket notifications arrive on, dual-stack if possible.
    pub(crate) fn bind() -> Result<UdpSocket> {
        UdpSocket::bind((Ipv6Addr::UNSPECIFIED, PORT))
            .or_else(|_| UdpSocket::bind((Ipv4Addr::UNSPECIFIED, PORT)))
            .map_err(Error::NotifySocket)
    }

    /// Waits for the notification of a device on `server`.
    pub(crate) fn receive(sock: &UdpSocket, server: IpAddr) -> Result<Self> {
        sock.set_read_timeout(Some(Duration::from_millis(500)))
            .map_err(Error::NotifySocket)?;
        let deadline = Instant::now() + NOTIFY_TIMEOUT;
        let mut buf = vec![0; 0x400];
        while Instant::now() < deadline {
            match sock.recv_from(&mut buf) {
                Ok((n, src)) if src.ip().to_canonical() == server.to_canonical() => {
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

    /// Builds a control request. `setup` is the raw little-endian setup packet.
    pub(crate) fn control(&self, seq: u16, setup: [u8; 8], out: &[u8]) -> Request {
        let dir_in = setup[0] & 0x80 != 0;
        let length = if dir_in {
            u32::from(u16::from_le_bytes([setup[6], setup[7]]))
        } else {
            out.len() as u32
        };
        let frame = ControlRequest {
            header: self.header(if dir_in { 1 } else { 1 | OUT }, seq, 0),
            f10: 8.into(),
            request_type: setup[0],
            request: setup[1],
            value: u16::from_le_bytes([setup[2], setup[3]]).into(),
            index: u16::from_le_bytes([setup[4], setup[5]]).into(),
            length: length.into(),
        };
        Request::new(Frame::Control(frame), if dir_in { &[] } else { out })
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
        let frame = TransferRequest {
            header: self.header(if dir_in { op } else { op | OUT }, seq, ep),
            f10: (0x8000 | e.max_packet).into(),
            f12: if e.transfer == Transfer::Interrupt {
                u16::from(e.interval)
            } else {
                0
            }
            .into(),
            length: if dir_in { length } else { out.len() as u32 }.into(),
        };
        Request::new(Frame::Transfer(frame), if dir_in { &[] } else { out })
    }

    fn header(&self, op: u16, seq: u16, ep: u8) -> RequestHeader {
        RequestHeader {
            op: op.into(),
            seq: seq.into(),
            bus: u16::from(self.bus).into(),
            addr: self.addr,
            ep,
            version: self.version.into(),
        }
    }

    /// Returns `None` for datagrams that are not notifications.
    fn parse(b: &[u8]) -> Option<Result<Self>> {
        let magic = u16::from_be_bytes([*b.first()?, *b.get(1)?]);
        if magic == LEGACY {
            return Some(Err(Error::LegacyServer));
        }
        MAGICS.contains(&magic).then(|| Self::parse_body(b))
    }

    fn parse_body(b: &[u8]) -> Result<Self> {
        let (raw, config) = RawNotification::ref_from_prefix(b)
            .map_err(|_| Error::NotifyTooShort { len: b.len() })?;
        let version = std::str::from_utf8(&raw.version)
            .ok()
            .and_then(|s| u16::from_str_radix(s, 16).ok())
            .ok_or(Error::NotifyBadVersion)?
            .clamp(0x200, 0x23f);
        let speed = match raw.location[0].to_ascii_uppercase() {
            b'L' => Speed::Low,
            b'F' => Speed::Full,
            b'H' => Speed::High,
            b'S' => Speed::Super,
            other => return Err(Error::NotifyBadSpeed(other)),
        };
        let server = Ipv4Addr::from(raw.server);
        Ok(Self {
            addr: raw.addr,
            bus: raw.bus,
            crypto: raw.crypto.get(),
            endpoints: Endpoint::parse_config(config),
            server: (!server.is_unspecified()).then_some(server),
            sessions: raw.sessions,
            speed,
            tcp_port: match raw.tcp_port.get() {
                0 => PORT,
                p => p,
            },
            version,
        })
    }
}

impl Endpoint {
    /// Reads endpoints from a configuration descriptor whose 16-bit fields
    /// are big-endian.
    fn parse_config(config: &[u8]) -> BTreeMap<u8, Self> {
        let total = config
            .get(2..4)
            .map_or(0, |t| usize::from(u16::from_be_bytes([t[0], t[1]])))
            .min(config.len());
        let mut rest = &config[..total];
        let mut endpoints = BTreeMap::new();
        while let [len, kind, ..] = *rest {
            let len = usize::from(len);
            if len < 2 || len > rest.len() {
                break;
            }
            if kind == 5
                && let Ok((d, _)) = EndpointDescriptor::ref_from_prefix(&rest[..len])
                && let Some(transfer) = Transfer::from_attributes(d.attributes)
            {
                let e = Self {
                    interval: d.interval,
                    max_packet: d.max_packet.get(),
                    transfer,
                };
                endpoints.insert(d.address, e);
            }
            rest = &rest[len..];
        }
        endpoints
    }
}

impl Transfer {
    fn from_attributes(attributes: u8) -> Option<Self> {
        match attributes & 3 {
            1 => Some(Self::Isochronous),
            2 => Some(Self::Bulk),
            3 => Some(Self::Interrupt),
            _ => None,
        }
    }
}

/// The part every request starts with.
#[repr(C)]
#[derive(Clone, Copy, FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct RequestHeader {
    op: U16<BE>,
    seq: U16<BE>,
    bus: U16<BE>,
    addr: u8,
    /// Endpoint address including the direction bit, 0 for control.
    ep: u8,
    version: U16<BE>,
}

/// A control request, 22 bytes. `value` and `index` are big-endian, unlike
/// in a USB setup packet, and a 32-bit length replaces `wLength`.
#[repr(C)]
#[derive(Clone, Copy, FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct ControlRequest {
    header: RequestHeader,
    /// Always 8.
    f10: U16<BE>,
    request_type: u8,
    request: u8,
    value: U16<BE>,
    index: U16<BE>,
    /// IN: requested length. OUT: length of the data that follows.
    length: U32<BE>,
}

/// A bulk or interrupt request, 18 bytes.
#[repr(C)]
#[derive(Clone, Copy, FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct TransferRequest {
    header: RequestHeader,
    /// 0x8000 | wMaxPacketSize.
    f10: U16<BE>,
    /// bInterval for interrupt endpoints, else 0.
    f12: U16<BE>,
    /// IN: requested length. OUT: length of the data that follows.
    length: U32<BE>,
}

#[derive(Clone, Copy)]
enum Frame {
    Control(ControlRequest),
    Transfer(TransferRequest),
}

/// A request ready to send.
pub(crate) struct Request {
    data: Vec<u8>,
    frame: Frame,
}

impl Request {
    /// The cancel frame: the same header with the cancel bit and length 0.
    pub(crate) fn cancel(&self) -> Vec<u8> {
        let mut frame = self.frame;
        let (header, length) = match &mut frame {
            Frame::Control(c) => (&mut c.header, &mut c.length),
            Frame::Transfer(t) => (&mut t.header, &mut t.length),
        };
        header.op.set(header.op.get() | CANCEL);
        length.set(0);
        frame.as_bytes().to_vec()
    }

    pub(crate) fn encode(&self) -> Vec<u8> {
        let header = self.frame.as_bytes();
        let mut b = Vec::with_capacity(header.len() + self.data.len());
        b.extend_from_slice(header);
        b.extend_from_slice(&self.data);
        b
    }

    fn new(frame: Frame, data: &[u8]) -> Self {
        Self {
            data: data.to_vec(),
            frame,
        }
    }
}

impl Frame {
    fn as_bytes(&self) -> &[u8] {
        match self {
            Self::Control(c) => c.as_bytes(),
            Self::Transfer(t) => t.as_bytes(),
        }
    }
}

/// The fixed part of every reply.
#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct RawReplyHeader {
    op: U16<BE>,
    seq: U16<BE>,
    status: U16<BE>,
    length: U32<BE>,
}

pub(crate) struct ReplyHeader {
    pub(crate) length: u32,
    pub(crate) op: u16,
    pub(crate) seq: u16,
    pub(crate) status: u16,
}

impl ReplyHeader {
    pub(crate) fn read(r: &mut impl Read) -> io::Result<Self> {
        let mut h = RawReplyHeader::new_zeroed();
        r.read_exact(h.as_mut_bytes())?;
        Ok(Self {
            length: h.length.get(),
            op: h.op.get(),
            seq: h.seq.get(),
            status: h.status.get(),
        })
    }
}
