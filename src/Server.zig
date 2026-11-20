auth: *Auth,
interface: Interface,
options: Options,
router: *const Router,
stats: Stats,
/// secret user pointer that can be referenced from within request handlers.
usrptr: ?*const anyopaque = null,
/// General Allocator, can be used by requests, but memory allocated via `gpa` is unmanaged
gpa: Allocator = undefined,

// Experimental API
seen: SeenMap,

const Server = @This();

pub const zWSGI = @import("zwsgi.zig");
pub const Http = @import("Http.zig");

pub const Interface = union(Name) {
    zwsgi: zWSGI,
    http: Http,
    other: void,

    pub const Name = enum {
        zwsgi,
        http,
        other,
    };
};

pub const Options = struct {
    io: Options.IoMode = .threaded,
    mode: RunMode,
    auth: ?*Auth = null,
    stats: Stats.Options = .disabled,
    threads: u16 = 1,
    logging: Logging = .stdout,

    pub const RunMode = union(Interface.Name) {
        zwsgi: zWSGI.Options,
        http: Http.Options,
        other: void,
    };

    pub const default: Options = .{
        .io = .threaded,
        .mode = .{ .http = .localdevel },
        .auth = null,
        .threads = 1,
        .stats = .disabled,
        .logging = .stdout,
    };

    pub const IoMode = union(enum) {
        io: std.Io,
        threaded,
        evented,
    };
};

pub fn init(router: *const Router, opts: Options) !Server {
    return .{
        .options = opts,
        .router = router,
        .interface = switch (opts.mode) {
            .zwsgi => |z| .{ .zwsgi = zWSGI.init(router, z) },
            .http => |h| .{ .http = try Http.init(router, h) },
            .other => .{ .other = {} },
        },
        .auth = opts.auth orelse .disabled,
        .stats = .disabled,
        .seen = .empty,
    };
}

pub fn serve(srv: *Server, gpa: Allocator) !void {
    srv.gpa = gpa;
    system.installSignals();

    var threaded: std.Io.Threaded = .init(gpa, .{ .environ = .empty });
    defer threaded.deinit();
    threaded.async_limit = Io.Limit.limited(@max(2, srv.options.threads));
    const io: Io = switch (srv.options.io) {
        .io => |io| io,
        .threaded => threaded.io(),
        .evented => unreachable,
    };

    var lines: []Stats.Line = &.{};
    defer gpa.free(lines);
    if (srv.options.stats.auth_mode != .stats_disabled) {
        const now = Io.Clock.real.now(io);
        lines = try gpa.alloc(Stats.Line, 256);
        srv.stats = .init(lines, now, srv.options.stats);
    }

    defer srv.seen.deinit(gpa);

    try srv.core(gpa, io);
}

const Future = Io.Future(@typeInfo(@TypeOf(Server.once)).@"fn".return_type.?);

pub fn core(srv: *Server, gpa: Allocator, io: Io) !void {
    log.info("starting core", .{});
    var future_buf: [20]Future = undefined;
    var future_list: ArrayList(Future) = .initBuffer(&future_buf);

    defer switch (srv.interface) {
        .zwsgi => |*z| z.raze(io),
        .http => |*h| h.raze(io),
        .other => unreachable,
    };

    var listener = try srv.listen(io);
    defer listener.deinit(io);

    var poller: Poller = .init();
    poller.pollfds[1] = .{ .fd = listener.socket.handle, .revents = 0, .events = std.math.maxInt(i16) };
    while (true) {
        const ready = poller.poll() catch |e| switch (e) {
            error.ExitSignal => {
                if (poller.signal(io)) |siginfo|
                    log.info("watched signal\n{any}", .{siginfo});
                break;
            },
            error.SystemResources => return error.SystemResources,
            error.Unexpected => return error.Unexpected,
            error.SignalInterrupt => return error.SignalInterrupt,
        };
        log.debug("poll {}", .{ready});
        if (ready > 0 and future_list.items.len < 20) {
            if (try poller.next()) |_| {
                log.debug("accept", .{});
                const stream = try listener.accept(io);
                try future_list.appendBounded(io.async(once, .{ srv, stream, gpa, io }));
                continue;
            }
        }

        while (future_list.pop()) |f| {
            var future = f;
            future.await(io) catch |err| log.err("await error {}", .{err});
        }
    }
    while (future_list.pop()) |f| {
        var future = f;
        _ = try future.await(io);
    }
    log.info("closing, and cleaning up", .{});
}

