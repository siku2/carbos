//! The bootloader (USB 1532:110D) and its vendor control requests.

use std::fmt;
use std::io;
use std::thread;
use std::time::Duration;

use crate::image::Packet;
use crate::usb::Device;

const ERASE: u8 = 0x82;
const ERASE_SPAN: u16 = 0x1FF;
const EXIT: u8 = 0x84;
const IN: u8 = 0xC0;
const OUT: u8 = 0x40;
const POLL: Duration = Duration::from_millis(10);
/// Long enough for a sector erase, which takes about 100 ms.
const POLLS: usize = 200;
const STATUS: u8 = 0x8F;
const STATUS_BUSY: u8 = 0xFF;
const STATUS_OK: u8 = 0x01;
const TIMEOUT: Duration = Duration::from_secs(5);
const VERIFY: u8 = 0x87;
const WRITE: u8 = 0x81;

#[derive(Debug)]
pub(crate) enum Error {
    Busy,
    Io(io::Error),
    Mismatch,
    Status(u8),
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Busy => write!(f, "the bootloader stayed busy"),
            Self::Io(_) => write!(f, "the control request failed"),
            Self::Mismatch => write!(f, "the flash does not hold the data"),
            Self::Status(status) => write!(f, "the bootloader reported status {status:#04x}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Io(err) => Some(err),
            Self::Busy | Self::Mismatch | Self::Status(_) => None,
        }
    }
}

impl From<io::Error> for Error {
    fn from(err: io::Error) -> Self {
        Self::Io(err)
    }
}

/// What a step works on, for error messages.
#[derive(Clone, Copy, Debug)]
pub(crate) enum Target {
    Erase(u16),
    Exit,
    Verify(u16),
    Write(u16),
}

impl fmt::Display for Target {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Erase(at) => write!(f, "erasing the sector at {at:#06x}"),
            Self::Exit => write!(f, "leaving the bootloader"),
            Self::Verify(at) => write!(f, "verifying the packet at {at:#06x}"),
            Self::Write(at) => write!(f, "writing the packet at {at:#06x}"),
        }
    }
}

/// One step of the flash, as the plan command prints it.
pub(crate) enum Step<'a> {
    Erase(u16),
    Exit,
    Verify(&'a Packet),
    Write(&'a Packet),
}

impl Step<'_> {
    pub(crate) fn target(&self) -> Target {
        match self {
            Self::Erase(at) => Target::Erase(*at),
            Self::Exit => Target::Exit,
            Self::Verify(p) => Target::Verify(p.start),
            Self::Write(p) => Target::Write(p.start),
        }
    }
}

impl fmt::Display for Step<'_> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let packet = |f: &mut fmt::Formatter<'_>, name: &str, p: &Packet| {
            write!(f, "{name} {:#06x}..={:#06x}", p.start, p.end())?;
            p.data.iter().try_for_each(|b| write!(f, " {b:02x}"))
        };
        match self {
            Self::Erase(sector) => write!(f, "erase {sector:#06x}..={:#06x}", sector + ERASE_SPAN),
            Self::Exit => write!(f, "exit"),
            Self::Verify(p) => packet(f, "verify", p),
            Self::Write(p) => packet(f, "write", p),
        }
    }
}

pub(crate) struct Bootloader(pub(crate) Device);

impl Bootloader {
    /// Runs one step and waits until the bootloader reports success.
    pub(crate) fn run(&self, step: &Step<'_>) -> Result<(), Error> {
        match step {
            // Razer's updater sends the erase as an IN request.
            Step::Erase(sector) => {
                self.0
                    .control(IN, ERASE, *sector, sector + ERASE_SPAN, &mut [], TIMEOUT)?;
            }
            // The bootloader resets without finishing the request.
            Step::Exit => {
                let _ = self.0.control(OUT, EXIT, 0, 0, &mut [], TIMEOUT);
                return Ok(());
            }
            Step::Verify(packet) | Step::Write(packet) => {
                let request = if matches!(step, Step::Write(_)) {
                    WRITE
                } else {
                    VERIFY
                };
                let mut data = packet.data.clone();
                self.0
                    .control(OUT, request, packet.start, packet.end(), &mut data, TIMEOUT)?;
            }
        }
        // A verify that does not match leaves the status at busy.
        match (step, self.wait()) {
            (Step::Verify(_), Err(Error::Busy)) => Err(Error::Mismatch),
            (_, result) => result,
        }
    }

    fn wait(&self) -> Result<(), Error> {
        for _ in 0..POLLS {
            let mut status = [STATUS_BUSY];
            self.0.control(IN, STATUS, 0, 0, &mut status, TIMEOUT)?;
            match status[0] {
                STATUS_OK => return Ok(()),
                STATUS_BUSY => thread::sleep(POLL),
                other => return Err(Error::Status(other)),
            }
        }
        Err(Error::Busy)
    }
}
