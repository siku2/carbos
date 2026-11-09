//! USB access through usbfs and hidraw, without libusb.

use std::ffi::{c_ulong, c_void};
use std::fs::{self, File, OpenOptions};
use std::io;
use std::os::fd::AsRawFd;
use std::path::{Path, PathBuf};
use std::ptr;
use std::time::Duration;

const HIDIOCGFEATURE_91: c_ulong = 0xC05B_4807;
const HIDIOCSFEATURE_91: c_ulong = 0xC05B_4806;
const USBDEVFS_CONNECT: i32 = 0x5517;
const USBDEVFS_CONTROL: c_ulong = 0xC018_5500;
const USBDEVFS_DISCONNECT_CLAIM: c_ulong = 0x8108_551B;
const USBDEVFS_IOCTL: c_ulong = 0xC010_5512;
const USBDEVFS_RELEASEINTERFACE: c_ulong = 0x8004_5510;

unsafe extern "C" {
    fn ioctl(fd: i32, request: c_ulong, ...) -> i32;
}

#[repr(C)]
struct CtrlTransfer {
    request_type: u8,
    request: u8,
    value: u16,
    index: u16,
    length: u16,
    timeout: u32,
    data: *mut c_void,
}

#[repr(C)]
struct DisconnectClaim {
    interface: u32,
    flags: u32,
    driver: [u8; 256],
}

#[repr(C)]
struct UsbIoctl {
    interface: i32,
    code: i32,
    data: *mut c_void,
}

/// A USB device in sysfs, identified by its IDs.
pub(crate) struct Id {
    pub(crate) bcd_device: Option<u16>,
    pub(crate) product: u16,
    pub(crate) vendor: u16,
}

impl Id {
    /// Finds the sysfs directory of the first matching device.
    pub(crate) fn find(&self) -> io::Result<Option<PathBuf>> {
        for entry in fs::read_dir("/sys/bus/usb/devices")? {
            let path = entry?.path();
            let read = |name: &str| {
                fs::read_to_string(path.join(name))
                    .ok()
                    .and_then(|text| u16::from_str_radix(text.trim(), 16).ok())
            };
            if read("idVendor") == Some(self.vendor)
                && read("idProduct") == Some(self.product)
                && self
                    .bcd_device
                    .is_none_or(|bcd| read("bcdDevice") == Some(bcd))
            {
                return Ok(Some(path));
            }
        }
        Ok(None)
    }
}

/// An open usbfs device node.
pub(crate) struct Device {
    file: File,
}

impl Device {
    pub(crate) fn open(sysfs: &Path) -> io::Result<Self> {
        let read = |name: &str| -> io::Result<u32> {
            fs::read_to_string(sysfs.join(name))?
                .trim()
                .parse()
                .map_err(io::Error::other)
        };
        let node = format!("/dev/bus/usb/{:03}/{:03}", read("busnum")?, read("devnum")?);
        let file = OpenOptions::new().read(true).write(true).open(node)?;
        Ok(Self { file })
    }

    /// Detaches any kernel driver from the interface and claims it.
    pub(crate) fn claim(&self, interface: u8) -> io::Result<()> {
        let mut claim = DisconnectClaim {
            interface: u32::from(interface),
            flags: 0,
            driver: [0; 256],
        };
        // SAFETY: the struct matches usbdevfs_disconnect_claim.
        let ret = unsafe { ioctl(self.file.as_raw_fd(), USBDEVFS_DISCONNECT_CLAIM, &mut claim) };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    /// Sends a control request and returns the number of bytes transferred.
    pub(crate) fn control(
        &self,
        request_type: u8,
        request: u8,
        value: u16,
        index: u16,
        data: &mut [u8],
        timeout: Duration,
    ) -> io::Result<usize> {
        let mut transfer = CtrlTransfer {
            request_type,
            request,
            value,
            index,
            length: u16::try_from(data.len()).map_err(io::Error::other)?,
            timeout: u32::try_from(timeout.as_millis()).map_err(io::Error::other)?,
            data: if data.is_empty() {
                ptr::null_mut()
            } else {
                data.as_mut_ptr().cast()
            },
        };
        // SAFETY: the struct matches usbdevfs_ctrltransfer and data outlives the call.
        let ret = unsafe { ioctl(self.file.as_raw_fd(), USBDEVFS_CONTROL, &mut transfer) };
        usize::try_from(ret).map_err(|_| io::Error::last_os_error())
    }

    /// Releases a claimed interface and lets its kernel driver bind again.
    pub(crate) fn reconnect(&self, interface: u8) -> io::Result<()> {
        let mut number = u32::from(interface);
        // SAFETY: the argument is the interface number.
        let ret = unsafe {
            ioctl(
                self.file.as_raw_fd(),
                USBDEVFS_RELEASEINTERFACE,
                &mut number,
            )
        };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        let mut command = UsbIoctl {
            interface: i32::from(interface),
            code: USBDEVFS_CONNECT,
            data: ptr::null_mut(),
        };
        // SAFETY: the struct matches usbdevfs_ioctl, CONNECT takes no data.
        let ret = unsafe { ioctl(self.file.as_raw_fd(), USBDEVFS_IOCTL, &mut command) };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
}

/// The hidraw node of one interface, for feature reports with report ID 0.
pub(crate) struct Hidraw {
    file: File,
}

impl Hidraw {
    /// Opens the hidraw node of an interface of the USB device in sysfs.
    pub(crate) fn open(sysfs: &Path, interface: u8) -> io::Result<Option<Self>> {
        let Some(name) = sysfs.file_name() else {
            return Ok(None);
        };
        let interface_dir = format!("{}:1.{interface}", name.to_string_lossy());
        for entry in fs::read_dir("/sys/class/hidraw")? {
            let entry = entry?;
            // A node that goes away during the scan is not the one we want.
            let Ok(device) = fs::canonicalize(entry.path().join("device")) else {
                continue;
            };
            if device
                .parent()
                .and_then(Path::file_name)
                .is_some_and(|parent| parent.to_string_lossy() == interface_dir)
            {
                let file = OpenOptions::new()
                    .read(true)
                    .write(true)
                    .open(Path::new("/dev").join(entry.file_name()))?;
                return Ok(Some(Self { file }));
            }
        }
        Ok(None)
    }

    pub(crate) fn get_feature(&self, report: &mut [u8; 91]) -> io::Result<()> {
        // SAFETY: the buffer has the length encoded in the request.
        let ret = unsafe {
            ioctl(
                self.file.as_raw_fd(),
                HIDIOCGFEATURE_91,
                report.as_mut_ptr(),
            )
        };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }

    pub(crate) fn set_feature(&self, report: &mut [u8; 91]) -> io::Result<()> {
        // SAFETY: the buffer has the length encoded in the request.
        let ret = unsafe {
            ioctl(
                self.file.as_raw_fd(),
                HIDIOCSFEATURE_91,
                report.as_mut_ptr(),
            )
        };
        if ret < 0 {
            return Err(io::Error::last_os_error());
        }
        Ok(())
    }
}
