use std::error;
use std::fmt;
use std::io;
use std::net::Ipv4Addr;
use std::path::PathBuf;

use crate::jcp::Verdict;

#[derive(Debug)]
pub(crate) enum Error {
    DeviceAbsent {
        port: String,
    },
    DeviceBusy {
        owner: Ipv4Addr,
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
    ServerSocket(io::Error),
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
            Self::JcpRejected { command, verdict } => {
                write!(f, "server answered {verdict:?} to {command:?}")
            }
            Self::JcpShortReply { command } => write!(f, "short reply to {command:?}"),
            Self::JcpSocket(_) => write!(f, "JCP socket"),
            Self::JcpTimeout { command } => write!(f, "no reply to {command:?}"),
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
            Self::ServerSocket(_) => write!(f, "server session"),
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
            | Self::ServerSocket(e)
            | Self::Sysfs(_, e)
            | Self::VhciSocket(e) => Some(e),
            _ => None,
        }
    }
}

pub(crate) type Result<T> = std::result::Result<T, Error>;
