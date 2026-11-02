use std::fs::OpenOptions;
use std::io;
use std::os::fd::AsRawFd;
use std::path::Path;
use std::ptr::{self, NonNull};

const PROT_READ: i32 = 1;
const PROT_WRITE: i32 = 2;
const MAP_SHARED: i32 = 1;

unsafe extern "C" {
    fn mmap(addr: *mut u8, len: usize, prot: i32, flags: i32, fd: i32, off: i64) -> *mut u8;
    fn munmap(addr: *mut u8, len: usize) -> i32;
}

/// The MMIO register BAR of a Navi3x GPU.
pub(crate) struct Bar {
    base: NonNull<u32>,
    len: usize,
}

impl Bar {
    pub(crate) fn open(device: &Path) -> io::Result<Self> {
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .open(device.join("resource5"))?;
        let len = usize::try_from(file.metadata()?.len()).map_err(io::Error::other)?;
        // SAFETY: a fresh shared mapping of the whole BAR, unmapped in drop.
        let base = unsafe {
            mmap(
                ptr::null_mut(),
                len,
                PROT_READ | PROT_WRITE,
                MAP_SHARED,
                file.as_raw_fd(),
                0,
            )
        };
        if base as isize == -1 {
            return Err(io::Error::last_os_error());
        }
        let base =
            NonNull::new(base.cast()).ok_or_else(|| io::Error::other("mmap returned null"))?;
        Ok(Self { base, len })
    }

    fn slot(&self, offset: usize) -> *mut u32 {
        assert!(
            offset.is_multiple_of(4) && offset < self.len,
            "register {offset:#x} outside the BAR"
        );
        // SAFETY: in bounds and aligned, checked above.
        unsafe { self.base.as_ptr().add(offset / 4) }
    }

    pub(crate) fn read(&self, offset: usize) -> u32 {
        // SAFETY: a valid MMIO register, see slot.
        unsafe { self.slot(offset).read_volatile() }
    }

    pub(crate) fn write(&self, offset: usize, value: u32) {
        // SAFETY: a valid MMIO register, see slot.
        unsafe { self.slot(offset).write_volatile(value) }
    }
}

impl Drop for Bar {
    fn drop(&mut self) {
        // SAFETY: the mapping from open.
        unsafe { munmap(self.base.as_ptr().cast(), self.len) };
    }
}
