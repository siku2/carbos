//! Updates the firmware of a Razer BlackWidow Chroma V2 from the Intel HEX
//! image in Razer's Windows updater.
//!
//! The bootloader stays in place: the app cannot write it and the bootloader
//! ignores writes outside the app. A failed flash leaves the keyboard in the
//! bootloader, and running `flash` again finishes it.
//!
//! ```text
//! razer-kbd-flash check bwc2.hex
//! razer-kbd-flash plan bwc2.hex
//! razer-kbd-flash version
//! razer-kbd-flash flash bwc2.hex
//! ```

mod bootloader;
mod image;
mod razer;
mod usb;

use std::fmt;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::ExitCode;
use std::thread;
use std::time::{Duration, Instant};

use crate::bootloader::{Bootloader, Step, Target};
use crate::image::Plan;
use crate::razer::Keyboard;
use crate::usb::{Device, Hidraw, Id};

const APP: Id = Id {
    bcd_device: None,
    product: 0x0221,
    vendor: 0x1532,
};
/// The bootloader has its own product ID and the keyboard's in bcdDevice.
const BOOTLOADER: Id = Id {
    bcd_device: Some(0x0221),
    product: 0x110D,
    vendor: 0x1532,
};
/// The interface the kernel driver sends commands to.
const COMMAND_INTERFACE: u8 = 1;
/// The razer-kbd kernel driver, which reads the version when it binds.
const DRIVER: &str = "/sys/bus/hid/drivers/razer-kbd";
/// An interface with a hidraw node while the kernel driver is bound.
const QUERY_INTERFACE: u8 = 0;
const USAGE: &str = "usage: razer-kbd-flash check <image> | plan <image> | version | flash <image>";
const WAIT: Duration = Duration::from_secs(20);

#[derive(Debug)]
enum Error {
    Bootloader(Target, bootloader::Error),
    Image(PathBuf, image::Error),
    Io(PathBuf, io::Error),
    Keyboard(razer::Error),
    NoHidraw,
    NoKeyboard,
    NotBound,
    Timeout(&'static str),
    Usage,
    Usb(io::Error),
    Version { expected: String, found: String },
}

impl fmt::Display for Error {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Bootloader(target, _) => {
                write!(f, "{target} failed, run flash again to finish the update")
            }
            Self::Image(path, _) => write!(f, "{} is not a valid image", path.display()),
            Self::Io(path, _) => write!(f, "cannot read {}", path.display()),
            Self::Keyboard(_) => write!(f, "the keyboard did not take the command"),
            Self::NoHidraw => write!(
                f,
                "the keyboard has no hidraw node on interface {QUERY_INTERFACE}"
            ),
            Self::NoKeyboard => write!(f, "no BlackWidow Chroma V2 found"),
            Self::NotBound => write!(f, "the razer-kbd driver is not bound to the keyboard"),
            Self::Timeout(what) => write!(f, "the {what} did not appear"),
            Self::Usage => f.write_str(USAGE),
            Self::Usb(_) => write!(f, "cannot open the USB device"),
            Self::Version { expected, found } => {
                write!(
                    f,
                    "the keyboard runs {found} after the flash, not {expected}"
                )
            }
        }
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        match self {
            Self::Bootloader(_, err) => Some(err),
            Self::Image(_, err) => Some(err),
            Self::Io(_, err) | Self::Usb(err) => Some(err),
            Self::Keyboard(err) => Some(err),
            Self::NoHidraw
            | Self::NoKeyboard
            | Self::NotBound
            | Self::Timeout(_)
            | Self::Usage
            | Self::Version { .. } => None,
        }
    }
}

impl From<razer::Error> for Error {
    fn from(err: razer::Error) -> Self {
        Self::Keyboard(err)
    }
}

fn load(path: &Path) -> Result<Plan, Error> {
    let text = fs::read_to_string(path).map_err(|err| Error::Io(path.to_owned(), err))?;
    Plan::parse(&text).map_err(|err| Error::Image(path.to_owned(), err))
}

/// The steps of a flash, in order. The first flush empties the page buffer
/// that an earlier, aborted run may have left, before the erase.
fn steps(plan: &Plan) -> impl Iterator<Item = Step<'_>> {
    [Step::Flush(&plan.flush)]
        .into_iter()
        .chain(plan.sectors.iter().map(|sector| Step::Erase(*sector)))
        .chain(plan.packets.iter().map(Step::Write))
        .chain([Step::Flush(&plan.flush)])
        .chain(plan.packets.iter().map(Step::Verify))
        .chain([Step::Exit])
}

/// Waits for a device to appear and opens it.
fn wait_for(id: &Id, what: &'static str) -> Result<(PathBuf, Device), Error> {
    let start = Instant::now();
    while start.elapsed() < WAIT {
        if let Some(path) = id.find().map_err(Error::Usb)?
            && let Ok(device) = Device::open(&path)
        {
            return Ok((path, device));
        }
        thread::sleep(Duration::from_millis(100));
    }
    Err(Error::Timeout(what))
}

