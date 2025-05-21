frame: *Frame,

const Websocket = @This();

pub const Error = WriteError || MemError || ReadError;

pub const MemError = error{
    OutOfMemory,
};

pub const WriteError = error{
    IOWriteFailure,
} || MemError;

pub const ReadError = error{
    IOReadFailure,
    RequiredHeaderMissing,
} || MemError;

pub fn accept(frame: *Frame) Error!Websocket {
    const key = if (frame.request.headers.getCustom("Sec-WebSocket-Key")) |key|
        key.list[0]
    else
        return error.RequiredHeaderMissing;

    try respond(frame, key);
    return Websocket{ .frame = frame };
}

fn respond(f: *Frame, key: []const u8) WriteError!void {
    f.status = .switching_protocols;
    f.content_type = null;

    try f.headers.addCustom(f.alloc, "Upgrade", "websocket");
    try f.headers.addCustom(f.alloc, "Connection", "Upgrade");

    var digest: [Hash.digest_length]u8 = undefined;
    var encoded: [28]u8 = undefined;
    var sha = Hash.init(.{});
    sha.update(key);
    sha.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    sha.final(&digest);
    const accept_key = base64.encode(&encoded, &digest);
    try f.headers.addCustom(f.alloc, "Sec-WebSocket-Accept", accept_key);

    f.sendHeaders() catch return error.IOWriteFailure;
    f.sendRawSlice("\r\n") catch return error.IOWriteFailure;
}

pub fn send(ws: Websocket, msg: []const u8) WriteError!void {
    const m = Message.init(msg, .text);

    return ws.frame.request.downstream.writevAll(
        @ptrCast(@constCast(m.toVec()[0..3])),
    ) catch |err| switch (err) {
        else => return error.IOWriteFailure,
    };
}

pub fn recieve(ws: *Websocket, buffer: []align(8) u8) Error!Message {
    var reader = switch (ws.frame.request.downstream) {
        .zwsgi => |z| z.conn.stream.reader(),
        .http => |h| h.server.connection.stream.reader(),
        else => unreachable,
    };
    return Message.read(reader.any(), buffer) catch error.IOReadFailure;
}

