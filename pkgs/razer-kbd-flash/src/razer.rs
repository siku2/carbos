//! Razer feature reports to the keyboard while its app runs.

use std::fmt;
use std::io;
use std::thread;
use std::time::Duration;

use crate::usb::{Device, Hidraw};

const ARGS: usize = 80;
const CLASS_DEVICE: u8 = 0x00;
const CMD_DEVICE_MODE: u8 = 0x04;
const CMD_VERSION: u8 = 0x87;
/// Device mode 1 starts the bootloader. The app erases its last sector
/// first, so the keyboard stays in the bootloader until a full flash.
const MODE_BOOTLOADER: u8 = 0x01;
const POLLS: usize = 100;
const REPORT: usize = 90;
const STATUS_BUSY: u8 = 0x01;
const STATUS_NEW: u8 = 0x00;
const STATUS_OK: u8 = 0x02;
/// The transaction IDs the kernel driver uses for these commands.
const TID_DEFAULT: u8 = 0xFF;
const TID_MATRIX: u8 = 0x3F;

#[derive(Debug)]
pub(crate) enum Error {
    Echo,
    Io(io::Error),
    Status(u8),
    Timeout,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Echo => write!(f, "the answer is for another command"),
            Self::Io(_) => write!(f, "the feature report failed"),
            Self::Status(status) => write!(f, "the keyboard answered with status {status:#04x}"),
            Self::Timeout => write!(f, "the keyboard did not answer"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(err) => Some(err),
            Self::Echo | Self::Status(_) | Self::Timeout => None,
        }
    }
}

impl From<io::Error> for Error {
    fn from(err: io::Error) -> Self {
        Self::Io(err)
    }
}

/// A 90 byte Razer report, without the report ID.
struct Report([u8; REPORT]);

impl Report {
    fn new(tid: u8, class: u8, command: u8, size: u8, args: &[u8]) -> Self {
        assert!(args.len() <= ARGS, "too many arguments");
        let mut report = [0; REPORT];
        report[1] = tid;
        report[5] = size;
        report[6] = class;
        report[7] = command;
        report[8..8 + args.len()].copy_from_slice(args);
        report[88] = report[2..88].iter().fold(0, |crc, b| crc ^ b);
        Self(report)
    }
}

/// The keyboard app, reached through hidraw for queries or through usbfs on
/// the interface the kernel driver uses.
pub(crate) enum Keyboard {
    Hidraw(Hidraw),
    Usb(Device, u8),
}

impl Keyboard {
    /// Switches to the bootloader. The keyboard resets before it answers.
    pub(crate) fn enter_bootloader(&self) -> Result<(), Error> {
        let report = Report::new(
            TID_MATRIX,
            CLASS_DEVICE,
            CMD_DEVICE_MODE,
            2,
            &[MODE_BOOTLOADER, 0],
        );
        Ok(self.set(&report)?)
    }

    fn get(&self) -> io::Result<Report> {
        match self {
            Self::Hidraw(hidraw) => {
                let mut buffer = [0; REPORT + 1];
                hidraw.get_feature(&mut buffer)?;
                let mut report = [0; REPORT];
                report.copy_from_slice(&buffer[1..]);
                Ok(Report(report))
            }
            Self::Usb(device, interface) => {
                let mut report = [0; REPORT];
                device.control(
                    0xA1,
                    0x01,
                    0x0300,
                    u16::from(*interface),
                    &mut report,
                    Duration::from_secs(1),
                )?;
                Ok(Report(report))
            }
        }
    }

    fn query(&self, request: &Report) -> Result<[u8; ARGS], Error> {
        self.set(request)?;
        for _ in 0..POLLS {
            thread::sleep(Duration::from_millis(2));
            let answer = self.get()?;
            match answer.0[0] {
                STATUS_NEW | STATUS_BUSY => continue,
                STATUS_OK => {}
                status => return Err(Error::Status(status)),
            }
            if answer.0[6..8] != request.0[6..8] {
                return Err(Error::Echo);
            }
            let mut args = [0; ARGS];
            args.copy_from_slice(&answer.0[8..8 + ARGS]);
            return Ok(args);
        }
        Err(Error::Timeout)
    }

    fn set(&self, report: &Report) -> io::Result<()> {
        match self {
            Self::Hidraw(hidraw) => {
                let mut buffer = [0; REPORT + 1];
                buffer[1..].copy_from_slice(&report.0);
                hidraw.set_feature(&mut buffer)
            }
            Self::Usb(device, interface) => {
                let mut data = report.0;
                device.control(
                    0x21,
                    0x09,
                    0x0300,
                    u16::from(*interface),
                    &mut data,
                    Duration::from_secs(1),
                )?;
                Ok(())
            }
        }
    }

    /// Gives a claimed interface back to its kernel driver.
    pub(crate) fn release(&self) -> io::Result<()> {
        match self {
            Self::Hidraw(_) => Ok(()),
            Self::Usb(device, interface) => device.reconnect(*interface),
        }
    }

    /// Reads the app version the way Razer's updater does.
    pub(crate) fn version(&self) -> Result<String, Error> {
        let args = self.query(&Report::new(TID_DEFAULT, CLASS_DEVICE, CMD_VERSION, 8, &[]))?;
        Ok(format!("{}.{:02}.{:02}", args[0], args[1], args[2]))
    }
}
