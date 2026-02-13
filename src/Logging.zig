//! Logging
//! Logging will be disabled when both path and sout are null
//! Both Logging and Debug logging will be sent to serr when set

path: ?[]const u8,
sout: ?File,
serr: ?File = .stderr(),

/// Default when running as a daemon
pub const default: Logging = .{
    .path = "/var/log/verse.log",
    .sout = null,
};

/// Default when running in the foreground
pub const stdout: Logging = .{
    .path = "/dev/stdout",
    .sout = .stdout(),
};

pub const devnull: Logging = .{
    .path = "/dev/null",
    .sout = null,
};

const Logging = @This();

pub const default_prefix = "/var/log/verse/";

var mutex: Io.Mutex = .{};

//pub const log: *Logging = &global_logger;
var global_logger: Logging = undefined;

pub fn setGlobal(l: Logging) !void {
    global_logger = l;
}

pub fn getGlobal() *const Logging {
    return &global_logger;
}

pub fn log(l: Logging, comptime str: []const u8, args: anytype) void {
    if (l.sout) |out| {
        mutex.lock();
        defer mutex.unlock();
        out.print(str, args) catch @panic("Failed to write to logging sout fd");
        if (l.serr) |stderr| {
            stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
        }
    }
}

pub fn err(l: Logging, comptime str: []const u8, args: anytype) void {
    if (l.serr) |stderr| {
        mutex.lock();
        defer mutex.unlock();

        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

pub fn warn(l: Logging, comptime str: []const u8, args: anytype) void {
    if (l.serr) |stderr| {
        mutex.lock();
        defer mutex.unlock();

        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

pub fn info(l: Logging, comptime str: []const u8, args: anytype) void {
    if (l.serr) |stderr| {
        mutex.lock();
        defer mutex.unlock();

        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

pub fn debug(l: Logging, comptime str: []const u8, args: anytype) void {
    if (l.serr) |stderr| {
        mutex.lock();
        defer mutex.unlock();

        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

const std = @import("std");
const File = std.Io.File;
const Io = std.Io;
