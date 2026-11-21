//! Attaches USB devices from Silex USB device servers to the local machine.
//!
//! sxlink reserves a device over JCP, opens its SXUPTP session and connects
//! that session to a `vhci_hcd` port. The device then shows up like a local
//! USB device. `attach` runs in the foreground until the device goes away.
//!
//! ```text
//! sxlink list 10.0.15.194
//! sxlink attach 10.0.15.194 A104ADD8 --take
//! sxlink release 10.0.15.194 usb4-003:0
//! ```

mod bridge;
mod error;
mod jcp;
mod log;
mod sxuptp;
mod usbip;
mod vhci;

use std::error::Error as _;
use std::net::{IpAddr, SocketAddr, TcpStream};
use std::os::fd::OwnedFd;
use std::os::unix::net::UnixStream;
use std::process::ExitCode;

use crate::bridge::Bridge;
use crate::error::{Error, Result};
use crate::jcp::Client;

const USAGE: &str = "usage: sxlink [-v] list <server>
       sxlink [-v] attach <server> <port|serial> [--take]
       sxlink [-v] release <server> <port|serial>";

enum Action {
    Attach {
        selector: String,
        server: IpAddr,
        take: bool,
    },
    List {
        server: IpAddr,
    },
    Release {
        selector: String,
        server: IpAddr,
    },
}

impl Action {
    fn parse(mut args: Vec<String>) -> Result<Self> {
        if let Some(i) = args.iter().position(|a| a == "-v") {
            args.remove(i);
            log::enable();
        }
        let take = args
            .iter()
            .position(|a| a == "--take")
            .map(|i| args.remove(i))
            .is_some();
        let server = |s: &String| s.parse().map_err(|_| Error::Usage);
        match args.as_slice() {
            [cmd, s] if cmd == "list" && !take => Ok(Self::List { server: server(s)? }),
            [cmd, s, sel] if cmd == "attach" => Ok(Self::Attach {
                selector: sel.clone(),
                server: server(s)?,
                take,
            }),
            [cmd, s, sel] if cmd == "release" && !take => Ok(Self::Release {
                selector: sel.clone(),
                server: server(s)?,
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
            } => attach(server, &selector, take),
            Self::List { server } => list(server),
            Self::Release { selector, server } => release(server, &selector),
        }
    }
}

fn attach(server: IpAddr, selector: &str, take: bool) -> Result<()> {
    let client = Client::new(server)?;
    let device = client.find(selector)?;
    if !device.present {
        return Err(Error::DeviceAbsent { port: device.port });
    }
    match device.owner {
        Some(owner) if owner == client.local() => client.disconnect(&device.port, owner)?,
        Some(owner) if take => {
            eprintln!("releasing {} from {owner}", device.port);
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
    eprintln!(
        "attached {} {:04x}:{:04x} ({}) to vhci port {}",
        device.port,
        device.vid,
        device.pid,
        device.name,
        port.number()
    );

    let result = Bridge::new(&n, tcp, ours).run();
    // The kernel usually detaches by itself when the socket closes.
    let _ = port.detach();
    result
}

fn list(server: IpAddr) -> Result<()> {
    let client = Client::new(server)?;
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
    let result = Action::parse(std::env::args().skip(1).collect()).and_then(Action::run);
    match result {
        Ok(()) => ExitCode::SUCCESS,
        Err(Error::Usage) => {
            eprintln!("{USAGE}");
            ExitCode::from(2)
        }
        Err(err) => {
            let mut msg = format!("sxlink: {err}");
            let mut source = err.source();
            while let Some(s) = source {
                msg.push_str(&format!(": {s}"));
                source = s.source();
            }
            eprintln!("{msg}");
            ExitCode::FAILURE
        }
    }
}

fn release(server: IpAddr, selector: &str) -> Result<()> {
    let client = Client::new(server)?;
    let device = client.find(selector)?;
    match device.owner {
        Some(owner) => {
            client.disconnect(&device.port, owner)?;
            eprintln!("released {} from {owner}", device.port);
        }
        None => eprintln!("{} is not reserved", device.port),
    }
    Ok(())
}
