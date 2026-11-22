//! Attaches USB devices from Silex USB device servers to the local machine.
//!
//! sxlink reserves a device over JCP, opens its SXUPTP session and connects
//! that session to a `vhci_hcd` port. The device then shows up like a local
//! USB device. `attach` runs in the foreground until the device goes away.
//!
//! ```text
//! sxlink list ds600.example.org
//! sxlink attach 10.0.15.194 A104ADD8 --take
//! sxlink release 10.0.15.194 usb4-003:0
//! ```

mod bridge;
mod error;
mod jcp;
mod sxuptp;
mod usbip;
mod vhci;

use std::error::Error as _;
use std::net::{IpAddr, SocketAddr, TcpStream};
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream;
use std::process::ExitCode;
use std::thread;

use log::{LevelFilter, error, info};
use signal_hook::consts::{SIGINT, SIGTERM};
use signal_hook::iterator::Signals;

use crate::bridge::Bridge;
use crate::error::{Error, Result};
use crate::jcp::Client;

const USAGE: &str = "usage: sxlink [-v] list <server>
       sxlink [-v] attach <server> <port|serial> [--take]
       sxlink [-v] release <server> <port|serial>";

enum Action {
    Attach {
        selector: String,
        server: String,
        take: bool,
    },
    List {
        server: String,
    },
    Release {
        selector: String,
        server: String,
    },
}

impl Action {
    fn parse(mut args: Vec<String>) -> Result<Self> {
        let take = args
            .iter()
            .position(|a| a == "--take")
            .map(|i| args.remove(i))
            .is_some();
        match args.as_slice() {
            [cmd, s] if cmd == "list" && !take => Ok(Self::List { server: s.clone() }),
            [cmd, s, sel] if cmd == "attach" => Ok(Self::Attach {
                selector: sel.clone(),
                server: s.clone(),
                take,
            }),
            [cmd, s, sel] if cmd == "release" && !take => Ok(Self::Release {
                selector: sel.clone(),
                server: s.clone(),
            }),
            _ => Err(Error::Usage),
        }
    }

    fn run(self) -> Result<()> {
        match self {
            Self::Attach {
                selector,
                server,
                take,
            } => attach(&server, &selector, take),
            Self::List { server } => list(&server),
            Self::Release { selector, server } => release(&server, &selector),
        }
    }
}

fn attach(server: &str, selector: &str, take: bool) -> Result<()> {
    let client = Client::open(server)?;
    let device = client.find(selector)?;
    if !device.present {
        return Err(Error::DeviceAbsent { port: device.port });
    }
    match device.owner {
        Some(owner) if owner == client.local() => client.disconnect(&device.port, owner)?,
        Some(owner) if take => {
            info!("releasing {} from {owner}", device.port);
            client.disconnect(&device.port, owner)?;
        }
        Some(owner) => {
            return Err(Error::DeviceBusy {
                owner,
                port: device.port,
            });
        }
        None => {}
    }

    let n = client.connect(&device.port)?;
    if n.crypto != 0 {
        return Err(Error::Encrypted { offer: n.crypto });
    }
    if n.sessions > 1 {
        return Err(Error::MultiSession { count: n.sessions });
    }
    let host = n.server.map_or(client.server(), IpAddr::V4);
    let tcp =
        TcpStream::connect(SocketAddr::new(host, n.tcp_port)).map_err(Error::ServerConnect)?;
    tcp.set_nodelay(true).map_err(Error::ServerConnect)?;

    let (ours, kernel) = UnixStream::pair().map_err(Error::VhciSocket)?;
    let devid = u32::from(n.bus) << 16 | u32::from(n.addr);
    let port = vhci::Port::attach(&OwnedFd::from(kernel), devid, n.speed)?;
    info!(
        "attached {} {:04x}:{:04x} ({}) to vhci port {}",
        device.port,
        device.vid,
        device.pid,
        device.name,
        port.number()
    );

    let mut signals = Signals::new([SIGINT, SIGTERM]).map_err(Error::Signals)?;
    let signals_handle = signals.handle();
    let bridge = Bridge::new(&n, tcp, ours);
    let result = thread::scope(|s| {
        s.spawn(|| {
            if let Some(signal) = signals.forever().next() {
                info!("stopping on signal {signal}");
                bridge.stop();
            }
        });
        let result = bridge.run();
        signals_handle.close();
        result
    });
    // The kernel usually detaches by itself when the socket closes.
    let _ = port.detach();
    info!("detached {}", device.port);
    result
}

fn list(server: &str) -> Result<()> {
    let client = Client::open(server)?;
    println!(
        "{:<12} {:<9} {:<10} {:<16} {:<16} NAME",
        "PORT", "ID", "LOCATION", "SERIAL", "OWNER"
    );
    for d in client.devices()? {
        let owner = match (d.present, d.owner) {
            (false, _) => "(empty)".to_owned(),
            (true, Some(o)) => o.to_string(),
            (true, None) => "-".to_owned(),
        };
        println!(
            "{:<12} {:04x}:{:04x} {:<10} {:<16} {:<16} {}",
            d.port, d.vid, d.pid, d.location, d.serial, owner, d.name
        );
    }
    Ok(())
}

fn main() -> ExitCode {
    let mut args: Vec<String> = std::env::args().skip(1).collect();
    let verbose = args
        .iter()
        .position(|a| a == "-v")
        .map(|i| args.remove(i))
        .is_some();
    env_logger::Builder::new()
        .filter_level(if verbose {
            LevelFilter::Debug
        } else {
            LevelFilter::Info
        })
        .format_target(false)
        .init();

    let result = Action::parse(args).and_then(Action::run);
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(Error::Usage) => {
            eprintln!("{USAGE}");
            ExitCode::from(2)
        }
        Err(err) => {
            let mut msg = err.to_string();
            let mut source = err.source();
            while let Some(s) = source {
                msg.push_str(&format!(": {s}"));
                source = s.source();
            }
            error!("{msg}");
            ExitCode::FAILURE
        }
    }
}

fn release(server: &str, selector: &str) -> Result<()> {
    let client = Client::open(server)?;
    let device = client.find(selector)?;
    match device.owner {
        Some(owner) => {
            client.disconnect(&device.port, owner)?;
            info!("released {} from {owner}", device.port);
        }
        None => info!("{} is not reserved", device.port),
    }
    Ok(())
}