fn query_keyboard(path: &Path) -> Result<Keyboard, Error> {
    let hidraw = Hidraw::open(path, QUERY_INTERFACE)
        .map_err(Error::Usb)?
        .ok_or(Error::NoHidraw)?;
    Ok(Keyboard::Hidraw(hidraw))
}

/// The version the driver read for the keyboard in sysfs, if it is bound.
fn driver_version(app: &Path) -> io::Result<Option<String>> {
    let app = fs::canonicalize(app)?;
    for entry in fs::read_dir(DRIVER)? {
        let Ok(device) = fs::canonicalize(entry?.path()) else {
            continue;
        };
        if !device.starts_with(&app) {
            continue;
        }
        match fs::read_to_string(device.join("firmware_version")) {
            Ok(version) => return Ok(Some(version.trim().to_owned())),
            Err(err) if err.kind() == io::ErrorKind::NotFound => {}
            Err(err) => return Err(err),
        }
    }
    Ok(None)
}

/// Asks the driver if it is loaded, so the queries do not interleave with its
/// commands. Without it, asks the keyboard.
fn app_version(app: &Path) -> Result<String, Error> {
    if !Path::new(DRIVER).exists() {
        return Ok(query_keyboard(app)?.version()?);
    }
    driver_version(app)
        .map_err(|err| Error::Io(PathBuf::from(DRIVER), err))?
        .ok_or(Error::NotBound)
}

fn version() -> Result<(), Error> {
    let path = APP.find().map_err(Error::Usb)?.ok_or(Error::NoKeyboard)?;
    println!("{}", app_version(&path)?);
    Ok(())
}

fn check(path: &Path) -> Result<(), Error> {
    let plan = load(path)?;
    let first = plan.packets.first().expect("parse rejects empty images");
    let last = plan.packets.last().expect("parse rejects empty images");
    println!("version: {}", plan.version);
    println!(
        "app: {:#06x}..={:#06x} in {} packets",
        first.start,
        last.end(),
        plan.packets.len()
    );
    println!("sectors: {}", plan.sectors.len());
    println!(
        "flush: {:#06x}..={:#06x}",
        plan.flush.start,
        plan.flush.end()
    );
    Ok(())
}

fn print_plan(path: &Path) -> Result<(), Error> {
    let plan = load(path)?;
    println!("enter the bootloader");
    for step in steps(&plan) {
        println!("{step}");
    }
    Ok(())
}

fn flash(path: &Path) -> Result<(), Error> {
    let plan = load(path)?;

    if BOOTLOADER.find().map_err(Error::Usb)?.is_some() {
        println!("the keyboard is in its bootloader, continuing");
    } else {
        let app = APP.find().map_err(Error::Usb)?.ok_or(Error::NoKeyboard)?;
        println!("running {}, flashing {}", app_version(&app)?, plan.version);
        let device = Device::open(&app).map_err(Error::Usb)?;
        device.claim(COMMAND_INTERFACE).map_err(Error::Usb)?;
        let keyboard = Keyboard::Usb(device, COMMAND_INTERFACE);
        if let Err(err) = keyboard.enter_bootloader() {
            if let Err(err) = keyboard.release() {
                eprintln!("razer-kbd-flash: cannot give the keyboard back to its driver: {err}");
            }
            return Err(err.into());
        }
        println!("entered the bootloader");
    }

    let (_, device) = wait_for(&BOOTLOADER, "bootloader")?;
    let bootloader = Bootloader(device);
    let total = steps(&plan).count();
    for (done, step) in steps(&plan).enumerate() {
        bootloader
            .run(&step)
            .map_err(|err| Error::Bootloader(step.target(), err))?;
        if done % 256 == 0 || done + 1 == total {
            println!("{} of {total}", done + 1);
        }
    }

    let (app, _) = wait_for(&APP, "keyboard")?;
    let start = Instant::now();
    let found = loop {
        match app_version(&app) {
            Ok(found) => break found,
            Err(err) if start.elapsed() > WAIT => return Err(err),
            Err(_) => thread::sleep(Duration::from_millis(500)),
        }
    };
    if found != plan.version {
        return Err(Error::Version {
            expected: plan.version,
            found,
        });
    }
    println!("the keyboard runs {found}");
    Ok(())
}

fn run(args: &[String]) -> Result<(), Error> {
    match args {
        [command, path] if command == "check" => check(Path::new(path)),
        [command, path] if command == "plan" => print_plan(Path::new(path)),
        [command] if command == "version" => version(),
        [command, path] if command == "flash" => flash(Path::new(path)),
        _ => Err(Error::Usage),
    }
}

fn main() -> ExitCode {
    let args: Vec<String> = std::env::args().skip(1).collect();
    match run(&args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            eprint!("razer-kbd-flash: {err}");
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
