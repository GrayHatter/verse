pub const endian = builtin.target.cpu.arch.endian();

const default_sigset: posix.sigset_t = defaultSigSet();
pub fn defaultSigSet() posix.sigset_t {
    var sigset: posix.sigset_t = posix.sigemptyset();
    posix.sigaddset(&sigset, .INT);
    posix.sigaddset(&sigset, .HUP);
    posix.sigaddset(&sigset, .QUIT);
    return sigset;
}

pub fn installSignals() void {
    // TODO support other platforms
    posix.sigprocmask(posix.SIG.BLOCK, &default_sigset, null);
}

pub const pollfd = linux.pollfd;
pub const O = linux.O;
pub const signalfd = posix.signalfd;
pub const ppoll = posix.ppoll;
pub const signalfd_siginfo = linux.signalfd_siginfo;

const linux = std.os.linux;
const posix = std.posix;
const std = @import("std");
const builtin = @import("builtin");
