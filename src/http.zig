const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.Verse);
const Server = std.http.Server;

const Verse = @import("verse.zig");
const Router = @import("router.zig");
const Request = @import("request.zig");
const RequestData = @import("request_data.zig");

const MAX_HEADER_SIZE = 1 <<| 13;

pub const HTTP = @This();

alloc: Allocator,
listen_addr: std.net.Address,
router: Router,
max_request_size: usize = 0xffff,

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

    log.warn("HTTP Server listening on port: {any}", .{http.listen_addr.getPort()});

    const request_buffer: []u8 = try http.alloc.alloc(u8, http.max_request_size);
    defer http.alloc.free(request_buffer);

    while (true) {
        var conn = try srv.accept();
        defer conn.stream.close();
        log.info("HTTP connection from {}", .{conn.address});
        var hsrv = std.http.Server.init(conn, request_buffer);
        var arena = std.heap.ArenaAllocator.init(http.alloc);
        defer arena.deinit();
        const a = arena.allocator();

        var hreq = try hsrv.receiveHead();
        var req = try Request.initHttp(a, &hreq);

        var verse = try buildVerse(a, &req);

        const callable = http.router.routerfn(&verse, http.router.routefn);
        http.router.builderfn(&verse, callable);
    }
    unreachable;
}

fn buildVerse(a: Allocator, req: *Request) !Verse {
    var itr_headers = req.raw.http.iterateHeaders();
    while (itr_headers.next()) |header| {
        log.debug("http header => {s} -> {s}", .{ header.name, header.value });
        log.debug("{}", .{header});
    }
    log.debug("http target -> {s}", .{req.uri});
    var post_data: ?RequestData.PostData = null;
    var reqdata: RequestData = undefined;

    if (req.raw.http.head.content_length) |h_len| {
        if (h_len > 0) {
            const h_type = req.raw.http.head.content_type orelse "text/plain";
            var reader = try req.raw.http.reader();
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
    if (std.mem.indexOf(u8, req.raw.http.head.target, "/")) |i| {
        query_data = try RequestData.readQuery(a, req.raw.http.head.target[i..]);
    }
    reqdata = RequestData{
        .post = post_data,
        .query = query_data,
    };

    return Verse.init(a, req, reqdata);
}
