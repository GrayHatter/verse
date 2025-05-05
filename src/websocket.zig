frame: *Frame,

const Websocket = @This();

pub fn accept(frame: *Frame) !Websocket {
    const key = if (frame.request.headers.getCustom("Sec-WebSocket-Key")) |key|
        key.list[0]
    else
        return error.InvalidWebsocketRequest;

    try respond(frame, key);
    return Websocket{ .frame = frame };
}

fn respond(f: *Frame, key: []const u8) !void {
    f.status = .switching_protocols;
    f.content_type = null;

    var sha = Hash.init(.{});
    sha.update(key);
    sha.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [Hash.digest_length]u8 = undefined;
    sha.final(&digest);
    var encoded: [28]u8 = undefined;
    _ = base64.encode(&encoded, &digest);
    try f.headers.addCustom("Upgrade", "websocket");
    try f.headers.addCustom("Connection", "Upgrade");
    try f.headers.addCustom("Sec-WebSocket-Accept", encoded[0..]);
    try f.sendHeaders();
    try f.sendRawSlice("\r\n");
}

pub fn send(ws: Websocket, msg: []const u8) !void {
    const m = Message.init(msg, .text);
    const vec = m.toVec();

    _ = switch (ws.frame.downstream) {
        .zwsgi, .http => |stream| try stream.writev(vec[0..3]),
        else => {},
    };
}

pub fn recieve(ws: *Websocket, buffer: []align(8) u8) !Message {
    var reader = switch (ws.frame.downstream) {
        .zwsgi, .http => |stream| stream.reader(),
        else => unreachable,
    };
    var any = reader.any();
    return try Message.read(&any, buffer);
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

    pub fn read(r: *AnyReader, buffer: []align(8) u8) !Message {
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
            inline else => |l| l,
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

    pub fn applyMask(mask: u32, buffer: []align(8) u8) void {
        const block_mask: usize = mask | @as(usize, mask) << 32;
        const block_buffer: []u8 align(8) = buffer[0 .. (buffer.len / 8) * 8];
        // TODO fix when zig supports this cast
        var block_msg: []usize = undefined;
        block_msg.ptr = @alignCast(@ptrCast(block_buffer.ptr));
        block_msg.len = block_buffer.len / 8;
        for (block_msg) |*blk| {
            blk.* ^= block_mask;
        }

        const remainder = buffer[block_buffer.len..];
        const rmask: [*]const u8 = @ptrCast(&mask);
        for (remainder, 0..) |*msg, i| msg.* ^= rmask[i % 4];
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

pub const Opcode = enum(u4) {
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
