pub fn headers() Headers {
    return .{
        .known = .{},
        .extended = .{},
    };
}

const Buffer = std.io.FixedBufferStream([]u8);
const DEFAULT_SIZE = 0x1000000;

pub fn request(a: std.mem.Allocator, buf: []u8) *Request {
    const fba = a.create(Buffer) catch @panic("OOM");
    fba.* = .{ .buffer = buf, .pos = 0 };

    const self = a.create(Request) catch @panic("OOM");
    self.* = .{
        .accept = "*/*",
        .authorization = null,
        .cookie_jar = .init(a),
        .data = .{
            .post = null,
            .query = Request.Data.QueryData.init(a, "") catch unreachable,
        },
        .headers = headers(),
        .host = "localhost",
        .method = .GET,
        .protocol = .default,
        .downstream = .{ .buffer = fba },
        .referer = null,
        .remote_addr = "127.0.0.1",
        .secure = true,
        .uri = "/",
        .user_agent = .init("Verse Internal Testing/0.0"),
    };
    return self;
}

pub const FrameCtx = struct {
    arena: *std.heap.ArenaAllocator,
    frame: Frame,
    buffer: []u8,

    pub fn init(alloc: std.mem.Allocator) !FrameCtx {
        var arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);

        const a = arena.allocator();
        const buffer = try a.alloc(u8, DEFAULT_SIZE / 0x1000);
        return .{
            .arena = arena,
            .frame = .{
                .cookie_jar = .init(a),
                // todo lifetime
                .alloc = a,
                // todo lifetime
                .request = request(a, buffer),
                .uri = splitUri("/") catch unreachable,
                .auth_provider = .invalid,
                .response_data = .init(a),
                .headers = headers(),
            },
            .buffer = buffer,
        };
    }

    pub fn raze(fc: FrameCtx, a: std.mem.Allocator) void {
        fc.arena.deinit();
        a.destroy(fc.arena);
    }
};

test {
    var fc = try FrameCtx.init(std.testing.allocator);
    defer fc.raze(std.testing.allocator);

    const fof = Router.defaultResponse(.not_found);

    const not_found_body =
        \\<!DOCTYPE html>
        \\<html>
        \\  <head>
        \\    <title>404: Not Found</title>
        \\    <style>
        \\      html {
        \\        color-scheme: light dark;
        \\        min-height: 100%;
        \\      }
        \\      body {
        \\        width: 35em;
        \\        margin: 0 auto;
        \\        font-family: Tahoma, Verdana, Arial, sans-serif;
        \\      }
        \\    </style>
        \\  </head>
        \\  <body>
        \\    <h1>404: Wrong Castle</h1>
        \\    <p>The page you're looking for is in another castle :(<br/>
        \\      Please try again repeatedly... surely it'll work this time!</p>
        \\    <p>If you are the system administrator you should already know why <br/>
        \\      it's broken what are you still reading this for?!</p>
        \\    <p><em>Faithfully yours, Geoff from Accounting.</em></p>
        \\  </body>
        \\</html>
        \\
        \\
    ;
    try fof(&fc.frame);

    const hidx = std.mem.lastIndexOf(u8, fc.buffer, "\r\n") orelse return error.InvalidHtml;

    try std.testing.expect(std.mem.startsWith(
        u8,
        fc.buffer,
        "HTTP/1.1 404 Not Found\r\nServer: verse/",
    ));

    try std.testing.expect(std.mem.endsWith(
        u8,
        fc.buffer[0 .. hidx + 2],
        "\r\nContent-Type: text/html; charset=utf-8\r\n\r\n",
    ));

    try std.testing.expect(800 <= fc.frame.request.downstream.buffer.pos);
    try std.testing.expectEqualSlices(u8, not_found_body, fc.buffer[hidx + 2 .. fc.frame.request.downstream.buffer.pos]);
}

const std = @import("std");
const Headers = @import("headers.zig");
const Request = @import("request.zig");
const Frame = @import("frame.zig");
const Router = @import("router.zig");
const splitUri = Router.splitUri;
