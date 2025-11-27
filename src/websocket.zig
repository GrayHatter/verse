frame: *Frame,

const Websocket = @This();

pub const Error = WriteError || MemError || ReadError;

pub const MemError = error{
    OutOfMemory,
    NoSpaceLeft,
};

pub const WriteError = error{
    WriteFailed,
} || MemError;

pub const ReadError = error{
    ReadFailed,
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
    try f.sendHeaders(.close);
}

pub fn send(ws: Websocket, msg: []const u8) WriteError!void {
    const m = Message.init(msg, .text);
    try m.write(ws.frame.downstream.writer);
    try ws.frame.downstream.writer.flush();
}

pub fn recieve(ws: *Websocket, buffer: []align(8) u8) Error!Message {
    return Message.read(ws.frame.downstream.reader, buffer) catch |err| {
        std.debug.print("reader failed! {}\n", .{err});
        return error.ReadFailed;
    };
}

pub const Message = struct {
    header: Header,
    length: Length,
    mask: [4]u8 align(4) = undefined,
    msg: []u8,

    pub const Length = union(enum) {
        tiny: u7,
        small: u16,
        large: u64,

        pub fn len(l: Length) usize {
            return switch (l) {
                inline else => |e| e,
            };
        }
    };

    pub const Header = packed struct(u16) {
        extlen: u7,
        mask: bool = false,
        opcode: Opcode,
        reserved: u3 = 0,
        final: bool = true,
    };

    test Header {
        {
            const h: Header = .{
                .opcode = .continuation,
                .reserved = 0,
                .final = false,
                .extlen = std.math.maxInt(u7),
                .mask = true,
            };
            const bits: u16 = 0b0000_0000_1111_1111;
            const t: Header = @bitCast(bits);
            try std.testing.expectEqualDeep(t, h);
        }
        {
            const h: Header = .{
                .opcode = .continuation,
                .reserved = 0,
                .final = false,
                .extlen = std.math.maxInt(u7),
                .mask = true,
            };
            const bytes: [2]u8 = .{ 0b0000_0000, 0b1111_1111 };
            var r: Reader = .fixed(&bytes);
            const t = r.takeStruct(Header, .big);
            try std.testing.expectEqualDeep(t, h);
        }
    }

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

    pub const Mask = usize;

    pub fn read(r: *Reader, buffer: []align(@alignOf(Mask)) u8) !Message {
        try r.fill(2);
        if (r.end < 2) return error.InvalidRead;
        const header: Message.Header = try r.takeStruct(Message.Header, endian);
        if (header.final == false) return error.FragmentNotSupported;
        const length: Length = if (header.extlen == 127)
            .{ .large = try r.takeInt(u64, .big) }
        else if (header.extlen == 126)
            .{ .small = try r.takeInt(u16, .big) }
        else
            .{ .tiny = header.extlen };

        if (length.len() > buffer.len) return error.NoSpaceLeft;
        try r.fill(4 + length.len());
        const mask: [4]u8 align(4) = if (header.mask) (try r.takeArray(4)).* else @splat(0);
        if (r.bufferedLen() < length.len()) {
            std.debug.print("read error: {} vs {}\n", .{ r.bufferedLen(), length });
            std.debug.print("read error: {} \n", .{header});
            return error.InvalidRead;
        }

        const umask: u32 = @as(*const u32, @ptrCast(&mask)).*;
        applyMask(umask, r.buffered()[0..length.len()], buffer);
        r.toss(length.len());
        return .{
            .header = header,
            .length = length,
            .mask = mask,
            .msg = buffer[0..length.len()],
        };
    }

    pub fn applyMask(mask: u32, src: []const u8, buffer: []align(@alignOf(Mask)) u8) void {
        const block_mask: Mask = switch (@sizeOf(Mask)) {
            4 => mask,
            8 => mask | @as(Mask, mask) << 32,
            else => @compileError("mask not implemented for this arch size"),
        };
        @memcpy(buffer[0..src.len], src);
        const block_buffer: []u8 align(@alignOf(Mask)) = buffer[0 .. (buffer.len / @sizeOf(Mask)) * @sizeOf(Mask)];
        const block_msg: []Mask = @ptrCast(@alignCast(block_buffer));
        for (block_msg) |*blk| blk.* ^= block_mask;

        const remainder = buffer[block_buffer.len..];
        const rmask: [*]const u8 = @ptrCast(&mask);
        for (remainder, 0..) |*msg, i| msg.* ^= rmask[i % 4];
    }

    test applyMask {
        var dest: [56]u8 align(@alignOf(Mask)) = undefined;

        // alignment is explicit here to verify reader alignment can missmatch
        var source: [56]u8 align(1) = [_]u8{
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
        applyMask(mask, &source, &dest);
        try std.testing.expectEqualStrings(expected, &dest);
    }

    pub fn write(m: *const Message, w: *Writer) !void {
        try w.writeAll(@ptrCast(&m.header));
        switch (m.length) {
            .tiny => {},
            .small => try w.writeAll(@ptrCast(&m.length.small)),
            .large => try w.writeAll(@ptrCast(&m.length.large)),
        }
        try w.writeAll(m.msg);
    }
};

test Message {
    {
        const msg = Message.init("Hi, Mom!", .text);
        var bytes: [2]u8 = undefined;
        var w: Writer = .fixed(&bytes);
        try w.writeStruct(msg.header, .big);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 8 }, &bytes);
    }
    {
        const msg = Message.init("Hi, Mom!" ** 15, .text);
        var bytes: [2]u8 = undefined;
        var w: Writer = .fixed(&bytes);
        try w.writeStruct(msg.header, .big);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 120 }, &bytes);
    }
    {
        const msg = Message.init("Hi, Mom!" ** 16, .text);
        var bytes: [2]u8 = undefined;
        var w: Writer = .fixed(&bytes);
        try w.writeStruct(msg.header, .big);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 0x7E }, &bytes);
    }
    {
        const text: [0xffff + 1]u8 = undefined;
        const msg = Message.init(&text, .text);
        var bytes: [2]u8 = undefined;
        var w: Writer = .fixed(&bytes);
        try w.writeStruct(msg.header, .big);
        try std.testing.expectEqualSlices(u8, &[2]u8{ 0x81, 0x7F }, &bytes);
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
const Io = std.Io;
const Reader = Io.Reader;
const Writer = Io.Writer;
const endian = builtin.target.cpu.arch.endian();
const Frame = @import("frame.zig");
const Hash = std.crypto.hash.Sha1;
const base64 = std.base64.standard.Encoder;
const nativeToBig = std.mem.nativeToBig;
