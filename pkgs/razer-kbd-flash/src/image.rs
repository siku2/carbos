//! The Intel HEX image from Razer's updater and the packets the bootloader
//! takes.

use std::collections::BTreeSet;
use std::fmt;

/// The bootloader only writes this range and ignores the rest.
pub(crate) const APP: std::ops::Range<u16> = 0x1000..0x7F00;
const FLASH_SIZE: u32 = 0x8000;
/// The app writes this marker into the last word, the bootloader checks it.
const MARKER: (u16, [u8; 4]) = (0x7FFC, [0x70, 0x56, 0x30, 0x12]);
const PACKET: usize = 8;
const PAGE: u16 = 0x100;
const SECTOR: u16 = 0x1000;
/// Where the app keeps its version, major, minor and patch.
const VERSION: u16 = 0x6DAB;

#[derive(Debug)]
pub(crate) enum Error {
    Address { line: usize },
    Checksum { line: usize },
    Empty,
    Marker,
    Order { line: usize },
    PageCrossing { start: u16 },
    Syntax { line: usize },
    Type { line: usize, kind: u8 },
    Version,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Address { line } => write!(f, "line {line}: address outside the 32 KiB flash"),
            Self::Checksum { line } => write!(f, "line {line}: wrong checksum"),
            Self::Empty => write!(f, "no data for the app range"),
            Self::Marker => write!(f, "no app marker at {:#06x}", MARKER.0),
            Self::Order { line } => write!(f, "line {line}: records out of order or overlapping"),
            Self::PageCrossing { start } => {
                write!(f, "the packet at {start:#06x} crosses a flash page")
            }
            Self::Syntax { line } => write!(f, "line {line}: not an Intel HEX record"),
            Self::Type { line, kind } => write!(f, "line {line}: unsupported record type {kind}"),
            Self::Version => write!(f, "no version at {VERSION:#06x}"),
        }
    }
}

impl std::error::Error for Error {}

/// A bootloader write or verify request: up to 8 bytes in one flash page.
pub(crate) struct Packet {
    pub(crate) data: Vec<u8>,
    pub(crate) start: u16,
}

impl Packet {
    pub(crate) fn end(&self) -> u16 {
        self.start + u16::try_from(self.data.len()).expect("packets are short") - 1
    }
}

/// What the flash sends: the sectors to erase, the app packets, and a last
/// packet outside the app range. The bootloader buffers a page and programs
/// it when a packet for another page arrives, so the last packet flushes the
/// last page. It is the marker record, which Razer's updater sends last too.
pub(crate) struct Plan {
    pub(crate) flush: Packet,
    pub(crate) packets: Vec<Packet>,
    pub(crate) sectors: BTreeSet<u16>,
    pub(crate) version: String,
}

impl Plan {
    pub(crate) fn parse(text: &str) -> Result<Self, Error> {
        let records = parse_records(text)?;
        let mut packets = Vec::new();
        let mut flush = None;
        for (address, data) in &records {
            if *address == MARKER.0 && data[..] == MARKER.1 {
                flush = Some(Packet {
                    data: data.clone(),
                    start: *address,
                });
                continue;
            }
            for (i, chunk) in data.chunks(PACKET).enumerate() {
                let start = address + u16::try_from(i * PACKET).expect("records are short");
                if !APP.contains(&start) {
                    continue;
                }
                let packet = Packet {
                    data: chunk.to_vec(),
                    start,
                };
                if packet.start / PAGE != packet.end() / PAGE || !APP.contains(&packet.end()) {
                    return Err(Error::PageCrossing { start });
                }
                packets.push(packet);
            }
        }
        let flush = flush.ok_or(Error::Marker)?;
        if packets.is_empty() {
            return Err(Error::Empty);
        }

        // The exit request writes the marker, so its sector is always erased.
        let sectors = packets
            .iter()
            .map(|p| p.start)
            .chain([MARKER.0])
            .map(|address| address / SECTOR * SECTOR)
            .collect();

        let byte = |address: u16| {
            packets
                .iter()
                .find(|p| (p.start..=p.end()).contains(&address))
                .map(|p| p.data[usize::from(address - p.start)])
                .ok_or(Error::Version)
        };
        let version = format!(
            "{}.{:02}.{:02}",
            byte(VERSION)?,
            byte(VERSION + 1)?,
            byte(VERSION + 2)?
        );

        Ok(Self {
            flush,
            packets,
            sectors,
            version,
        })
    }
}