pub fn once(srv: *Server, stream: Io.net.Stream, gpa: Allocator, io: Io) !void {
    log.debug("setting up request", .{});
    defer stream.close(io);
    var timer: Io.Timestamp = Io.Clock.awake.now(io);
    const now = Io.Clock.real.now(io);

    var arena = std.heap.ArenaAllocator.init(gpa);
    defer arena.deinit();
    const a = arena.allocator();

    var ds: Frame.Downstream = try .init(a);
    switch (srv.interface) {
        .zwsgi => try ds.zwsgi(stream, a, io),
        .http => try ds.http(stream, io),
        .other => unreachable,
    }

    const request: Request = try switch (srv.interface) {
        .zwsgi => |z| z.initRequest(&ds.gateway.zwsgi, now, a),
        .http => |h| h.initRequest(&ds.gateway.http, now, stream.socket.address, a),
        .other => unreachable,
    };

    var frame: Frame = try .init(srv, ds, &request, a, io);

    const seen = try srv.seen.getOrPut(gpa, Seen.ipFromStr(request.remote_addr));
    if (!seen.found_existing) {
        seen.value_ptr.* = .{
            .first = now,
            .count = 0,
        };
    } else {
        seen.value_ptr.count += 1;
    }
    frame.seen = seen.value_ptr.*;

    defer {
        const lap: Io.Duration = timer.untilNow(io, .awake);
        srv.options.logging.req(.{
            .prefix = if (frame.downstream.gateway == .zwsgi) "zWSGI" else "HTTP",
            .response_time = @as(f64, @floatFromInt(lap.toNanoseconds())) / 1000_000.0,
            .address = request.remote_addr,
            .method = request.method,
            .status = frame.status orelse .ok,
            .uri = frame.uri,
            .user_agent = if (request.user_agent) |ua| ua.string else "EMPTY",
        });
        srv.stats.log(.fromFrame(&frame, &arena, lap.toNanoseconds()), io);
    }

    const routed_endpoint = srv.router.fallback(&frame, srv.router.route);
    srv.router.builder(&frame, routed_endpoint);
    frame.downstream.writer.flush() catch {};
}

fn listen(srv: *Server, io: Io) !Io.net.Server {
    return switch (srv.interface) {
        .zwsgi => |*z| try z.listen(io),
        .http => |*h| try h.listen(io),
        .other => unreachable,
    };
}

fn accept(srv: *Server, _: anytype) !void {
    switch (srv.interface) {
        .zwsgi => comptime unreachable,
        .http => comptime unreachable,
        .other => unreachable,
    }
}

