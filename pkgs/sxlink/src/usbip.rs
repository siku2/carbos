//! The USB/IP data protocol that `vhci_hcd` speaks on its socket.
//!
//! Every PDU has a 48 byte big-endian header. See the kernel documentation
//! in `Documentation/usb/usbip_protocol.rst`.

/// Negative errno values used in replies.
pub(crate) mod errno {
    pub(crate) const ECONNRESET: i32 = -104;
    pub(crate) const EOVERFLOW: i32 = -75;
    pub(crate) const EPIPE: i32 = -32;
    pub(crate) const EPROTO: i32 = -71;
    pub(crate) const EXDEV: i32 = -18;
}

use std::io::{self, Read, Write};

use crate::error::{Error, Result};

const CMD_SUBMIT: u32 = 1;
const CMD_UNLINK: u32 = 2;
const HEADER_LEN: usize = 48;
const ISO_DESC_LEN: usize = 16;
const RET_SUBMIT: u32 = 3;
const RET_UNLINK: u32 = 4;

/// A command from `vhci_hcd`.
pub(crate) enum Command {
    Submit(Submit),
    Unlink { seqnum: u32, target: u32 },
}

pub(crate) struct Submit {
    pub(crate) buffer_length: u32,
    pub(crate) data: Vec<u8>,
    pub(crate) dir_in: bool,
    pub(crate) ep: u8,
    pub(crate) iso_packets: u32,
    pub(crate) seqnum: u32,
    pub(crate) setup: [u8; 8],
}

impl Command {
    /// Reads one command. Returns `None` on end of stream.
    pub(crate) fn read(r: &mut impl Read) -> Result<Option<Self>> {
        let mut h = [0; HEADER_LEN];
        match r.read_exact(&mut h) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
            Err(e) => return Err(Error::VhciSocket(e)),
        }
        let word = |i: usize| u32::from_be_bytes([h[i], h[i + 1], h[i + 2], h[i + 3]]);
        let seqnum = word(4);
        match word(0) {
            CMD_SUBMIT => {
                let dir_in = word(12) == 1;
                let ep = word(16) as u8;
                let buffer_length = word(24);
                let packets = word(32);
                let iso_packets = if packets == u32::MAX { 0 } else { packets };
                let mut setup = [0; 8];
                setup.copy_from_slice(&h[40..48]);
                let mut data = Vec::new();
                if !dir_in {
                    data.resize(buffer_length as usize, 0);
                    r.read_exact(&mut data).map_err(Error::VhciSocket)?;
                }
                let mut iso = vec![0; iso_packets as usize * ISO_DESC_LEN];
                r.read_exact(&mut iso).map_err(Error::VhciSocket)?;
                Ok(Some(Self::Submit(Submit {
                    buffer_length,
                    data,
                    dir_in,
                    ep,
                    iso_packets,
                    seqnum,
                    setup,
                })))
            }
            CMD_UNLINK => Ok(Some(Self::Unlink {
                seqnum,
                target: word(20),
            })),
            other => Err(Error::UsbipUnknownCommand(other)),
        }
    }
}

/// A reply to `vhci_hcd`.
pub(crate) enum Reply<'a> {
    /// `data` is only sent for IN transfers.
    Submit {
        actual: u32,
        data: &'a [u8],
        seqnum: u32,
        status: i32,
    },
    Unlink {
        seqnum: u32,
        status: i32,
    },
}

impl Reply<'_> {
    pub(crate) fn write(&self, w: &mut impl Write) -> io::Result<()> {
        let mut h = [0; HEADER_LEN];
        let (cmd, seqnum, status, data) = match *self {
            Self::Submit {
                actual,
                data,
                seqnum,
                status,
            } => {
                h[24..28].copy_from_slice(&actual.to_be_bytes());
                (RET_SUBMIT, seqnum, status, data)
            }
            Self::Unlink { seqnum, status } => (RET_UNLINK, seqnum, status, &[][..]),
        };
        h[0..4].copy_from_slice(&cmd.to_be_bytes());
        h[4..8].copy_from_slice(&seqnum.to_be_bytes());
        h[20..24].copy_from_slice(&status.to_be_bytes());
        let mut pdu = Vec::with_capacity(HEADER_LEN + data.len());
        pdu.extend_from_slice(&h);
        pdu.extend_from_slice(data);
        w.write_all(&pdu)
    }
}
