pub const SmokeTestOptions = struct {
    soft_errors: []const Router.Error,
    recurse: bool,
    retry_with_fake_user: bool,

    const default_soft_errors = &[_]Router.Error{
        // By default, the soft errors are DataMissing, DataInvalid [because
        // smokeTest is unable to generate the default or expected data],
        // and NotFound [for the same reason, smokeTest is unlikely to be
        // able to generate the required routing information]
        error.DataInvalid,
        error.DataMissing,
        error.NotFound,
    };

    pub const default: SmokeTestOptions = .{
        .recurse = true,
        .soft_errors = default_soft_errors,
        .retry_with_fake_user = false,
    };

    pub const with_fake_user: SmokeTestOptions = .{
        .recurse = true,
        .soft_errors = default_soft_errors,
        .retry_with_fake_user = true,
    };
};

pub fn smokeTest(
    a: Allocator,
    io: std.Io,
    comptime routes: []const Router.Match,
    comptime opts: SmokeTestOptions,
    comptime root_name: []const u8,
) !void {
    inline for (routes) |route| {
        const name = root_name ++ "/" ++ route.name;
        const E = @typeInfo(Request.Methods).@"enum";
        inline for (E.field_values) |value| {
            if (comptime !Request.Methods.readOnly(@fromBackingInt(@intCast(value)))) continue;
            if (comptime route.methods.supports(@fromBackingInt(@intCast(value)))) {
                switch (route.target) {
                    .build => |func| {
                        var fc: FrameResponse = try .init(a, io);
                        try fc.prepare();
                        defer fc.raze(a);
                        func(&fc.frame) catch |err| {
                            for (opts.soft_errors) |soft| {
                                if (err == soft) break;
                            } else {
                                if (opts.retry_with_fake_user and
                                    (err == error.Unauthenticated or err == error.Unauthorized))
                                {
                                    var testing_auth = Auth.Testing.init();

                                    fc.frame.user = testing_auth.getValidUser();
                                    func(&fc.frame) catch |err2| {
                                        for (opts.soft_errors) |soft| {
                                            if (err2 == soft) break;
                                        } else {
                                            log.err(
                                                \\
                                                \\Smoke test error for endpoint '{s}':
                                                \\Match {}
                                                \\Error1 {}
                                                \\Error2 {}
                                                \\Retry with valid user failed. {}
                                            ,
                                                .{ name, func, err, err2, fc.frame.user.? },
                                            );

                                            return err2;
                                        }
                                    };
                                } else {
                                    log.err(
                                        "Smoke test error for endpoint '{s}':\n    Match {}",
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

test smokeTest {
    try smokeTest(
        std.testing.allocator,
        std.testing.io,
        &.{},
        .{
            .soft_errors = &.{},
            .recurse = true,
            .retry_with_fake_user = true,
        },
        "",
    );
}

pub fn fuzzTest(trgt: Router.Target) !void {
    const Context = struct {
        target: *const Router.Target,

        fn testOne(context: @This(), smth: *std.testing.Smith) !void {
            var buffer: [8164]u8 = undefined;
            const len = smth.slice(&buffer);
            const input = buffer[0..len];
            var fc = try FrameResponse.initRequest(.{ .query_data = input }, std.testing.allocator, std.testing.io);
            defer fc.raze(std.testing.allocator);

            try context.target.build(&fc.frame);
        }
    };
    try std.testing.fuzz(Context{ .target = &trgt }, Context.testOne, .{});
}

pub fn mkHeaders() Headers {
    return .{ .known = .{}, .extra = .{} };
}

pub const RequestOptions = struct {
    uri: []const u8 = "/",
    query_data: []const u8 = "",
};

pub fn request(a: Allocator, opt: RequestOptions) *Request {
    const self = a.create(Request) catch @panic("OOM");
    self.* = .{
        .accept = .any,
        .authorization = null,
        .cookie_jar = .init(a),
        .data = .{
            .post = null,
            .query = Request.Data.Query.init(opt.query_data, a) catch @panic("OOM, probably"),
        },
        .headers = mkHeaders(),
        .host = .init("localhost"),
        .method = .GET,
        .protocol = .default,
        .referer = null,
        .remote_addr = "127.0.0.1",
        .secure = true,
        .target = opt.uri,
        .user_agent = .init("Verse Internal Testing/0.0"),
        .now = std.Io.Clock.real.now(std.testing.io),
        .client_hints = .empty,
    };
    return self;
}

pub const FrameResponse = struct {
    arena: *std.heap.ArenaAllocator,
    frame: Frame,
    call_error: ?Router.Error = null,
    call_count: usize = 0,

    pub fn initRequest(ropt: RequestOptions, alloc: Allocator, io: std.Io) !FrameResponse {
        var arena = try alloc.create(std.heap.ArenaAllocator);
        arena.* = std.heap.ArenaAllocator.init(alloc);

        const a = arena.allocator();
        return .{
            .arena = arena,
            .frame = .{
                .alloc = a,
                .io = io,
                // todo lifetime
                .cookie_jar = .init(a),
                // todo lifetime
                .request = request(a, ropt),
                .uri = try .init("/"),
                .template_data = .empty,
                .response_headers = mkHeaders(),
                .server = &.{
                    .interface = undefined,
                    .stats = .disabled,
                    .auth = .disabled,
                    .options = .default,
                    .router = undefined,
                },
                .downstream = undefined,
            },
        };
    }

    pub fn init(alloc: Allocator, io: std.Io) !FrameResponse {
        return initRequest(.{}, alloc, io);
    }

    pub fn raze(fr: *const FrameResponse, a: std.mem.Allocator) void {
        fr.arena.deinit();
        a.destroy(fr.arena);
    }

    pub fn prepare(fr: *FrameResponse) !void {
        const a = fr.arena.allocator();
        fr.frame.downstream = try .init(a);
        fr.frame.downstream.buffer();
        fr.frame.downstream.phase = .{ .responding = .new };
    }

    /// WARN: Incomplete implementation
    pub fn routeTo(fr: *FrameResponse, match: Router.Match) error{ ExistingError, Unrouteable }!void {
        if (fr.call_error) |_| return error.ExistingError;
        fr.prepare() catch unreachable;

        // we don't call the router functions, so we assume the path has a prefix
        if (!std.mem.eql(u8, fr.frame.uri.path[1..], match.name)) return error.Unrouteable;
        return switch (match.target) {
            .build => |endpoint| {
                endpoint(&fr.frame) catch |err| {
                    fr.call_error = err;
                };
                fr.call_count += 1;
            },
            .route => unreachable,
            .simple => unreachable,
        };
    }

    pub fn call(fr: *FrameResponse, endpoint: Router.BuildFn) error{ExistingError}!void {
        if (fr.call_error) |_| return error.ExistingError;
        fr.prepare() catch unreachable;
        endpoint(&fr.frame) catch |err| {
            fr.call_error = err;
        };
        fr.call_count += 1;
    }

    pub fn splitContent(fr: *const FrameResponse) error{Incomplete}!struct { []const u8, []const u8 } {
        if (std.mem.find(u8, fr.frame.downstream.writer.buffer, "\r\n\r\n")) |bh| {
            return .{
                fr.frame.downstream.writer.buffer[0 .. bh + 2],
                fr.frame.downstream.writer.buffer[bh + 4 .. fr.frame.downstream.writer.end],
            };
        } else return error.Incomplete;
    }

    pub fn bodyContent(fr: *const FrameResponse) error{ NeverCalled, BufferEmpty, Incomplete }![]const u8 {
        if (fr.call_count == 0) return error.NeverCalled;
        _, const body = try fr.splitContent();
        return body;
    }

    pub const ResultError = error{NeverCalled} | Router.Error;

    pub fn result(fr: *const FrameResponse) ResultError!std.http.Status {
        if (fr.call_error) |err| return err;
        if (fr.call_count == 0) return error.NeverCalled;
        return fr.frame.status;
    }
};

test {
    _ = &std.testing.refAllDecls(@This());

    var fr_resp = try FrameResponse.init(std.testing.allocator, std.testing.io);
    defer fr_resp.raze(std.testing.allocator);

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
    try fr_resp.call(fof);

    const headers, const body = try fr_resp.splitContent();
    _ = body;

    try std.testing.expect(std.mem.startsWith(
        u8,
        headers,
        "HTTP/1.1 404 Not Found\r\nServer: verse/",
    ));

    try std.testing.expect(std.mem.endsWith(
        u8,
        headers,
        "\r\nContent-Type: text/html; charset=utf-8\r\n",
    ));
    _ = not_found_body;
    return error.SkipZigTest;
    //const frame_response_size = fc.frame.request.downstream.buffer.pos;
    //try std.testing.expect(720 <= frame_response_size); // Tagged release header
    //try std.testing.expect(765 >= frame_response_size); // Devel release header (plus extra)
    //try std.testing.expectEqualSlices(u8, not_found_body, fc.buffer[hidx + 2 .. frame_response_size]);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.verse_testing);
const Headers = @import("Headers.zig");
const Request = @import("Request.zig");
const Frame = @import("Frame.zig");
const Router = @import("Router.zig");
const Server = @import("Server.zig");
const Auth = @import("Auth.zig");