const Poller = struct {
    pollfds: [2]pollfd = undefined,
    sigset: SigSet = system.defaultSigSet(),
    sigfd: Io.File = undefined,

    pub const PollError = error{
        SystemResources,
        Unexpected,
        SignalInterrupt,
        ExitSignal,
    };

    pub const pollfd = system.pollfd;
    pub const SigSet = std.posix.sigset_t;
    pub const default_timeout: std.posix.timespec = .{ .sec = 10, .nsec = 100 * ns_per_ms };

    pub fn init() Poller {
        var poller: Poller = undefined;

        poller.sigset = system.defaultSigSet();
        poller.sigfd = .{
            .handle = system.signalfd(
                -1,
                &poller.sigset,
                @bitCast(system.O{ .NONBLOCK = false }),
            ) catch @panic("fd failed"),
            .flags = .{ .nonblocking = false },
        };
        poller.pollfds[0] = .{ .fd = poller.sigfd.handle, .events = std.math.maxInt(i16), .revents = 0 };
        return poller;
    }

    pub fn poll(poller: *Poller) !usize {
        poller.resetFds();
        const ready = system.ppoll(&poller.pollfds, &default_timeout, &poller.sigset) catch |err| {
            switch (err) {
                error.SignalInterrupt => log.warn("signaled, cleaning up", .{}),
                else => return err,
            }
            return err;
        };
        if (poller.pollfds[0].revents != 0) return error.ExitSignal;
        return ready;
    }

    pub fn next(poller: *Poller) !?*pollfd {
        for (poller.pollfds[1..]) |*fd| {
            if (fd.revents != 0) {
                defer fd.revents = 0;
                return fd;
            }
        }
        return null;
    }

    pub fn signal(poller: *Poller, io: Io) ?system.signalfd_siginfo {
        if (poller.pollfds[0].revents == 0) return null;
        defer poller.pollfds[0].revents = 0;
        var r_b: [@sizeOf(system.signalfd_siginfo)]u8 = undefined;
        var r = poller.sigfd.reader(io, &r_b);
        const siginfo: system.signalfd_siginfo = r.interface.takeStruct(
            system.signalfd_siginfo,
            system.endian,
        ) catch unreachable;
        return siginfo;
    }

    pub fn resetFds(poller: *Poller) void {
        for (&poller.pollfds) |*fd| {
            fd.events = std.math.maxInt(i16);
            fd.revents = 0;
        }
    }
};

pub const Seen = struct {
    first: Io.Timestamp,
    count: usize,

    pub const zero: Seen = .{
        .first = .zero,
        .count = 0,
    };

    pub const IpAddr = u64;

    pub fn ipFromStr(str: []const u8) u64 {
        var ip: u64 = 0;
        var bytes: *align(8) [8]u8 = std.mem.asBytes(&ip);
        var idx: usize = 0;
        if (findScalarPos(u8, str, 0, '.')) |_| {
            var itr = std.mem.splitScalar(u8, str, '.');
            while (itr.next()) |addr| {
                bytes[idx] = std.fmt.parseInt(u8, addr, 10) catch 0;
                idx += 1;
                if (idx == 4) break;
            }
        } else if (findScalarPos(u8, str, idx, ':')) |_| {
            var itr = std.mem.splitScalar(u8, str, ':');
            while (itr.next()) |addr| {
                bytes[idx] = std.fmt.parseInt(u8, addr, 16) catch 0;
                idx += 1;
                if (idx == 8) break;
            }
        }
        return ip;
    }

    pub fn ipFromAddr(addr: std.Io.net.IpAddress) u64 {
        var ip: u64 = 0;
        var bytes: *align(8) [8]u8 = std.mem.asBytes(&ip);
        switch (addr) {
            .ip4 => |ip4| bytes[0..4].* = ip4.bytes[0..4].*,
            .ip6 => |ip6| bytes[0..8].* = ip6.bytes[0..8].*,
        }

        return ip;
    }
};

test Server {
    std.testing.refAllDecls(@This());

    const srv = try init(&Router.Routes(&.{}), .default);
    _ = srv;
}

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const findScalarPos = std.mem.findScalarPos;
const ArrayList = std.ArrayList;
const ns_per_ms = std.time.ns_per_ms;
const log = std.log.scoped(.verse);
const SeenMap = std.AutoHashMapUnmanaged(u64, Seen);

const Auth = @import("Auth.zig");
const Request = @import("Request.zig");
const Router = @import("Router.zig");
const Stats = @import("Stats.zig");
const Frame = @import("Frame.zig");
const Logging = @import("Logging.zig");
const system = @import("system.zig");
