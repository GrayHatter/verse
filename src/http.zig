//! Verse HTTP server
pub const HTTP = @This();

const MAX_HEADER_SIZE = 1 <<| 13;

alloc: Allocator,
listen_addr: std.net.Address,
router: Router,
max_request_size: usize = 0xffff,
request_buffer: [0xffff]u8 = undefined,
running: bool = true,
alive: bool = false,

pub const Options = struct {
    host: []const u8 = "127.0.0.1",
    port: u16 = 8080,
};

pub fn init(a: Allocator, opts: Options, router: Router) !HTTP {
    return .{
        .alloc = a,
        .listen_addr = try std.net.Address.parseIp(opts.host, opts.port),
        .router = router,
    };
}

pub fn serve(http: *HTTP) !void {
    var srv = try http.listen_addr.listen(.{ .reuse_address = true });
    defer srv.deinit();

    log.info("HTTP Server listening on port: {any}", .{http.listen_addr.getPort()});
    http.alive = true;
    while (http.running) {
        try http.once(&srv);
    }
}

pub fn once(http: *HTTP, srv: *net.Server) !void {
    var arena = std.heap.ArenaAllocator.init(http.alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var conn = try srv.accept();
    defer conn.stream.close();

    log.info("HTTP connection from {}", .{conn.address});
    var hsrv = std.http.Server.init(conn, &http.request_buffer);

    var hreq = try hsrv.receiveHead();
    const reqdata = try requestData(a, &hreq);
    const req = try Request.initHttp(a, &hreq, reqdata);

    var verse = try Verse.init(a, &req);

    const callable = http.router.routerfn(&verse, http.router.routefn);
    http.router.builderfn(&verse, callable);
}

fn requestData(a: Allocator, req: *std.http.Server.Request) !Request.Data {
    var itr_headers = req.iterateHeaders();
    while (itr_headers.next()) |header| {
        log.debug("http header => {s} -> {s}", .{ header.name, header.value });
        log.debug("{}", .{header});
    }
    var post_data: ?RequestData.PostData = null;

    if (req.head.content_length) |h_len| {
        if (h_len > 0) {
            const h_type = req.head.content_type orelse "text/plain";
            var reader = try req.reader();
            post_data = try RequestData.readBody(a, &reader, h_len, h_type);
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
    var server = try init(a, .{ .port = 9345 }, .{ .routefn = Router.testingRouter });
    var thread = try std.Thread.spawn(.{}, threadFn, .{&server});

    var client = std.http.Client{ .allocator = a };
    defer client.deinit();
    while (!server.alive) {}

    var list = std.ArrayList(u8).init(a);
    defer list.clearAndFree();
    server.running = false;
    const fetch = try client.fetch(.{
        .response_storage = .{ .dynamic = &list },
        .location = .{ .url = "http://localhost:9345/" },
        .method = .GET,
    });
    try std.testing.expectEqual(.ok, fetch.status);

    thread.join();
}

const Verse = @import("verse.zig");
const Router = @import("router.zig");
const Request = @import("request.zig");
const RequestData = @import("request_data.zig");

const std = @import("std");
const net = std.net;
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.Verse);
const Server = std.http.Server;
