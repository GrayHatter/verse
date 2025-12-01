options: Options,
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
    io: ?Io = null,
    mode: RunMode,
    auth: Auth.Provider,
    stats: ?Stats.Options = null,
    threads: u16 = 1,
    logging: Logging = .stdout,

    pub const default: Options = .{
        .io = null,
        .mode = .{ .http = .localdevel },
        .auth = .disabled,
        .threads = 1,
        .stats = .disabled,
        .logging = .stdout,
    };
};

pub fn init(router: *const Router, opts: Options) !Server {
    return .{
        .options = opts,
        .interface = switch (opts.mode) {
            .zwsgi => |z| .{ .zwsgi = zWSGI.init(router, z, opts) },
            .http => |h| .{ .http = try Http.init(router, h, opts) },
            .other => .{ .other = {} },
        },
        .stats = null,
    };
}

pub fn serve(srv: *Server, gpa: Allocator) !void {
    system.installSignals();

    var threaded: std.Io.Threaded = .init(gpa);
    defer threaded.deinit();
    threaded.async_limit = Io.Limit.limited(@max(2, srv.options.threads));
    const io: Io = srv.options.io orelse threaded.io();

    const now = try std.Io.Clock.now(.real, io);
    if (srv.options.stats) |opt| {
        srv.stats = .init(opt, now);
    }

    switch (srv.interface) {
        .zwsgi => |*zw| try zw.serve(gpa, io),
        .http => |*ht| try ht.serve(gpa, io),
        .other => unreachable,
    }
}

test Server {
    std.testing.refAllDecls(@This());

    const srv = try init(&Router.Routes(&.{}), .default);
    _ = srv;
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const Auth = @import("auth.zig");
const Router = @import("router.zig");
const Stats = @import("stats.zig");
const Logging = @import("Logging.zig");
const system = @import("system.zig");
