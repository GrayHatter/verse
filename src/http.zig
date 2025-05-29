//! Verse HTTP server
alloc: Allocator,
router: Router,
auth: Auth.Provider,

listen_addr: std.net.Address,
running: bool = true,
alive: bool = false,
threads: ?struct {
    count: usize,
    pool: std.Thread.Pool,
} = null,

const HTTP = @This();

const MAX_HEADER_SIZE = 1 <<| 13;

pub const Options = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
};

pub fn init(a: Allocator, router: Router, opts: Options, sopts: Server.Options) !HTTP {
    return .{
        .alloc = a,
        .router = router,
        .auth = sopts.auth,
        .listen_addr = try std.net.Address.parseIp(opts.host, opts.port),
        .threads = if (sopts.threads) |tcount| brk: {
            var pool: std.Thread.Pool = undefined;
            try pool.init(.{ .allocator = a, .n_jobs = tcount });
            break :brk .{
                .count = tcount,
                .pool = pool,
            };
        } else null,
    };
}

pub fn serve(http: *HTTP) !void {
    var srv = try http.listen_addr.listen(.{ .reuse_address = true });
    defer srv.deinit();

    log.info("HTTP Server listening on port: {any}", .{http.listen_addr.getPort()});
    http.alive = true;
    while (http.running) {
        const conn = try srv.accept();
        if (http.threads) |*threads| {
            try threads.pool.spawn(onceThreaded, .{ http, conn });
        } else {
            try http.once(conn);
        }
    }
    log.info("Normal HTTPD shutdown", .{});
}

fn onceThreaded(http: *HTTP, acpt: net.Server.Connection) void {
    once(http, acpt) catch |err| switch (err) {
        error.HttpRequestTruncated => {
            log.err("HttpRequestTruncated in threaded mode", .{});
        },
        else => {
            log.err("Unexpected endpoint error {} in threaded mode", .{err});
            http.running = false;
        },
    };
}

pub fn once(http: *HTTP, sconn: net.Server.Connection) !void {
    var timer = try std.time.Timer.start();

    var conn = sconn;
    defer conn.stream.close();

    var request_buffer: [0xfffff]u8 = undefined;
    log.info("HTTP connection from {}", .{conn.address});
    var hsrv = std.http.Server.init(conn, &request_buffer);

    var arena = std.heap.ArenaAllocator.init(http.alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var hreq = try hsrv.receiveHead();
    const reqdata = try requestData(a, &hreq);
    const req = try Request.initHttp(a, &hreq, reqdata);

    const ifc: *Server.Interface = @fieldParentPtr("http", http);
    const srvr: *Server = @fieldParentPtr("interface", ifc);

    var frame: Frame = try .init(a, srvr, &req, http.auth);

    errdefer comptime unreachable;

    const callable = http.router.fallback(&frame, http.router.route);
    http.router.builder(&frame, callable);

    const lap = timer.lap();
    if (srvr.stats) |*stats| {
        stats.log(.{
            .addr = req.remote_addr,
            .uri = req.uri,
            .us = lap / 1000,
            .ua = req.user_agent,
        });
    }
}

fn requestData(a: Allocator, req: *std.http.Server.Request) !Request.Data {
    var itr_headers = req.iterateHeaders();
    while (itr_headers.next()) |header| {
        log.debug("http header => {s} -> {s}", .{ header.name, header.value });
    }
    var post_data: ?RequestData.PostData = null;

    if (req.head.content_length) |h_len| {
        if (h_len > std.math.maxInt(usize)) return error.ContentTooLarge;
        const hlen: usize = @intCast(h_len);
        if (hlen > 0) {
            const h_type = req.head.content_type orelse "text/plain";
            var reader = try req.reader();
            post_data = try RequestData.readPost(a, &reader, hlen, h_type);
            log.debug(
                "post data \"{s}\" {{{any}}}",
                .{ post_data.?.rawpost, post_data.?.rawpost },
            );

            for (post_data.?.items) |itm| {
                log.debug("{}", .{itm});
            }
        }
    }

    var query_data: RequestData.QueryData = undefined;
    if (std.mem.indexOf(u8, req.head.target, "/")) |i| {
        query_data = try RequestData.readQuery(a, req.head.target[i..]);
    }

    return RequestData{
        .post = post_data,
        .query = query_data,
    };
}

fn threadFn(server: *HTTP) void {
    server.serve() catch |err| {
        log.err("Server failed! {}", .{err});
    };
}

test HTTP {
    const a = std.testing.allocator;

    var server: Server = .{
        .interface = .{ .http = try init(a, Router.TestingRouter, .{ .port = 9345 }, .{}) },
        .stats = null,
    };

    var thread = try std.Thread.spawn(.{}, threadFn, .{&server.interface.http});

    var client = std.http.Client{ .allocator = a };
    defer client.deinit();
    while (!server.interface.http.alive) {}

    var list = std.ArrayList(u8).init(a);
    defer list.clearAndFree();
    server.interface.http.running = false;
    const fetch = try client.fetch(.{
        .response_storage = .{ .dynamic = &list },
        .location = .{ .url = "http://localhost:9345/" },
        .method = .GET,
    });
    try std.testing.expectEqual(.ok, fetch.status);

    thread.join();
}

const Auth = @import("auth.zig");
const Server = @import("server.zig");
const Frame = @import("frame.zig");
const Router = @import("router.zig");
const Request = @import("request.zig");
const RequestData = @import("request-data.zig");

const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.Verse);
const HttpServer = std.http.Server;
