use std::fmt;
use std::thread;
use std::time::{Duration, Instant};

use crate::bar::Bar;

const C2PMSG_58: usize = 0x581E8;
const C2PMSG_73: usize = 0x58224;
const C2PMSG_115: usize = 0x582CC;
const C2PMSG_116: usize = 0x582D0;
const ROM_INDEX: usize = 0x5A390;
const ROM_DATA: usize = 0x5A394;
const READY: u32 = 1 << 31;

/// A bootloader mailbox command.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) enum Command {
    GetBootPartition = 0x1,
    GetFbState = 0x6,
    GetTransferType = 0x7,
    StartTransfer = 0x8,
    DataTransfer = 0x9,
    EndTransfer = 0xA,
    SpiGetModelId = 0xB,
}

/// A nonzero bootloader status.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Status(u16);

#[derive(Debug)]
pub(crate) enum Error {
    Busy(u32),
    Failed(Command, Status),
    Gone,
    Timeout(Command),
}

/// The PSP bootloader mailbox of a Navi3x GPU.
pub(crate) struct Psp {
    bar: Bar,
}

impl Status {
    pub(crate) const INVALID_COMMAND: Self = Self(0xE);

    // The names amdvbflash gives the codes.
    fn name(self) -> &'static str {
        match self.0 {
            0x1 => "generic error",
            0x2 => "out of bounds",
            0x3 => "invalid parameter",
            0x4 => "off chip boot error",
            0x5 => "address not set",
            0x6 => "address map error",
            0x7 => "parse off chip error",
            0x8 => "parse on chip error",
            0x9 => "full update error",
            0xA => "partition update error",
            0xB => "map on chip error",
            0xC => "write to SPI error",
            0xD => "signature validation error",
            0xE => "invalid command",
            0xF => "signature not found",
            0x10 => "state machine not initialized",
            0x11 => "state machine transfer error",
            0x12 => "initialization error",
            _ => "unknown error",
        }
    }
}

impl fmt::Display for Status {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:#x} ({})", self.0, self.name())
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Busy(state) => write!(f, "the mailbox is busy ({state:#010x})"),
            Self::Failed(command, status) => write!(f, "{command:?} failed with {status}"),
            Self::Gone => write!(f, "the GPU does not answer"),
            Self::Timeout(command) => write!(f, "{command:?} timed out"),
        }
    }
}

impl std::error::Error for Error {}

impl Psp {
    pub(crate) fn new(bar: Bar) -> Self {
        Self { bar }
    }

    /// The version of the PSP secure OS, zero when only the bootloader runs.
    ///
    /// The SPI update commands only work before a driver loads the secure OS.
    pub(crate) fn sos_version(&self) -> u32 {
        self.bar.read(C2PMSG_58)
    }

    pub(crate) fn query(&self, command: Command) -> Result<u32, Error> {
        self.send(command, None, Duration::from_secs(5))
    }

    pub(crate) fn send(
        &self,
        command: Command,
        data: Option<u32>,
        timeout: Duration,
    ) -> Result<u32, Error> {
        let state = self.bar.read(C2PMSG_115);
        if state == u32::MAX {
            return Err(Error::Gone);
        }
        if state & READY == 0 {
            return Err(Error::Busy(state));
        }
        if let Some(data) = data {
            self.bar.write(C2PMSG_116, data);
        }
        self.bar.write(C2PMSG_115, (command as u32) << 16);
        self.bar.write(C2PMSG_73, 1);
        let start = Instant::now();
        loop {
            let state = self.bar.read(C2PMSG_115);
            if state == u32::MAX {
                return Err(Error::Gone);
            }
            if state & READY != 0 {
                return match (state & 0xFFFF) as u16 {
                    0 => Ok(self.bar.read(C2PMSG_116)),
                    status => Err(Error::Failed(command, Status(status))),
                };
            }
            let waited = start.elapsed();
            if waited > timeout {
                return Err(Error::Timeout(command));
            }
            if waited > Duration::from_millis(1) {
                thread::sleep(Duration::from_micros(50));
            }
        }
    }

    /// Reads the SPI ROM of the selected chip into `buf`.
    pub(crate) fn read_rom(&self, buf: &mut [u8]) {
        self.bar.write(ROM_INDEX, 0);
        for word in buf.chunks_exact_mut(4) {
            word.copy_from_slice(&self.bar.read(ROM_DATA).to_le_bytes());
        }
    }
}
