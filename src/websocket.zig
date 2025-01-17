frame: *Frame,

const Websocket = @This();

pub fn accept(frame: *Frame) !Websocket {
    frame.status = .switching_protocols;
    frame.content_type = null;

    const key = if (frame.request.headers.getCustom("Sec-WebSocket-Key")) |key|
        key.value_list.value
    else
        return error.InvalidWebsocketRequest;

    var sha = Hash.init(.{});
    sha.update(key);
    sha.update("258EAFA5-E914-47DA-95CA-C5AB0DC85B11");
    var digest: [Hash.digest_length]u8 = undefined;
    sha.final(&digest);
    var base64_digest: [28]u8 = undefined;
    _ = base64.encode(&base64_digest, &digest);

    try frame.headersAdd("Upgrade", "websocket");
    try frame.headersAdd("Connection", "Upgrade");
    try frame.headersAdd("Sec-WebSocket-Accept", base64_digest[0..]);
    try frame.sendHeaders();
    try frame.sendRawSlice("\r\n");

    return Websocket{ .frame = frame };
}

pub fn send(ws: Websocket, msg: []const u8) !void {
    _ = switch (ws.frame.downstream) {
        .zwsgi, .http => |stream| try stream.writev(&[2]std.posix.iovec_const{
            .{ .base = (&[2]u8{ 0b10000000 | 0x01, @intCast(msg.len & 0x7f) }).ptr, .len = 2 },
            .{ .base = msg.ptr, .len = msg.len },
        }),
        else => {},
    };
}

const std = @import("std");
const Frame = @import("frame.zig");
const Hash = std.crypto.hash.Sha1;
const base64 = std.base64.standard.Encoder;
