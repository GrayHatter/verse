//! Verse HTTP server
alloc: Allocator,
router: Router,
auth: Auth.Provider,
srv_address: net.IpAddress,

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
        .srv_address = try net.IpAddress.parse(opts.host, opts.port),
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
    var future_buf: [20]OnceFuture = undefined;
    var future_list: ArrayList(OnceFuture) = .initBuffer(&future_buf);

    var threaded: std.Io.Threaded = .init(http.alloc);
    defer threaded.deinit();
    const io = threaded.io();

    var srv = try http.srv_address.listen(io, .{ .reuse_address = true });
    defer srv.deinit(io);

    log.info("HTTP Server listening at http://{f}", .{http.srv_address});
    http.alive = true;
    while (http.running) {
        var stream: Stream = try srv.accept(io);
        if (http.threads) |_| {
            try future_list.appendBounded(try io.concurrent(once, .{ http, &stream, io }));
        } else {
            try future_list.appendBounded(io.async(once, .{ http, &stream, io }));
        }
    }
    while (future_list.pop()) |future_| {
        var future = future_;
        _ = try future.await(io);
    }
    log.info("Normal HTTPD shutdown", .{});
}

const OnceFuture = std.Io.Future(@typeInfo(@TypeOf(once)).@"fn".return_type.?);

pub fn once(http: *HTTP, stream: *Stream, io: Io) !void {
    var timer = try std.time.Timer.start();
    const now = try std.Io.Clock.now(.real, io);

    defer stream.close(io);
    log.info("HTTP connection from {f}", .{stream.socket.address});

    var arena = std.heap.ArenaAllocator.init(http.alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const r_b: []u8 = try a.alloc(u8, 0x10000);
    const w_b: []u8 = try a.alloc(u8, 0x40000);
    var reader = stream.reader(io, r_b);
    var writer = stream.writer(io, w_b);
    var hsrv = std.http.Server.init(&reader.interface, &writer.interface);

    var hreq = try hsrv.receiveHead();
    const reqdata = try requestData(a, &hreq);
    const req = try Request.initHttp(a, &hreq, stream, reqdata, now);

    const ifc: *Server.Interface = @fieldParentPtr("http", http);
    const srvr: *Server = @alignCast(@fieldParentPtr("interface", ifc));

    var frame: Frame = try .init(a, io, srvr, &req, .{
        .gateway = .{ .http = &hsrv },
        .reader = &reader.interface,
        .writer = &writer.interface,
    }, http.auth);

    errdefer comptime unreachable;

    const callable = http.router.fallback(&frame, http.router.route);
    http.router.builder(&frame, callable);

    if (writer.err) |err| {
        std.debug.print("stream writer error {}\n", .{err});
    }

    writer.interface.flush() catch unreachable; // TODO

    const lap = timer.lap();
    if (srvr.stats) |*stats| {
        stats.log(.{
            .addr = req.remote_addr,
            .code = frame.status orelse .internal_server_error,
            .page_size = 0,
            .time = req.now.toSeconds(),
            .rss = arena.queryCapacity(),
            .ua = req.user_agent,
            .uri = req.uri,
            .us = lap / 1000,
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
            var r_b: [0x100000]u8 = undefined;
            const reader = req.readerExpectNone(&r_b);
            post_data = try RequestData.readPost(a, reader, hlen, h_type);
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

    var client = std.http.Client{ .allocator = a, .io = std.testing.io };
    defer client.deinit();
    while (!server.interface.http.alive) {}

    server.interface.http.running = false;
    const fetch = try client.fetch(.{
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
const net = std.Io.net;
const Stream = net.Stream;
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const log = std.log.scoped(.Verse);
const HttpServer = std.http.Server;
const Io = std.Io;
