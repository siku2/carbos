use std::fmt;
use std::thread;
use std::time::Duration;

use crate::ifwi::{Ifwi, Item};
use crate::psp::{self, Command, Psp, Status};

const LAST_ITEM: u32 = 2;
// amdvbflash gives up after this many items.
const MAX_ITEMS: usize = 18;
// The bootloader rejects about one word in 50000 with an invalid command
// status. Sending the same word again works, starting the item over does not.
const RETRIES: usize = 5;
const TIMEOUT: Duration = Duration::from_secs(600);

#[derive(Debug)]
pub(crate) enum Error {
    Psp(psp::Error),
    Rejected { item: Item, offset: usize },
    TooManyItems,
    UnknownItem(Item),
}

/// What happened during a streamed update.
pub(crate) enum Event {
    Done { item: Item, retries: usize },
    Progress { item: Item, sent: usize, len: usize },
    Retry { item: Item, offset: usize },
    Start { item: Item, len: usize, last: bool },
}

/// Streams an IFWI to the PSP bootloader, which writes the inactive slot.
///
/// This is the update path amdvbflash takes when no driver runs.
pub(crate) struct Flasher<'a> {
    pub(crate) ifwi: &'a Ifwi<'a>,
    pub(crate) psp: &'a Psp,
    pub(crate) word_pause: Duration,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Psp(err) => err.fmt(f),
            Self::Rejected { item, offset } => {
                write!(f, "item {item} kept getting rejected at {offset:#x}")
            }
            Self::TooManyItems => write!(f, "the bootloader asked for more than {MAX_ITEMS} items"),
            Self::UnknownItem(item) => write!(f, "the bootloader asked for unknown item {item}"),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Psp(err) => Some(err),
            _ => None,
        }
    }
}

impl From<psp::Error> for Error {
    fn from(err: psp::Error) -> Self {
        Self::Psp(err)
    }
}

impl Flasher<'_> {
    pub(crate) fn run(&self, mut report: impl FnMut(Event)) -> Result<(), Error> {
        for _ in 0..MAX_ITEMS {
            let request = self.psp.send(Command::GetTransferType, None, TIMEOUT)?;
            let item = Item::new((request & 0xFF) as u8);
            let last = (request >> 8) & LAST_ITEM != 0;
            let data = self.ifwi.item(item).ok_or(Error::UnknownItem(item))?;
            report(Event::Start {
                item,
                len: data.len(),
                last,
            });
            self.transfer(item, data, &mut report)?;
            if last {
                return Ok(());
            }
        }
        Err(Error::TooManyItems)
    }

    fn transfer(
        &self,
        item: Item,
        data: &[u8],
        report: &mut impl FnMut(Event),
    ) -> Result<(), Error> {
        let len = u32::try_from(data.len()).expect("items are smaller than the SPI ROM");
        self.psp.send(
            Command::StartTransfer,
            Some(len << 8 | u32::from(item)),
            TIMEOUT,
        )?;
        let mut retries = 0;
        for (index, chunk) in data.chunks(4).enumerate() {
            let mut word = [0; 4];
            word[..chunk.len()].copy_from_slice(chunk);
            let offset = index * 4;
            self.word(item, offset, u32::from_le_bytes(word), report, &mut retries)?;
            thread::sleep(self.word_pause);
            if (offset + 4) % 0x1_0000 == 0 {
                report(Event::Progress {
                    item,
                    sent: offset + 4,
                    len: data.len(),
                });
            }
        }
        let sent = len.next_multiple_of(4);
        self.psp.send(
            Command::EndTransfer,
            Some(sent << 8 | u32::from(item)),
            TIMEOUT,
        )?;
        report(Event::Done { item, retries });
        Ok(())
    }

    fn word(
        &self,
        item: Item,
        offset: usize,
        word: u32,
        report: &mut impl FnMut(Event),
        retries: &mut usize,
    ) -> Result<(), Error> {
        for _ in 0..=RETRIES {
            match self.psp.send(Command::DataTransfer, Some(word), TIMEOUT) {
                Ok(_) => return Ok(()),
                Err(psp::Error::Failed(_, Status::INVALID_COMMAND)) => {
                    *retries += 1;
                    report(Event::Retry { item, offset });
                    thread::sleep(Duration::from_millis(1));
                }
                Err(err) => return Err(err.into()),
            }
        }
        Err(Error::Rejected { item, offset })
    }
}
