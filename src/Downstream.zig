gateway: Gateway,
reader: *Io.Reader,
writer: *Io.Writer,

phase: Phase,

const Downstream = @This();

pub const Gateway = union(enum) {
    zwsgi: Zwsgi,
    http: Http,
    buffer: Buffer,
    none: None,

    var failing_buf: Buffer = .{
        .reader = .failing,
        .writer = .failing,
    };

    pub const failing: Gateway = .{
        .none = .empty,
    };

    pub fn preAlloc(a: Allocator) error{OutOfMemory}!Gateway {
        return .{ .none = try .init(a) };
    }

    pub const Zwsgi = struct {
        zwsgi: zWSGI.Request,
        reader: Io.net.Stream.Reader,
        writer: Io.net.Stream.Writer,

        pub fn init(z: *Zwsgi, s: Io.net.Stream, gw: Gateway.None, a: Allocator, io: Io) !void {
            z.reader = s.reader(io, gw.r_b);
            z.writer = s.writer(io, gw.w_b);
            z.zwsgi = try .init(&z.reader.interface, a);
        }
    };

    pub const Http = struct {
        http: std.http.Server,
        reader: Io.net.Stream.Reader,
        writer: Io.net.Stream.Writer,

        pub fn init(h: *Http, s: Io.net.Stream, gw: Gateway.None, io: Io) void {
            h.reader = s.reader(io, gw.r_b);
            h.writer = s.writer(io, gw.w_b);
            h.http = .init(&h.reader.interface, &h.writer.interface);
        }
    };

    pub const Buffer = struct {
        reader: Io.Reader,
        writer: Io.Writer,

        pub fn init(h: *Buffer, gw: Gateway.None) void {
            h.reader = .fixed(gw.r_b);
            h.writer = .fixed(gw.w_b);
        }
    };

    pub const None = struct {
        r_b: []u8,
        w_b: []u8,

        pub const empty: None = .{ .r_b = &.{}, .w_b = &.{} };

        pub fn init(a: Allocator) error{OutOfMemory}!None {
            const r_b: []u8 = try a.alloc(u8, 0x10000);
            errdefer a.free(r_b);
            const w_b: []u8 = try a.alloc(u8, 0x40000);
            return .{
                .r_b = r_b,
                .w_b = w_b,
            };
        }
    };
};

pub const Error = error{WriteFailed};
// Largest single IP packet size
pub const ONESHOT_SIZE = 14720;

pub fn init(a: Allocator) error{OutOfMemory}!Downstream {
    return .{
        .phase = .new,
        .gateway = try .preAlloc(a),
        .reader = &Gateway.failing_buf.reader,
        .writer = &Gateway.failing_buf.writer,
    };
}

pub fn http(ds: *Downstream, s: Io.net.Stream, io: Io) !void {
    const b: Gateway.None = ds.gateway.none;
    ds.gateway = .{ .http = undefined };
    ds.gateway.http.init(s, b, io);
    ds.reader = &ds.gateway.http.reader.interface;
    ds.writer = &ds.gateway.http.writer.interface;
}

pub fn zwsgi(ds: *Downstream, s: Io.net.Stream, a: Allocator, io: Io) !void {
    const b: Gateway.None = ds.gateway.none;
    ds.gateway = .{ .zwsgi = undefined };
    try ds.gateway.zwsgi.init(s, b, a, io);
    ds.reader = &ds.gateway.zwsgi.reader.interface;
    ds.writer = &ds.gateway.zwsgi.writer.interface;
}

pub fn buffer(ds: *Downstream) void {
    const b: Gateway.None = ds.gateway.none;
    ds.gateway = .{ .buffer = undefined };
    ds.gateway.buffer.init(b);
    ds.reader = &ds.gateway.buffer.reader;
    ds.writer = &ds.gateway.buffer.writer;
}

const Frame = @import("Frame.zig");
const Phase = Frame.Phase;
const zWSGI = @import("zwsgi.zig");
const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
