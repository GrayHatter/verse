const std = @import("std");
const Allocator = std.mem.Allocator;

const Verse = @import("verse.zig");
const Router = @import("router.zig");

pub const Server = @This();

pub const zWSGI = @import("zwsgi.zig");
pub const Http = @import("http.zig");

alloc: Allocator,
router: Router,
interface: Interface,

pub const RunMode = enum {
    zwsgi,
    http,
    other,
};

pub const Interface = union(RunMode) {
    zwsgi: zWSGI,
    http: Http,
    other: void,
};

pub const Options = union(RunMode) {
    zwsgi: zWSGI.Options,
    http: Http.Options,
    other: void,
};

pub fn init(a: Allocator, opts: Options, router: Router) !Server {
    return .{
        .alloc = a,
        .router = router,
        .interface = switch (opts) {
            .zwsgi => .{ .zwsgi = zWSGI.init(a, opts.zwsgi, router) },
            .http => .{ .http = try Http.init(a, opts.http, router) },
            .other => unreachable,
        },
    };
}

pub fn serve(srv: *Server) !void {
    switch (srv.interface) {
        .zwsgi => |*zw| try zw.serve(),
        .http => |*ht| try ht.serve(),
        else => {},
    }
}
