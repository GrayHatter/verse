//! Verse HTTP server
router: *const Router,
srv_address: net.IpAddress,

const HTTP = @This();

const MAX_HEADER_SIZE = 1 <<| 13;

pub const Options = struct {
    host: []const u8,
    port: u16,

    pub fn localPort(comptime port: u16) Options {
        return .{
            .host = "127.0.0.1",
            .port = port,
        };
    }

    pub const public: Options = .{
        .host = "0.0.0.0",
        .port = 80,
    };

    pub const localhost: Options = .{
        .host = "127.0.0.1",
        .port = 80,
    };

    pub const localdevel: Options = .{
        .host = "127.0.0.1",
        .port = 8080,
    };
};

pub fn init(router: *const Router, opts: Options) !HTTP {
    return .{
        .router = router,
        .srv_address = try net.IpAddress.parse(opts.host, opts.port),
    };
}

pub fn raze(http: *HTTP, io: Io) void {
    _ = http;
    _ = io;
}

pub fn listen(http: *HTTP, io: Io) !Io.net.Server {
    return try http.srv_address.listen(io, .{});
}

pub fn initRequest(_: *const HTTP, ds: *Frame.Downstream, now: Io.Timestamp, addr: IpAddress, a: Allocator) !Request {
    try ds.http();
    var hreq: std.http.Server.Request = try ds.gateway.http.receiveHead();
    log.debug("http request uri: {s}", .{hreq.head.target});

    const reqdata = try requestData(a, &hreq);
    const request: Request = try .initHttp(&hreq, reqdata, now, addr, a);
    return request;
}

pub fn serve(http: *HTTP, gpa: Allocator, io: Io) !void {
    var future_buf: [20]OnceFuture = undefined;
    var future_list: ArrayList(OnceFuture) = .initBuffer(&future_buf);

    var srv = try http.listen(io);
    defer srv.deinit(io);

    var pollfds: [2]pollfd = undefined;

    const sigset = system.defaultSigSet();
    const sigfd: Io.File = .{ .handle = system.signalfd(
        -1,
        &sigset,
        @bitCast(system.O{ .NONBLOCK = false }),
    ) catch @panic("fd failed"), .flags = .{ .nonblocking = false } };

    log.info("HTTP Server listening at http://{f}", .{http.srv_address});
    while (true) {
        pollfds = .{
            .{ .fd = sigfd.handle, .events = std.math.maxInt(i16), .revents = 0 },
            .{ .fd = srv.socket.handle, .events = std.math.maxInt(i16), .revents = 0 },
        };
        const ready = system.ppoll(
            &pollfds,
            &.{ .sec = 10, .nsec = 100 * ns_per_ms },
            &sigset,
        ) catch |err| switch (err) {
            error.SignalInterrupt => {
                log.warn("signaled, cleaning up", .{});
                break;
            },
            else => return err,
        };
        if (ready > 0 and future_list.items.len < 20) {
            if (pollfds[0].revents != 0) {
                log.err("signal", .{});
                var r_b: [@sizeOf(system.signalfd_siginfo)]u8 = undefined;
                var r = sigfd.reader(io, &r_b);
                const siginfo: system.signalfd_siginfo = r.interface.takeStruct(
                    system.signalfd_siginfo,
                    system.endian,
                ) catch unreachable;
                log.debug("siginfo {}\n\n\n", .{siginfo});
                break;
            }
            if (pollfds[1].revents != 0) {
                const stream = try srv.accept(io);
                try future_list.appendBounded(io.async(once, .{ http, stream, gpa, io }));
                continue;
            }
        }

        while (future_list.pop()) |future_| {
            var future = future_;
            try future.await(io);
        }
    }
    while (future_list.pop()) |future_| {
        var future = future_;
        _ = try future.await(io);
    }
    log.info("Normal HTTPD shutdown", .{});
}

const OnceFuture = std.Io.Future(@typeInfo(@TypeOf(once)).@"fn".return_type.?);

