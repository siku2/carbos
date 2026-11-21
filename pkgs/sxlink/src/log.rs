//! Debug output on stderr, enabled with `-v`.

use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};

static VERBOSE: AtomicBool = AtomicBool::new(false);

pub(crate) fn debug(args: fmt::Arguments<'_>) {
    if VERBOSE.load(Ordering::Relaxed) {
        eprintln!("{args}");
    }
}

pub(crate) fn enable() {
    VERBOSE.store(true, Ordering::Relaxed);
}
