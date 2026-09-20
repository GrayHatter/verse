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

var mutex: Io.Mutex = .init;
var global_logger: Logging = undefined;

pub fn setGlobal(l: Logging) !void {
    global_logger = l;
}

pub fn getGlobal() *const Logging {
    return &global_logger;
}

pub const LoggerData = struct {
    prefix: []const u8 = "Verse",
    request_time: Io.Timestamp = .zero,
    address: []const u8,
    method: Method,
    uri: Uri,
    user_agent: []const u8,
    status: Status,
    response_time: f64 = 0.0,

    const Method = @import("Request.zig").Methods;
    const Status = std.http.Status;
    const Uri = @import("Uri.zig");
    const UserAgent = @import("UserAgent.zig");
};

pub fn req(l: Logging, data: LoggerData) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [64]u8 = undefined;
    if (l.sout) |out| {
        mutex.lock(io) catch return;
        defer mutex.unlock(io);
        var wout = out.writer(io, &buffer);
        defer wout.interface.flush() catch {};

        wout.interface.print(
            "{s}: [{d: >4.2}] {s: >15} | {}:{d} {f: <35} -- \"{s}\"",
            .{
                data.prefix, data.response_time, data.address, data.method, data.status,
                data.uri,    data.user_agent,
            },
        ) catch @panic("Failed to write to logging sout fd");

        if (l.serr) |serr| {
            var err_buffer: [64]u8 = undefined;
            var werr = serr.writer(io, &err_buffer);
            defer werr.interface.flush() catch {};
            werr.interface.print(
                "{s}: [{d: >4.2}] {s: >15} | {}:{d} {f: <35} -- \"{s}\"",
                .{
                    data.prefix, data.response_time, data.address, data.method, data.status,
                    data.uri,    data.user_agent,
                },
            ) catch @panic("Failed to write to logging serr fd");
        }
    }
}

pub fn log(l: Logging, comptime str: []const u8, args: anytype) void {
    const io = std.Options.debug_io;
    const prev = io.swapCancelProtection(.blocked);
    defer _ = io.swapCancelProtection(prev);
    var buffer: [64]u8 = undefined;
    if (l.sout) |out| {
        mutex.lock(io) catch return;
        defer mutex.unlock(io);
        var wout = out.writer(io, &buffer);
        defer wout.interface.flush() catch {};
        wout.interface.print(str, args) catch @panic("Failed to write to logging sout fd");
        if (l.serr) |serr| {
            var err_buffer: [64]u8 = undefined;
            var werr = serr.writer(io, &err_buffer);
            defer werr.interface.flush() catch {};
            werr.interface.print(str, args) catch @panic("Failed to write to logging serr fd");
        }
    }
}

pub fn err(l: Logging, comptime str: []const u8, args: anytype) void {
    const io = std.Options.debug_io;
    var buffer: [64]u8 = undefined;
    if (l.serr) |stderr| {
        mutex.lock(io);
        defer mutex.unlock(io);

        var werr = stderr.writer(io, &buffer);
        defer werr.interface.flush() catch {};
        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

pub fn warn(l: Logging, comptime str: []const u8, args: anytype) void {
    const io = std.Options.debug_io;
    var buffer: [64]u8 = undefined;
    if (l.serr) |stderr| {
        mutex.lock(io);
        defer mutex.unlock(io);

        var werr = stderr.writer(io, &buffer);
        defer werr.interface.flush() catch {};
        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

pub fn info(l: Logging, comptime str: []const u8, args: anytype) void {
    const io = std.Options.debug_io;
    var buffer: [64]u8 = undefined;
    if (l.serr) |stderr| {
        mutex.lock(io);
        defer mutex.unlock(io);

        var werr = stderr.writer(io, &buffer);
        defer werr.interface.flush() catch {};
        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

pub fn debug(l: Logging, comptime str: []const u8, args: anytype) void {
    const io = std.Options.debug_io;
    var buffer: [64]u8 = undefined;
    if (l.serr) |stderr| {
        mutex.lock(io);
        defer mutex.unlock(io);

        var werr = stderr.writer(io, &buffer);
        defer werr.interface.flush() catch {};
        stderr.print(str, args) catch @panic("Failed to write to logging serr fd");
    }
}

const std = @import("std");
const File = std.Io.File;
const Io = std.Io;
