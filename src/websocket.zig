frame: *Frame,

const Websocket = @This();

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
