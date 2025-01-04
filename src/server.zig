alloc: Allocator,
router: Router,
interface: Interface,

const Server = @This();

pub const RunModes = enum {
    zwsgi,
    http,
    other,
};

pub const RunMode = union(RunModes) {
    zwsgi: zWSGI.Options,
    http: Http.Options,
    other: void,
};

pub const Interface = union(RunModes) {
    zwsgi: zWSGI,
    http: Http,
    other: void,
};

pub const Options = struct {
    mode: RunMode = .{ .http = .{} },
    router: Router,
    auth: Auth.Provider = Auth.InvalidAuth.provider(),
};

pub fn init(a: Allocator, opts: Options) !Server {
    return .{
        .alloc = a,
        .router = opts.router,
        .interface = switch (opts.mode) {
            .zwsgi => |z| .{ .zwsgi = zWSGI.init(a, z, opts.router) },
            .http => |h| .{ .http = try Http.init(a, h, opts.router) },
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

test Server {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const Auth = @import("auth.zig");
const Router = @import("routing/router.zig");
pub const zWSGI = @import("zwsgi.zig");
pub const Http = @import("http.zig");
