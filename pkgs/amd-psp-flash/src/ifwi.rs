use std::collections::BTreeMap;
use std::fmt;
use std::ops::Range;

const EFS_SIZE: usize = 0x54;
const ROMSTRAP_SIZE: usize = 0x1000;
const SIGNATURE_POINTER: usize = 0x1000;
const OEM_DATA: Range<usize> = 0x1F_0000..0x1F_0100;
const ISH_A: u32 = 0x13C;
const ISH_B: u32 = 0x13D;
/// The size of the SPI ROM on Navi3x boards.
pub(crate) const ROM_SIZE: usize = 0x20_0000;

/// A part of the image the bootloader asks for during a streamed update.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub(crate) struct Item(u8);

#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Error {
    MissingSlot(u32),
    OutOfBounds {
        field: usize,
    },
    Region {
        item: Item,
        start: usize,
        end: usize,
    },
    TooLarge(usize),
}

/// An image slot header, which tells the bootloader where a partition lives.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(crate) struct Slot {
    pub(crate) id: u32,
    pub(crate) location: usize,
    pub(crate) priority: u32,
}

/// A Navi3x IFWI whose stream items all lie inside the image.
pub(crate) struct Ifwi<'a> {
    bytes: &'a [u8],
    items: BTreeMap<Item, Range<usize>>,
    slots: [Slot; 2],
}

impl Item {
    pub(crate) const PARTITION: Self = Self(0x08);

    pub(crate) fn new(code: u8) -> Self {
        Self(code)
    }
}

impl fmt::Display for Item {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{:#04x}", self.0)
    }
}

impl From<Item> for u32 {
    fn from(item: Item) -> Self {
        Self::from(item.0)
    }
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::MissingSlot(id) => write!(f, "the image has no slot header {id:#x}"),
            Self::OutOfBounds { field } => {
                write!(f, "the field at {field:#x} is outside the image")
            }
            Self::TooLarge(len) => {
                write!(
                    f,
                    "the image has {len:#x} bytes, more than the {ROM_SIZE:#x} byte SPI ROM"
                )
            }
            Self::Region { item, start, end } => {
                write!(
                    f,
                    "item {item} at {start:#x}..{end:#x} is outside the image"
                )
            }
        }
    }
}

impl std::error::Error for Error {}

impl<'a> Ifwi<'a> {
    // The item lookup of amdvbflash's PSPFlashPreFBInit::GetROMItemTypeDetails.
    pub(crate) fn parse(bytes: &'a [u8]) -> Result<Self, Error> {
        if bytes.len() > ROM_SIZE {
            return Err(Error::TooLarge(bytes.len()));
        }
        let field = |offset: usize| -> Result<usize, Error> {
            bytes
                .get(offset..offset + 4)
                .map(|b| u32::from_le_bytes([b[0], b[1], b[2], b[3]]) as usize)
                .ok_or(Error::OutOfBounds { field: offset })
        };
        let table = |offset: usize| -> Result<Range<usize>, Error> {
            Ok(offset..offset + (field(offset + 8)? + 1) * 16)
        };
        let sized = |start: usize, len: usize| start..start + len;

        let l1 = field(0x14)?;
        let signatures = field(SIGNATURE_POINTER)?;
        let mut items = BTreeMap::from([
            (Item(0x01), 0..EFS_SIZE),
            (Item(0x02), table(l1)?),
            (Item(0x03), table(field(0x2C)?)?),
            (Item(0x04), sized(field(0x4C)?, ROMSTRAP_SIZE)),
            (Item(0x05), sized(field(0x50)?, ROMSTRAP_SIZE)),
            (Item(0x80), sized(SIGNATURE_POINTER, 4)),
            (Item(0x81), table(signatures)?),
            (Item(0x89), OEM_DATA),
        ]);

        let entries = (0..field(l1 + 8)?).map(|i| l1 + 16 + 16 * i);
        let mut slots = [None, None];
        let mut first = None;
        for entry in entries {
            let (id, size, location) = (field(entry)? as u32, field(entry + 4)?, field(entry + 8)?);
            first.get_or_insert(location);
            for (index, (item, slot_id)) in [(Item(0x06), ISH_A), (Item(0x07), ISH_B)]
                .into_iter()
                .enumerate()
            {
                if id == slot_id {
                    items.insert(item, sized(location, size));
                    slots[index] = Some(Slot {
                        id,
                        location: field(location + 0x10)?,
                        priority: field(location + 4)? as u32,
                    });
                }
            }
        }
        // The partition is the region of the first slot header in L1.
        let first = first.ok_or(Error::MissingSlot(ISH_A))?;
        items.insert(
            Item::PARTITION,
            sized(field(first + 0x10)?, field(first + 0x18)?),
        );

        for i in 0..field(signatures + 8)? {
            let entry = signatures + 16 + 16 * i;
            let kind = *bytes
                .get(entry)
                .ok_or(Error::OutOfBounds { field: entry })?;
            if (1..=7).contains(&kind) {
                items.insert(
                    Item(0x81 + kind),
                    sized(field(entry + 0xC)?, field(entry + 8)?),
                );
            }
        }

        if let Some((&item, range)) = items.iter().find(|(_, range)| range.end > bytes.len()) {
            return Err(Error::Region {
                item,
                start: range.start,
                end: range.end,
            });
        }
        let [Some(a), Some(b)] = slots else {
            return Err(Error::MissingSlot(if slots[0].is_none() {
                ISH_A
            } else {
                ISH_B
            }));
        };
        Ok(Self {
            bytes,
            items,
            slots: [a, b],
        })
    }

