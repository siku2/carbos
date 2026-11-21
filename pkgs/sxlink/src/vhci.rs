//! Attaching sockets to `vhci_hcd` ports through sysfs.

use std::fs;
use std::os::fd::{AsRawFd, OwnedFd};
use std::path::{Path, PathBuf};

use crate::error::{Error, Result};
use crate::sxuptp::Speed;

const SYSFS: &str = "/sys/devices/platform/vhci_hcd.0";
/// `VDEV_ST_NULL`, a free port.
const STATUS_FREE: &str = "004";

/// A `vhci_hcd` root hub port with a device attached.
pub(crate) struct Port(u32);

impl Port {
    /// Attaches `sock` as a device with `devid` and `speed` to a free port.
    ///
    /// The kernel takes its own reference to the socket, so `sock` can be
    /// dropped afterwards.
    pub(crate) fn attach(sock: &OwnedFd, devid: u32, speed: Speed) -> Result<Self> {
        let port = free_port(speed)?;
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

impl Speed {
    /// The `enum usb_device_speed` value.
    fn usb_number(self) -> u32 {
        match self {
            Self::Low => 1,
            Self::Full => 2,
            Self::High => 3,
            Self::Super => 5,
        }
    }
}

/// Finds a free port on a hub matching `speed`. `status`, `status.1` and so
/// on list the ports of each controller.
fn free_port(speed: Speed) -> Result<u32> {
    let hub = if speed == Speed::Super { "ss" } else { "hs" };
    let dir = PathBuf::from(SYSFS);
    let mut entries: Vec<PathBuf> = fs::read_dir(&dir)
        .map_err(|e| Error::Sysfs(dir.clone(), e))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| {
            p.file_name()
                .and_then(|n| n.to_str())
                .is_some_and(|n| n == "status" || n.starts_with("status."))
        })
        .collect();
    entries.sort();
    for path in entries {
        let text = fs::read_to_string(&path).map_err(|e| Error::Sysfs(path.clone(), e))?;
        for line in text.lines().skip(1) {
            let mut cols = line.split_whitespace();
            let (Some(h), Some(port), Some(state)) = (cols.next(), cols.next(), cols.next()) else {
                continue;
            };
            if h == hub
                && state == STATUS_FREE
                && let Ok(port) = port.parse()
            {
                return Ok(port);
            }
        }
    }
    Err(Error::NoVhciPort)
}

fn write(path: &Path, value: &str) -> Result<()> {
    fs::write(path, value).map_err(|e| Error::Sysfs(path.to_owned(), e))
}