pub fn once(http: *HTTP, stream: Stream, gpa: Allocator, io: Io) !void {
    defer stream.close(io);
    var timer: Io.Timestamp = Io.Clock.awake.now(io);
    const now: Io.Timestamp = Io.Clock.real.now(io);

    log.info("HTTP connection from {f}", .{stream.socket.address});

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    const ifc: *Server.Interface = @fieldParentPtr("http", http);
    const srvr: *Server = @alignCast(@fieldParentPtr("interface", ifc));

    var ds: Frame.Downstream = try .init(stream, a, io);
    var request: Request = try http.initRequest(&ds, now, stream.socket.address, a);
    var frame: Frame = try .init(srvr, ds, &request, a, io);

    errdefer comptime unreachable;

    const callable = http.router.fallback(&frame, http.router.route);
    http.router.builder(&frame, callable);

    if (frame.downstream.writer.err) |err| {
        std.debug.print("stream writer error {}\n", .{err});
    }

    frame.downstream.writer.interface.flush() catch unreachable; // TODO

    const lap = timer.untilNow(io, .awake);
    srvr.stats.log(.{
        .addr = request.remote_addr,
        .code = frame.status orelse .internal_server_error,
        .page_size = 0,
        .time = request.now.toSeconds(),
        .rss = arena.queryCapacity(),
        .ua = request.user_agent,
        .uri = frame.uri.path,
        .us = @intCast(@divTrunc(lap.toNanoseconds(), 1000)),
    }, io);
}

fn requestData(a: Allocator, req: *std.http.Server.Request) !Request.Data {
    var itr_headers = req.iterateHeaders();
    while (itr_headers.next()) |header| {
        log.debug("http header => {s} -> {s}", .{ header.name, header.value });
    }
    var post_data: ?Request.Data.Post = null;

    if (req.head.content_length) |h_len| {
        if (h_len > std.math.maxInt(usize)) return error.ContentTooLarge;
        const hlen: usize = @intCast(h_len);
        if (hlen > 0) {
            const h_type = req.head.content_type orelse "text/plain";
            var r_b: [0x100000]u8 = undefined;
            const reader = req.readerExpectNone(&r_b);
            post_data = try .init(a, hlen, reader, try .fromStr(h_type));
            log.debug(
                "post data \"{s}\" {{{any}}}",
                .{ post_data.?.buffer, post_data.?.buffer },
            );

            for (post_data.?.items) |itm| {
                log.debug("{}", .{itm});
            }
        }
    }

    var query_data: Request.Data.Query = undefined;
    if (std.mem.indexOf(u8, req.head.target, "/")) |i| {
        query_data = try Request.Data.readQuery(a, req.head.target[i..]);
    }

    return Request.Data{
        .post = post_data,
        .query = query_data,
    };
}

fn threadFn(server: *HTTP, gpa: Allocator, io: Io) void {
    var srv = server.srv_address.listen(io, .{ .reuse_address = true }) catch unreachable;
    defer srv.deinit(io);
    const stream = srv.accept(io) catch unreachable;

    once(server, stream, gpa, io) catch |err| {
        log.err("Server failed! {}", .{err});
    };
}

test HTTP {
    const a = std.testing.allocator;
    const io = std.testing.io;

    var server: Server = .{
        .interface = .{
            .http = try init(&Router.TestingRouter, .localPort(9345)),
        },
        .stats = .disabled,
        .options = .default,
        .auth = .disabled,
        .router = &Router.TestingRouter,
    };

    var thread = try std.Thread.spawn(.{}, threadFn, .{ &server.interface.http, a, io });

    var client = std.http.Client{ .allocator = a, .io = std.testing.io };
    defer client.deinit();
    try io.sleep(.fromMilliseconds(100), .real);

    const fetch = try client.fetch(.{
        .location = .{ .url = "http://localhost:9345/" },
        .method = .GET,
    });
    try std.testing.expectEqual(.ok, fetch.status);

    thread.join();
}

const Server = @import("Server.zig");
const Frame = @import("Frame.zig");
const Router = @import("Router.zig");
const Request = @import("Request.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const net = Io.net;
const Stream = net.Stream;
const IpAddress = net.IpAddress;
const log = std.log.scoped(.Verse);
const ns_per_ms = std.time.ns_per_ms;

const system = @import("system.zig");
const pollfd = system.pollfd;