    pub(crate) fn item(&self, item: Item) -> Option<&'a [u8]> {
        self.items
            .get(&item)
            .map(|range| &self.bytes[range.clone()])
    }

    pub(crate) fn items(&self) -> impl Iterator<Item = (Item, &Range<usize>)> {
        self.items.iter().map(|(&item, range)| (item, range))
    }

    pub(crate) fn slots(&self) -> &[Slot; 2] {
        &self.slots
    }

    /// The slot the bootloader picks on the next boot.
    pub(crate) fn next_slot(&self) -> Slot {
        let [a, b] = self.slots;
        if b.priority > a.priority { b } else { a }
    }

    /// The `len` bytes of the partition the slot points to.
    pub(crate) fn slot_partition(&self, slot: Slot, len: usize) -> Option<&'a [u8]> {
        self.bytes.get(slot.location..slot.location + len)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn put(image: &mut [u8], offset: usize, value: u32) {
        image[offset..offset + 4].copy_from_slice(&value.to_le_bytes());
    }

    // The layout of the ASUS TUF RX 7900 XTX image, with empty payloads.
    fn image() -> Vec<u8> {
        let mut image = vec![0xFF; 0x20_0000];
        image[..EFS_SIZE].fill(0);
        put(&mut image, 0x14, 0x2000);
        put(&mut image, 0x2C, 0x3000);
        put(&mut image, 0x4C, 0x1_0000);
        put(&mut image, 0x50, 0x1_1000);
        for l1 in [0x2000, 0x3000] {
            put(&mut image, l1 + 8, 2);
            for (i, (id, location)) in [(ISH_A, 0x1_2000), (ISH_B, 0x1_3000)]
                .into_iter()
                .enumerate()
            {
                let entry = l1 + 16 + 16 * i;
                put(&mut image, entry, id);
                put(&mut image, entry + 4, 0x20);
                put(&mut image, entry + 8, location);
            }
        }
        for (ish, priority, location) in [(0x1_2000, 2, 0x2_0000), (0x1_3000, 3, 0x10_0000)] {
            put(&mut image, ish + 4, priority);
            put(&mut image, ish + 0x10, location);
            put(&mut image, ish + 0x18, 0xE_0000);
        }
        put(&mut image, SIGNATURE_POINTER, 0x1_B000);
        put(&mut image, 0x1_B000 + 8, 7);
        for kind in 1..=7u8 {
            let entry = 0x1_B000 + 16 * usize::from(kind);
            image[entry] = kind;
            put(&mut image, entry + 8, 0x200);
            put(&mut image, entry + 0xC, 0x1_3000 + 0x1000 * u32::from(kind));
        }
        image
    }

    #[test]
    fn maps_the_items_like_amdvbflash() {
        let bytes = image();
        let ifwi = Ifwi::parse(&bytes).unwrap();
        let ranges: Vec<_> = ifwi
            .items
            .iter()
            .map(|(item, range)| (item.0, range.clone()))
            .collect();
        assert_eq!(
            ranges,
            [
                (0x01, 0x0..0x54),
                (0x02, 0x2000..0x2030),
                (0x03, 0x3000..0x3030),
                (0x04, 0x1_0000..0x1_1000),
                (0x05, 0x1_1000..0x1_2000),
                (0x06, 0x1_2000..0x1_2020),
                (0x07, 0x1_3000..0x1_3020),
                (0x08, 0x2_0000..0x10_0000),
                (0x80, 0x1000..0x1004),
                (0x81, 0x1_B000..0x1_B080),
                (0x82, 0x1_4000..0x1_4200),
                (0x83, 0x1_5000..0x1_5200),
                (0x84, 0x1_6000..0x1_6200),
                (0x85, 0x1_7000..0x1_7200),
                (0x86, 0x1_8000..0x1_8200),
                (0x87, 0x1_9000..0x1_9200),
                (0x88, 0x1_A000..0x1_A200),
                (0x89, 0x1F_0000..0x1F_0100),
            ]
        );
    }

    #[test]
    fn picks_the_slot_with_the_higher_priority() {
        let bytes = image();
        let ifwi = Ifwi::parse(&bytes).unwrap();
        assert_eq!(ifwi.next_slot().location, 0x10_0000);
    }

    #[test]
    fn rejects_an_image_larger_than_the_rom() {
        let mut bytes = image();
        bytes.push(0xFF);
        assert_eq!(
            Ifwi::parse(&bytes).err(),
            Some(Error::TooLarge(ROM_SIZE + 1))
        );
    }

    #[test]
    fn rejects_a_truncated_image() {
        let bytes = image();
        assert!(matches!(
            Ifwi::parse(&bytes[..0x1F_0000]),
            Err(Error::Region {
                item: Item(0x89),
                ..
            })
        ));
    }
}
