//! Attaching sockets to `vhci_hcd` ports through sysfs.

use std::cmp::Ordering;
use std::fs::{self, File};
use std::io::{BufRead, BufReader};
use std::os::fd::{AsRawFd, OwnedFd};
use std::path::{Path, PathBuf};
use std::str::FromStr;

use crate::error::{Error, Result};
use crate::sxuptp::Speed;

const SYSFS: &str = "/sys/devices/platform/vhci_hcd.0";
/// `VDEV_ST_NULL`, a free port.
const STATE_FREE: u32 = 4;

/// The root hub a port belongs to.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum Hub {
    High,
    Super,
}

impl Hub {
    fn for_speed(speed: Speed) -> Self {
        if speed == Speed::Super {
            Self::Super
        } else {
            Self::High
        }
    }
}

impl FromStr for Hub {
    type Err = ();

    fn from_str(s: &str) -> std::result::Result<Self, ()> {
        match s {
            "hs" => Ok(Self::High),
            "ss" => Ok(Self::Super),
            _ => Err(()),
        }
    }
}

/// A `vhci_hcd` root hub port with a device attached.
pub(crate) struct Port(u32);

impl Port {
    /// Attaches `sock` as a device with `devid` and `speed` to a free port.
    ///
    /// The kernel takes its own reference to the socket, so `sock` can be
    /// dropped afterwards.
    pub(crate) fn attach(sock: &OwnedFd, devid: u32, speed: Speed) -> Result<Self> {
        let port = PortStatus::free(Hub::for_speed(speed))?;
        let line = format!("{port} {} {devid} {}", sock.as_raw_fd(), speed.usb_number());
        write(&Path::new(SYSFS).join("attach"), &line)?;
        Ok(Self(port))
    }

    pub(crate) fn detach(self) -> Result<()> {
        write(&Path::new(SYSFS).join("detach"), &self.0.to_string())
    }

    pub(crate) fn number(&self) -> u32 {
        self.0
    }
}

/// One line of a `status` file.
struct PortStatus {
    hub: Hub,
    /// Global port number, unique across controllers.
    port: u32,
    state: u32,
}

impl PortStatus {
    /// Every port of every controller. `status`, `status.1` and so on list
    /// the ports of each controller.
    fn all() -> Result<impl Iterator<Item = Result<Self>>> {
        let dir = PathBuf::from(SYSFS);
        let entries = fs::read_dir(&dir).map_err(|e| Error::Sysfs(dir, e))?;
        Ok(entries
            .filter_map(|entry| {
                let path = entry.ok()?.path();
                let name = path.file_name()?.to_str()?;
                (name == "status" || name.starts_with("status.")).then_some(path)
            })
            .flat_map(Self::read_file))
    }

    /// The lowest free port on `hub`.
    fn free(hub: Hub) -> Result<u32> {
        // A free port wins over a file that could not be read. Without any
        // free port the read error comes out.
        Self::all()?
            .filter(|s| !matches!(s, Ok(s) if s.hub != hub || s.state != STATE_FREE))
            .map(|s| s.map(|s| s.port))
            .min_by(|a, b| match (a, b) {
                (Ok(a), Ok(b)) => a.cmp(b),
                (Ok(_), Err(_)) => Ordering::Less,
                (Err(_), Ok(_)) => Ordering::Greater,
                (Err(_), Err(_)) => Ordering::Equal,
            })
            .unwrap_or(Err(Error::NoVhciPort))
    }

    /// The ports in one status file, skipping its header line.
    fn read_file(path: PathBuf) -> impl Iterator<Item = Result<Self>> {
        let (lines, open_error) = match File::open(&path) {
            Ok(f) => (Some(BufReader::new(f).lines().skip(1)), None),
            Err(e) => (None, Some(Err(Error::Sysfs(path.clone(), e)))),
        };
        lines
            .into_iter()
            .flatten()
            .filter_map(move |line| match line {
                Ok(line) => line.parse().ok().map(Ok),
                Err(e) => Some(Err(Error::Sysfs(path.clone(), e))),
            })
            .chain(open_error)
    }
}

impl FromStr for PortStatus {
    type Err = ();

    /// Parses `hub port state ...`, for example `hs  0000 004 000 ...`.
    fn from_str(line: &str) -> std::result::Result<Self, ()> {
        let mut cols = line.split_whitespace();
        let hub = cols.next().ok_or(())?.parse()?;
        let port = cols.next().ok_or(())?.parse().map_err(drop)?;
        let state = cols.next().ok_or(())?.parse().map_err(drop)?;
        Ok(Self { hub, port, state })
    }
}

fn write(path: &Path, value: &str) -> Result<()> {
    fs::write(path, value).map_err(|e| Error::Sysfs(path.to_owned(), e))
}
