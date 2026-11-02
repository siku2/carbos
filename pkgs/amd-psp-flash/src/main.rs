//! Updates the VBIOS of a Navi3x GPU through its PSP bootloader.
//!
//! The bootloader only takes a streamed update while no driver has loaded
//! the PSP secure OS, so the GPU has to stay unbound, for example on
//! pci-stub, from power-on until the update.
//!
//! ```text
//! amd-psp-flash check p.rom
//! amd-psp-flash 0000:03:00.0 info
//! amd-psp-flash 0000:03:00.0 read rom.bin
//! amd-psp-flash 0000:03:00.0 flash p.rom
//! ```

mod bar;
mod flash;
mod ifwi;
mod psp;

use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::time::Duration;

use crate::bar::Bar;
use crate::flash::{Event, Flasher};
use crate::ifwi::{Ifwi, Item, ROM_SIZE};
use crate::psp::{Command, Psp};

const USAGE: &str = "usage: amd-psp-flash check <image>
       amd-psp-flash <pci-address> info | read <file> | flash <image>";

#[derive(Debug)]
enum Error {
    Flash(flash::Error),
    Image(PathBuf, ifwi::Error),
    Io(PathBuf, io::Error),
    Mismatch { location: usize },
    Psp(psp::Error),
    Readback(ifwi::Error),
    SecureOs(u32),
    Usage,
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Flash(_) => write!(f, "the update failed"),
            Self::Image(path, _) => write!(f, "{} is not a Navi3x IFWI", path.display()),
            Self::Io(path, _) => write!(f, "cannot access {}", path.display()),
            Self::Mismatch { location } => write!(
                f,
                "the slot the bootloader boots next, at {location:#x}, does not hold the image"
            ),
            Self::Psp(_) => write!(f, "the PSP bootloader did not answer"),
            Self::Readback(_) => {
                write!(f, "the SPI ROM does not hold a valid IFWI after the update")
            }
            Self::SecureOs(version) => write!(
                f,
                "a driver loaded the PSP secure OS {version:#010x}, boot with the GPU on pci-stub"
            ),
            Self::Usage => f.write_str(USAGE),
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Flash(err) => Some(err),
            Self::Image(_, err) | Self::Readback(err) => Some(err),
            Self::Io(_, err) => Some(err),
            Self::Psp(err) => Some(err),
            Self::Mismatch { .. } | Self::SecureOs(_) | Self::Usage => None,
        }
    }
}

impl From<psp::Error> for Error {
    fn from(err: psp::Error) -> Self {
        Self::Psp(err)
    }
}

fn open(address: &str) -> Result<Psp, Error> {
    let device = Path::new("/sys/bus/pci/devices").join(address);
    let bar = Bar::open(&device).map_err(|err| Error::Io(device.join("resource5"), err))?;
    Ok(Psp::new(bar))
}

fn info(psp: &Psp) -> Result<(), Error> {
    println!("secure OS: {:#010x}", psp.sos_version());
    println!("boot partition: {}", psp.query(Command::GetBootPartition)?);
    println!("framebuffer state: {}", psp.query(Command::GetFbState)?);
    println!(
        "SPI JEDEC ID: {:06x}",
        psp.query(Command::SpiGetModelId)? & 0xFF_FFFF
    );
    Ok(())
}

fn read(psp: &Psp, path: &Path) -> Result<(), Error> {
    let mut rom = vec![0; ROM_SIZE];
    psp.read_rom(&mut rom);
    fs::write(path, rom).map_err(|err| Error::Io(path.to_owned(), err))
}

fn render(event: Event) {
    match event {
        Event::Start { item, len, last } => {
            println!(
                "item {item}: {len:#x} bytes{}",
                if last { ", last" } else { "" }
            );
        }
        Event::Progress { item, sent, len } => println!("item {item}: {sent:#x} of {len:#x}"),
        Event::Retry { item, offset } => println!("item {item}: resending the word at {offset:#x}"),
        Event::Done { item, retries } => println!("item {item}: done, {retries} resent"),
    }
}

fn flash(psp: &Psp, path: &Path) -> Result<(), Error> {
    match psp.sos_version() {
        0 => {}
        u32::MAX => return Err(psp::Error::Gone.into()),
        version => return Err(Error::SecureOs(version)),
    }
    let bytes = fs::read(path).map_err(|err| Error::Io(path.to_owned(), err))?;
    let ifwi = Ifwi::parse(&bytes).map_err(|err| Error::Image(path.to_owned(), err))?;
    let partition = ifwi
        .item(Item::PARTITION)
        .expect("parse maps the partition");

    let flasher = Flasher {
        ifwi: &ifwi,
        psp,
        word_pause: Duration::from_micros(200),
    };
    flasher.run(render).map_err(Error::Flash)?;

    let mut rom = vec![0; ROM_SIZE];
    psp.read_rom(&mut rom);
    let written = Ifwi::parse(&rom).map_err(Error::Readback)?;
    let slot = written.next_slot();
    if written.slot_partition(slot, partition.len()) != Some(partition) {
        return Err(Error::Mismatch {
            location: slot.location,
        });
    }
    println!(
        "verified: slot {:#x} at {:#x} holds the image and boots next",
        slot.id, slot.location
    );
    Ok(())
}

fn check(path: &Path) -> Result<(), Error> {
    let bytes = fs::read(path).map_err(|err| Error::Io(path.to_owned(), err))?;
    let ifwi = Ifwi::parse(&bytes).map_err(|err| Error::Image(path.to_owned(), err))?;
    for (item, range) in ifwi.items() {
        println!("item {item}: {:#08x}..{:#08x}", range.start, range.end);
    }
    for slot in ifwi.slots() {
        println!(
            "slot {:#x}: partition at {:#x}, priority {}",
            slot.id, slot.location, slot.priority
        );
    }
    Ok(())
}

fn run(args: &[String]) -> Result<(), Error> {
    match args {
        [command, path] if command == "check" => check(Path::new(path)),
        [address, command] if command == "info" => info(&open(address)?),
        [address, command, path] if command == "read" => read(&open(address)?, Path::new(path)),
        [address, command, path] if command == "flash" => flash(&open(address)?, Path::new(path)),
        _ => Err(Error::Usage),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprint!("amd-psp-flash: {err}");
            let mut source = std::error::Error::source(&err);
            while let Some(cause) = source {
                eprint!(": {cause}");
                source = cause.source();
            }
            eprintln!();
            ExitCode::FAILURE
        }
    }
}
