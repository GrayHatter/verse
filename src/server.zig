interface: Interface,
stats: ?Stats,

const Server = @This();

pub const zWSGI = @import("zwsgi.zig");
pub const Http = @import("http.zig");

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
    auth: Auth.Provider = .invalid,
    threads: ?u16 = null,
    stats: ?stats_.Options = null,
    logging: Logging = .stdout,
};

pub fn init(a: Allocator, router: Router, opts: Options) !Server {
    if (opts.stats) |so| {
        stats_.options = so;
    }

    // TODO FIXME
    const now: std.Io.Timestamp = .{ .nanoseconds = 1762107590 * std.time.ns_per_s };

    return .{
        .interface = switch (opts.mode) {
            .zwsgi => |z| .{ .zwsgi = zWSGI.init(a, router, z, opts) },
            .http => |h| .{ .http = try Http.init(a, router, h, opts) },
            .other => unreachable,
        },
        .stats = if (opts.stats) |_| .init(opts.threads != null, now) else null,
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

    const srv = try init(std.testing.allocator, Router.Routes(&.{}), .{});
    _ = srv;
}

const std = @import("std");
const Allocator = std.mem.Allocator;

const Auth = @import("auth.zig");
const Router = @import("router.zig");
const stats_ = @import("stats.zig");
const Logging = @import("Logging.zig");
const Stats = stats_.Stats;
