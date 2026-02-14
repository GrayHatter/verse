pub const pollfd = linux.pollfd;
pub const mode_t = linux.mode_t;

// TODO decide if system.zig should be a thick or thin wrappper
pub const Mode = linux.mode_t;

pub const O = linux.O;
pub const signalfd = posix.signalfd;
pub const ppoll = posix.ppoll;
pub const signalfd_siginfo = linux.signalfd_siginfo;

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

pub fn chmodPath(path: [*:0]const u8, mode: Mode) !void {
    const ret: i32 = @intCast(linux.chmod(path, mode));
    switch (ret) {
        std.math.minInt(i32)...-1 => return error.Unexpected,
        else => return,
    }
}

test {
    _ = &std.testing.refAllDecls(@This());
}

const linux = std.os.linux;
const posix = std.posix;
const std = @import("std");
const builtin = @import("builtin");
