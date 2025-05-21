pub fn headers() Headers {
    return .{
        .known = undefined,
        .extended = undefined,
    };
}

const Buffer = std.io.FixedBufferStream([]u8);
const DEFAULT_SIZE = 0x1000000;

pub fn request(a: std.mem.Allocator, buf: []u8) Request {
    return .{
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
        .downstream = .{ .buffer = .{ .buffer = buf, .pos = 0 } },
        .referer = null,
        .remote_addr = "127.0.0.1",
        .secure = true,
        .uri = "/",
        .user_agent = .init("Verse Internal Testing/0.0"),
    };
}

pub const FrameCtx = struct {
    arena: std.heap.ArenaAllocator,
    frame: Frame,
    buffer: []u8,

    pub fn init() !FrameCtx {
        var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
        defer arena.deinit();
        const buffer = try arena.allocator().alloc(u8, DEFAULT_SIZE);
        const req = request(arena.allocator(), buffer);
        return .{
            .arena = arena,
            .frame = .{
                .cookie_jar = .init(arena.allocator()),
                // todo lifetime
                .alloc = arena.allocator(),
                // todo lifetime
                .request = &req,
                .uri = splitUri("/") catch unreachable,
                .auth_provider = undefined,
                .response_data = .init(arena.allocator()),
                .headers = headers(),
            },
            .buffer = buffer,
        };
    }

    pub fn raze(fc: FrameCtx) void {
        fc.arena.deinit();
    }
};

test {
    _ = try FrameCtx.init();
}

const std = @import("std");
const Headers = @import("headers.zig");
const Request = @import("request.zig");
const Frame = @import("frame.zig");
const Router = @import("router.zig");
const splitUri = Router.splitUri;