pub const Message = struct {
    header: Header,
    length: union(enum) {
        tiny: u7,
        small: u16,
        large: u64,
    },
    mask: [4]u8 align(4) = undefined,
    msg: []u8,

    pub const Header = if (endian == .big)
        packed struct(u16) {
            extlen: u7,
            mask: bool = false,
            opcode: Opcode,
            reserved: u3 = 0,
            final: bool = true,
        }
    else
        packed struct(u16) {
            opcode: Opcode,
            reserved: u3 = 0,
            final: bool = true,
            extlen: u7,
            mask: bool = false,
        };

    pub fn init(msg: []const u8, code: Opcode) Message {
        const message: Message = .{
            .header = .{
                .opcode = code,
                .extlen = switch (msg.len) {
                    0...125 => |l| @truncate(l),
                    126...0xffff => 126,
                    else => 127,
                },
            },
            .length = switch (msg.len) {
                0...125 => .{ .tiny = @truncate(msg.len) },
                126...0xffff => |len| .{ .small = nativeToBig(u16, @truncate(len)) },
                else => |len| .{ .large = nativeToBig(u64, len) },
            },
            .msg = @constCast(msg),
        };

        return message;
    }

    pub fn read(r: AnyReader, buffer: []align(@alignOf(Mask)) u8) !Message {
        var m: Message = undefined;

        if (try r.read(@as(*[2]u8, @ptrCast(&m.header))) != 2) return error.InvalidRead;
        if (m.header.final == false) return error.FragmentNotSupported;
        if (m.header.extlen == 127) {
            m.length = .{ .large = try r.readInt(u64, .big) };
        } else if (m.header.extlen == 126) {
            m.length = .{ .small = try r.readInt(u16, .big) };
        } else {
            m.length = .{ .tiny = m.header.extlen };
        }

        const length: usize = switch (m.length) {
            .tiny => |t| t,
            .small => |s| s,
            .large => |l| if (@sizeOf(usize) != @sizeOf(@TypeOf(l))) @intCast(l) else l,
        };

        if (length > buffer.len) return error.NoSpaceLeft;

        if (m.header.mask) {
            _ = try r.read(&m.mask);
        }
        const size = try r.read(buffer[0..length]);
        if (size != length) {
            std.debug.print("read error: {} vs {}\n", .{ size, length });
            std.debug.print("read error: {} \n", .{m.header});
            return error.InvalidRead;
        }

        const umask: u32 = @as(*u32, @ptrCast(&m.mask)).*;
        applyMask(umask, buffer[0..size]);
        m.msg = buffer[0..size];
        return m;
    }

    pub const Mask = usize;
    pub fn applyMask(mask: u32, buffer: []align(@alignOf(Mask)) u8) void {
        const block_mask: Mask = switch (@sizeOf(Mask)) {
            4 => mask,
            8 => mask | @as(Mask, mask) << 32,
            else => @compileError("mask not implemented for this arch size"),
        };
        const block_buffer: []u8 align(@alignOf(Mask)) =
            buffer[0 .. (buffer.len / @sizeOf(Mask)) * @sizeOf(Mask)];
        const block_msg: []Mask = @alignCast(@ptrCast(block_buffer));
        for (block_msg) |*blk| blk.* ^= block_mask;

        const remainder = buffer[block_buffer.len..];
        const rmask: [*]const u8 = @ptrCast(&mask);
        for (remainder, 0..) |*msg, i| msg.* ^= rmask[i % 4];
    }

    test applyMask {
        var vector: [56]u8 align(@alignOf(Mask)) = [_]u8{
            0x0b, 0x0a, 0x2e, 0xc1, 0x63, 0x06, 0x31, 0xcd,
            0x3a, 0x00, 0x22, 0xca, 0x31, 0x0a, 0x77, 0x9f,
            0x26, 0x0e, 0x33, 0x84, 0x2d, 0x08, 0x77, 0x99,
            0x2b, 0x06, 0x24, 0xc1, 0x63, 0x26, 0x77, 0x85,
            0x2c, 0x1f, 0x32, 0xcd, 0x3a, 0x00, 0x22, 0xcd,
            0x2b, 0x0e, 0x21, 0x88, 0x63, 0x0e, 0x77, 0x8a,
            0x2c, 0x00, 0x33, 0xcd, 0x27, 0x0e, 0x2e, 0xcc,
        };
        const mask: u32 = 3981930307;
        const expected = "Hey, if you're reading this, I hope you have a good day!";
        applyMask(mask, &vector);
        try std.testing.expectEqualStrings(expected, &vector);
    }

    pub fn toVec(m: *const Message) [3]std.posix.iovec_const {
        return .{
            .{ .base = @ptrCast(&m.header), .len = 2 },
            switch (m.length) {
                .tiny => .{ .base = @ptrCast(&m.length), .len = 0 },
                .small => .{ .base = @ptrCast(&m.length.small), .len = 2 },
                .large => .{ .base = @ptrCast(&m.length.large), .len = 8 },
            },
            .{ .base = m.msg.ptr, .len = m.msg.len },
        };
    }
};

test Message {
    {
        const msg = Message.init("Hi, Mom!", .text);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 8 }, &@as([2]u8, @bitCast(msg.header)));
    }
    {
        const msg = Message.init("Hi, Mom!" ** 15, .text);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 120 }, &@as([2]u8, @bitCast(msg.header)));
    }
    {
        const msg = Message.init("Hi, Mom!" ** 16, .text);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 0x7E }, &@as([2]u8, @bitCast(msg.header)));
    }
    {
        const text: [0xffff + 1]u8 = undefined;
        const msg = Message.init(&text, .text);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 0x7F }, &@as([2]u8, @bitCast(msg.header)));
    }
}

const Opcode = enum(u4) {
    continuation = 0,
    text = 1,
    binary = 2,
    connection_close = 8,
    ping = 9,
    pong = 10,
    _,
};

const std = @import("std");
const builtin = @import("builtin");
const endian = builtin.target.cpu.arch.endian();
const Frame = @import("frame.zig");
const Hash = std.crypto.hash.Sha1;
const base64 = std.base64.standard.Encoder;
const nativeToBig = std.mem.nativeToBig;
const AnyReader = std.io.AnyReader;
