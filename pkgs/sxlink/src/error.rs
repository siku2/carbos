use std::error;
use std::fmt;
use std::io;
use std::net::IpAddr;
use std::path::PathBuf;

use crate::jcp::Verdict;

#[derive(Debug)]
pub(crate) enum Error {
    DeviceAbsent {
        port: String,
    },
    DeviceBusy {
        owner: IpAddr,
        port: String,
    },
    Encrypted {
        offer: u32,
    },
    JcpArgsTooLong {
        command: &'static str,
    },
    JcpBadDeviceList,
    JcpBadOffset {
        command: &'static str,
    },
    JcpBadSearchReply,
    JcpIpv6NotImplemented,
    JcpRejected {
        command: &'static str,
        verdict: Verdict,
    },
    JcpShortReply {
        command: &'static str,
    },
    JcpSocket(io::Error),
    JcpTimeout {
        command: &'static str,
    },
    LegacyServer,
    MultiSession {
        count: u8,
    },
    NoDevice {
        selector: String,
    },
    NoVhciPort,
    NotifyBadSpeed(u8),
    NotifyBadVersion,
    NotifySocket(io::Error),
    NotifyTimeout,
    NotifyTooShort {
        len: usize,
    },
    ServerConnect(io::Error),
    ServerResolve(String, io::Error),
    ServerSocket(io::Error),
    ServerUnreachable(String, Box<Error>),
    ServerUnresolved(String),
    Signals(io::Error),
    Sysfs(PathBuf, io::Error),
    Usage,
    UsbipUnknownCommand(u32),
    VhciSocket(io::Error),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::DeviceAbsent { port } => write!(f, "no device plugged into {port}"),
            Self::DeviceBusy { owner, port } => {
                write!(f, "{port} is in use by {owner}, pass --take to release it")
            }
            Self::Encrypted { offer } => {
                write!(
                    f,
                    "server requires encryption (offer {offer:#010x}), not supported yet"
                )
            }
            Self::JcpArgsTooLong { command } => write!(f, "arguments for {command:?} too long"),
            Self::JcpBadDeviceList => write!(f, "malformed device list"),
            Self::JcpBadOffset { command } => write!(f, "reply to {command:?} out of order"),
            Self::JcpBadSearchReply => write!(f, "malformed search reply"),
            Self::JcpIpv6NotImplemented => write!(f, "JCP over IPv6 is not implemented yet"),
            Self::JcpRejected { command, verdict } => {
                write!(f, "server answered {verdict:?} to {command:?}")
            }
            Self::JcpShortReply { command } => write!(f, "short reply to {command:?}"),
            Self::JcpSocket(_) => write!(f, "JCP socket"),
            Self::JcpTimeout { command } => write!(f, "no reply to {command:?}"),
            Self::LegacyServer => write!(f, "server uses the legacy SXUPTP header, not supported"),
            Self::MultiSession { count } => {
                write!(f, "device needs {count} sessions, only 1 is supported yet")
            }
            Self::NoDevice { selector } => write!(f, "no port or serial matches {selector:?}"),
            Self::NoVhciPort => write!(f, "no free vhci_hcd port, is vhci-hcd loaded?"),
            Self::NotifyBadSpeed(c) => {
                write!(f, "unknown speed {:?} in notification", char::from(*c))
            }
            Self::NotifyBadVersion => write!(f, "bad protocol version in notification"),
            Self::NotifySocket(_) => write!(f, "notification socket"),
            Self::NotifyTimeout => write!(f, "no notification from the server"),
            Self::NotifyTooShort { len } => write!(f, "notification of {len} bytes is too short"),
            Self::ServerConnect(_) => write!(f, "connecting to the server"),
            Self::ServerResolve(host, _) => write!(f, "resolving {host}"),
            Self::ServerSocket(_) => write!(f, "server session"),
            Self::ServerUnreachable(host, _) => write!(f, "no address of {host} answered"),
            Self::ServerUnresolved(host) => write!(f, "{host} has no address"),
            Self::Signals(_) => write!(f, "signal handler"),
            Self::Sysfs(path, _) => write!(f, "{}", path.display()),
            Self::Usage => write!(f, "invalid arguments"),
            Self::UsbipUnknownCommand(c) => write!(f, "unknown USB/IP command {c}"),
            Self::VhciSocket(_) => write!(f, "vhci socket"),
        }
    }
}

impl error::Error for Error {
    fn source(&self) -> Option<&(dyn error::Error + 'static)> {
        match self {
            Self::JcpSocket(e)
            | Self::NotifySocket(e)
            | Self::ServerConnect(e)
            | Self::ServerResolve(_, e)
            | Self::ServerSocket(e)
            | Self::Signals(e)
            | Self::Sysfs(_, e)
            | Self::VhciSocket(e) => Some(e),
            Self::ServerUnreachable(_, e) => Some(e.as_ref()),
            _ => None,
        }
    }
}

pub(crate) type Result<T> = std::result::Result<T, Error>;