fn parse_records(text: &str) -> Result<Vec<(u16, Vec<u8>)>, Error> {
    let mut records: Vec<(u16, Vec<u8>)> = Vec::new();
    for (index, line) in text.lines().enumerate() {
        let line_number = index + 1;
        let line = line.trim();
        if line.is_empty() {
            continue;
        }
        let bytes = line
            .strip_prefix(':')
            .filter(|hex| hex.is_ascii() && hex.len() % 2 == 0)
            .and_then(|hex| {
                (0..hex.len())
                    .step_by(2)
                    .map(|i| u8::from_str_radix(&hex[i..i + 2], 16).ok())
                    .collect::<Option<Vec<u8>>>()
            })
            .filter(|bytes| bytes.len() >= 5 && bytes.len() == usize::from(bytes[0]) + 5)
            .ok_or(Error::Syntax { line: line_number })?;
        if bytes.iter().fold(0u8, |sum, b| sum.wrapping_add(*b)) != 0 {
            return Err(Error::Checksum { line: line_number });
        }
        let address = u16::from_be_bytes([bytes[1], bytes[2]]);
        let data = &bytes[4..bytes.len() - 1];
        match bytes[3] {
            0 => {
                if u32::from(address) + u32::try_from(data.len()).expect("short") > FLASH_SIZE {
                    return Err(Error::Address { line: line_number });
                }
                if let Some((last, last_data)) = records.last()
                    && usize::from(*last) + last_data.len() > usize::from(address)
                {
                    return Err(Error::Order { line: line_number });
                }
                records.push((address, data.to_vec()));
            }
            1 if data.is_empty() => break,
            // An extended linear address of 0 keeps the 16 bit addresses.
            4 if data == [0, 0] => {}
            4 if data.len() == 2 => return Err(Error::Address { line: line_number }),
            // The start address does not matter to the bootloader.
            5 if data.len() == 4 => {}
            1 | 4 | 5 => return Err(Error::Syntax { line: line_number }),
            kind => {
                return Err(Error::Type {
                    line: line_number,
                    kind,
                });
            }
        }
    }
    Ok(records)
}

#[cfg(test)]
mod tests {
    use super::{Error, Plan};

    /// Builds an Intel HEX record with its checksum.
    fn record(kind: u8, address: u16, data: &[u8]) -> String {
        let [high, low] = address.to_be_bytes();
        let bytes: Vec<u8> = [u8::try_from(data.len()).expect("short"), high, low, kind]
            .into_iter()
            .chain(data.iter().copied())
            .collect();
        let sum = bytes.iter().fold(0u8, |sum, b| sum.wrapping_add(*b));
        let hex: String = bytes
            .iter()
            .chain([&sum.wrapping_neg()])
            .map(|b| format!("{b:02X}"))
            .collect();
        format!(":{hex}\n")
    }

    /// A small image: a bootloader record, app data with the version, and
    /// the marker.
    fn image(app: &[(u16, &[u8])]) -> String {
        let mut text = record(4, 0, &[0, 0]);
        text += &record(0, 0x0000, &[0xAA; 16]);
        for (address, data) in app {
            text += &record(0, *address, data);
        }
        text += &record(0, 0x7FFC, &[0x70, 0x56, 0x30, 0x12]);
        text += &record(5, 0, &[0, 0, 0x10, 0xC1]);
        text += &record(1, 0, &[]);
        text
    }

    #[test]
    fn plan_skips_the_bootloader_and_erases_the_marker_sector() {
        let text = image(&[(0x1000, &[1; 16]), (0x6DA8, &[0, 0, 0, 1, 1, 0, 0, 0])]);
        let plan = Plan::parse(&text).expect("valid image");
        let starts: Vec<u16> = plan.packets.iter().map(|p| p.start).collect();
        assert_eq!(starts, [0x1000, 0x1008, 0x6DA8]);
        assert_eq!(
            plan.sectors.iter().copied().collect::<Vec<_>>(),
            [0x1000, 0x6000, 0x7000]
        );
        assert_eq!(plan.flush.start, 0x7FFC);
        assert_eq!(plan.version, "1.01.00");
    }

    #[test]
    fn plan_needs_the_marker() {
        let text = record(0, 0x1000, &[1; 16]) + &record(1, 0, &[]);
        assert!(matches!(Plan::parse(&text), Err(Error::Marker)));
    }

    #[test]
    fn parse_rejects_bad_records() {
        assert!(matches!(
            Plan::parse(":0\u{e9}A\n"),
            Err(Error::Syntax { line: 1 })
        ));
        let mut bad = record(0, 0x1000, &[1; 16]);
        bad.replace_range(bad.len() - 3..bad.len() - 1, "00");
        assert!(matches!(
            Plan::parse(&bad),
            Err(Error::Checksum { line: 1 })
        ));
        assert!(matches!(
            Plan::parse(&record(5, 0, &[0, 0])),
            Err(Error::Syntax { line: 1 })
        ));
        let overlap = record(0, 0x1000, &[1; 16]) + &record(0, 0x1008, &[1; 8]);
        assert!(matches!(
            Plan::parse(&overlap),
            Err(Error::Order { line: 2 })
        ));
    }
}
