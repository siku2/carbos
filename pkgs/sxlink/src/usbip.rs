//! The USB/IP data protocol that `vhci_hcd` speaks on its socket.
//!
//! Every PDU has a 48 byte big-endian header: a 20 byte basic part and a
//! 28 byte command specific part. See `Documentation/usb/usbip_protocol.rst`
//! in the kernel tree.

/// Negative errno values used in replies.
pub(crate) mod errno {
    pub(crate) const ECONNRESET: i32 = -104;
    pub(crate) const EOVERFLOW: i32 = -75;
    pub(crate) const EPIPE: i32 = -32;
    pub(crate) const EPROTO: i32 = -71;
    pub(crate) const EXDEV: i32 = -18;
}

use std::io::{self, Read, Write};

use zerocopy::byteorder::{BE, I32, U32};
use zerocopy::{FromBytes, FromZeros, Immutable, IntoBytes, KnownLayout, Unaligned};

use crate::error::{Error, Result};

const CMD_SUBMIT: u32 = 1;
const CMD_UNLINK: u32 = 2;
const ISO_DESC_LEN: usize = 16;
const RET_SUBMIT: u32 = 3;
const RET_UNLINK: u32 = 4;

/// The common part of every PDU.
#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct Basic {
    command: U32<BE>,
    seqnum: U32<BE>,
    devid: U32<BE>,
    direction: U32<BE>,
    ep: U32<BE>,
}

/// A whole 48 byte header with the command specific part still raw.
#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct Header {
    basic: Basic,
    body: [u8; 28],
}

#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct CmdSubmit {
    transfer_flags: U32<BE>,
    transfer_buffer_length: U32<BE>,
    start_frame: I32<BE>,
    number_of_packets: U32<BE>,
    interval: I32<BE>,
    setup: [u8; 8],
}

#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct CmdUnlink {
    unlink_seqnum: U32<BE>,
    padding: [u8; 24],
}

#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct RetSubmit {
    status: I32<BE>,
    actual_length: U32<BE>,
    start_frame: I32<BE>,
    number_of_packets: I32<BE>,
    error_count: I32<BE>,
    padding: [u8; 8],
}

#[repr(C)]
#[derive(FromBytes, Immutable, IntoBytes, KnownLayout, Unaligned)]
struct RetUnlink {
    status: I32<BE>,
    padding: [u8; 24],
}

/// A command from `vhci_hcd`.
pub(crate) enum Command {
    Submit(Submit),
    Unlink { seqnum: u32, target: u32 },
}

impl Command {
    /// Reads one command. Returns `None` on end of stream.
    pub(crate) fn read(r: &mut impl Read) -> Result<Option<Self>> {
        let mut h = Header::new_zeroed();
        match r.read_exact(h.as_mut_bytes()) {
            Ok(()) => {}
            Err(e) if e.kind() == io::ErrorKind::UnexpectedEof => return Ok(None),
            Err(e) => return Err(Error::VhciSocket(e)),
        }
        let seqnum = h.basic.seqnum.get();
        match h.basic.command.get() {
            CMD_SUBMIT => Submit::read(r, &h).map(|s| Some(Self::Submit(s))),
            CMD_UNLINK => {
                let body = CmdUnlink::ref_from_bytes(&h.body).expect("body is 28 bytes");
                Ok(Some(Self::Unlink {
                    seqnum,
                    target: body.unlink_seqnum.get(),
                }))
            }
            other => Err(Error::UsbipUnknownCommand(other)),
        }
    }
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

impl Submit {
    /// Reads the OUT data and iso descriptors that follow the header.
    fn read(r: &mut impl Read, h: &Header) -> Result<Self> {
        let body = CmdSubmit::ref_from_bytes(&h.body).expect("body is 28 bytes");
        let dir_in = h.basic.direction.get() == 1;
        let buffer_length = body.transfer_buffer_length.get();
        let iso_packets = match body.number_of_packets.get() {
            u32::MAX => 0,
            n => n,
        };
        let mut data = Vec::new();
        if !dir_in {
            data.resize(buffer_length as usize, 0);
            r.read_exact(&mut data).map_err(Error::VhciSocket)?;
        }
        let mut iso = vec![0; iso_packets as usize * ISO_DESC_LEN];
        r.read_exact(&mut iso).map_err(Error::VhciSocket)?;
        Ok(Self {
            buffer_length,
            data,
            dir_in,
            ep: h.basic.ep.get() as u8,
            iso_packets,
            seqnum: h.basic.seqnum.get(),
            setup: body.setup,
        })
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
        let mut h = Header::new_zeroed();
        let data = match *self {
            Self::Submit {
                actual,
                data,
                seqnum,
                status,
            } => {
                h.basic.command.set(RET_SUBMIT);
                h.basic.seqnum.set(seqnum);
                let body = RetSubmit {
                    status: status.into(),
                    actual_length: actual.into(),
                    ..RetSubmit::new_zeroed()
                };
                h.body.copy_from_slice(body.as_bytes());
                data
            }
            Self::Unlink { seqnum, status } => {
                h.basic.command.set(RET_UNLINK);
                h.basic.seqnum.set(seqnum);
                let body = RetUnlink {
                    status: status.into(),
                    ..RetUnlink::new_zeroed()
                };
                h.body.copy_from_slice(body.as_bytes());
                &[]
            }
        };
        let mut pdu = Vec::with_capacity(size_of::<Header>() + data.len());
        pdu.extend_from_slice(h.as_bytes());
        pdu.extend_from_slice(data);
        w.write_all(&pdu)
    }
}
