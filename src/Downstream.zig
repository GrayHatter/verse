gateway: Gateway,
reader: Io.net.Stream.Reader,
writer: Io.net.Stream.Writer,

phase: Phase,

const Downstream = @This();

pub const Gateway = union(enum) {
    zwsgi: zWSGI.Request,
    http: std.http.Server,
    none: void,
};

pub const Error = error{WriteFailed};
// Largest single IP packet size
pub const ONESHOT_SIZE = 14720;

pub fn init(s: Io.net.Stream, a: Allocator, io: Io) error{OutOfMemory}!Downstream {
    const r_b: []u8 = try a.alloc(u8, 0x10000);
    errdefer a.free(r_b);
    const w_b: []u8 = try a.alloc(u8, 0x40000);

    errdefer comptime unreachable;
    return .{
        .phase = .new,
        .gateway = .none,
        .reader = s.reader(io, r_b),
        .writer = s.writer(io, w_b),
    };
}

pub fn http(ds: *Downstream) !void {
    ds.gateway = .{ .http = .init(&ds.reader.interface, &ds.writer.interface) };
}

pub fn zwsgi(ds: *Downstream, a: Allocator) !void {
    ds.gateway = .{ .zwsgi = try .init(&ds.reader.interface, a) };
}

const Frame = @import("Frame.zig");
const Phase = Frame.Phase;
const zWSGI = @import("zwsgi.zig");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
