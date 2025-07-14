pub const SmokeTestOptions = struct {
    soft_errors: []const Router.Error,
    recurse: bool,
    retry_with_fake_user: bool,

    pub const default: SmokeTestOptions = .{
        .recurse = true,
        .soft_errors = &[_]Router.Error{
            // By default, the soft errors are DataMissing, DataInvalid [because
            // smokeTest is unable to generate the default or expected data],
            // and Unrouteable [for the same reason, smokeTest is unlikely to be
            // able to generate the required routing information]
            error.DataInvalid,
            error.DataMissing,
            error.Unrouteable,
        },
        .retry_with_fake_user = false,
    };
};

pub fn smokeTest(
    a: Allocator,
    comptime routes: []const Router.Match,
    comptime opts: SmokeTestOptions,
    comptime root_name: []const u8,
) !void {
    inline for (routes) |route| {
        const name = root_name ++ "/" ++ route.name;
        inline for (@typeInfo(Request.Methods).@"enum".fields) |field| {
            if (comptime !Request.Methods.readOnly(@enumFromInt(field.value))) continue;
            if (comptime route.methods.supports(@enumFromInt(field.value))) {
                switch (route.target) {
                    .build => |func| {
                        var fc: FrameCtx = try .init(a);
                        defer fc.raze(a);
                        func(&fc.frame) catch |err| {
                            for (opts.soft_errors) |soft| {
                                if (err == soft) break;
                            } else {
                                if (opts.retry_with_fake_user and
                                    (err == error.Unauthenticated or err == error.Unauthorized))
                                {
                                    var provider = auth.TestingAuth.init();

                                    fc.frame.user = provider.getValidUser();
                                    func(&fc.frame) catch |err2| {
                                        for (opts.soft_errors) |soft| {
                                            if (err2 == soft) break;
                                        } else {
                                            std.debug.print(
                                                \\
                                                \\Smoke test error for endpoint '{s}':
                                                \\Match {}
                                                \\Error1 {}
                                                \\Error2 {}
                                                \\Retry with valid user failed. {}
                                                \\
                                            ,
                                                .{ name, func, err, err2, fc.frame.user.? },
                                            );

                                            return err2;
                                        }
                                    };
                                } else {
                                    std.debug.print(
                                        "Smoke test error for endpoint '{s}':\n    Match {}\n",
                                        .{ name, func },
                                    );
                                    return err;
                                }
                            }
                        };
                    },
                    .simple => |smp| {
                        if (!opts.recurse) continue;
                        try smokeTest(a, smp, opts, name);
                    },
                    else => {},
                }
            }
        }
    }
}

pub fn fuzzTest(trgt: Router.Target) !void {
    const Context = struct {
        target: *const Router.Target,

        fn testOne(context: @This(), input: []const u8) anyerror!void {
            var fc = try FrameCtx.initRequest(
                std.testing.allocator,
                .{ .query_data = input },
            );
            defer fc.raze(std.testing.allocator);

            try context.target.build(&fc.frame);
        }
    };
    try std.testing.fuzz(
        Context{ .target = &trgt },
        Context.testOne,
        .{},
    );
}

pub fn headers() Headers {
    return .{
        .known = .{},
        .extended = .{},
    };
}

const Buffer = std.io.FixedBufferStream([]u8);
const DEFAULT_SIZE = 0x1000000;

pub const RequestOptions = struct {
    uri: []const u8 = "/",
    query_data: []const u8 = "",
};

pub fn request(a: Allocator, buf: []u8, opt: RequestOptions) *Request {
    const fba = a.create(Buffer) catch @panic("OOM");
    fba.* = .{ .buffer = buf, .pos = 0 };

    const self = a.create(Request) catch @panic("OOM");
    self.* = .{
        .accept = "*/*",
        .authorization = null,
        .cookie_jar = .init(a),
        .data = .{
            .post = null,
            .query = Request.Data.QueryData.init(a, opt.query_data) catch unreachable,
        },
        .headers = headers(),
        .host = "localhost",
        .method = .GET,
        .protocol = .default,
        .downstream = .{ .buffer = fba },
        .referer = null,
        .remote_addr = "127.0.0.1",
        .secure = true,
        .uri = opt.uri,
        .user_agent = .init("Verse Internal Testing/0.0"),
    };
    return self;
}

pub const FrameCtx = struct {
    arena: *std.heap.ArenaAllocator,
    frame: Frame,
    buffer: []u8,

    pub fn initRequest(alloc: Allocator, ropt: RequestOptions) !FrameCtx {
        var arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);

        const a = arena.allocator();
        const buffer = try a.alloc(u8, DEFAULT_SIZE);
        return .{
            .arena = arena,
            .frame = .{
                .cookie_jar = .init(a),
                // todo lifetime
                .alloc = a,
                // todo lifetime
                .request = request(a, buffer, ropt),
                .uri = splitUri("/") catch unreachable,
                .auth_provider = .invalid,
                .response_data = .init(a),
                .headers = headers(),
                .server = &Server{
                    .interface = undefined,
                    .stats = null,
                },
            },
            .buffer = buffer,
        };
    }

    pub fn init(alloc: Allocator) !FrameCtx {
        return initRequest(alloc, .{});
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
        \\      html { color-scheme: light dark; min-height: 100%; }
        \\      body { width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }
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

    try std.testing.expectEqual(754, fc.frame.request.downstream.buffer.pos);
    try std.testing.expectEqualSlices(u8, not_found_body, fc.buffer[hidx + 2 .. fc.frame.request.downstream.buffer.pos]);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Headers = @import("headers.zig");
const Request = @import("request.zig");
const Frame = @import("frame.zig");
const Router = @import("router.zig");
const Server = @import("server.zig");
const auth = @import("auth.zig");
const splitUri = Router.splitUri;
