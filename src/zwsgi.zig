//! Verse zwsgi server
//! Speaks the uwsgi protocol
alloc: Allocator,
router: Router,
options: Options,
auth: Auth.Provider,
threads: ?u16,

unix_file: []const u8,

const zWSGI = @This();

pub const Options = struct {
    file: []const u8 = "./zwsgi_file.sock",
    chmod: ?std.posix.mode_t = null,
    stats: bool = false,
};

pub fn init(a: Allocator, router: Router, opts: Options, sopts: Server.Options) zWSGI {
    return .{
        .alloc = a,
        .unix_file = opts.file,
        .router = router,
        .options = opts,
        .auth = sopts.auth,
        .threads = sopts.threads,
    };
}

var running: bool = true;

pub fn serve(z: *zWSGI) !void {
    var cwd = std.fs.cwd();
    if (cwd.access(z.unix_file, .{})) {
        log.warn("File {s} already exists, zwsgi can not start.", .{z.unix_file});
        return error.FileExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("Unexpected error during zwsgi startup {}", .{err});
            return err;
        },
    }

    defer cwd.deleteFile(z.unix_file) catch |err| {
        log.err(
            "Unable to delete file {s} during cleanup ({}this is unrecoverable)",
            .{ z.unix_file, err },
        );
        @panic("Cleanup failed");
    };

    signalListen(SIG.INT);

    if (z.options.chmod) |cmod| {
        var b: [2048:0]u8 = undefined;
        const path = try cwd.realpath(z.unix_file, b[0..]);
        const zpath = try z.alloc.dupeZ(u8, path);
        defer z.alloc.free(zpath);
        _ = std.os.linux.chmod(zpath, cmod);
    }
    log.warn("Unix server listening", .{});

    var future_buf: [20]OnceFuture = undefined;
    var future_list: ArrayList(OnceFuture) = .initBuffer(&future_buf);

    var threaded: std.Io.Threaded = .init(z.alloc);
    defer threaded.deinit();
    const io = threaded.io();

    const uaddr = try net.UnixAddress.init(z.unix_file);
    var server: net.Server = try uaddr.listen(io, .{});
    defer server.deinit(io);

    while (running) {
        var pollfds = [1]std.os.linux.pollfd{
            .{
                .fd = server.socket.handle,
                .events = std.math.maxInt(i16),
                .revents = 0,
            },
        };
        const ready = try std.posix.poll(&pollfds, 100);
        if (ready == 0) {
            while (future_list.pop()) |future_| {
                var future = future_;
                try future.await(io);
            }
            continue;
        }
        var stream = try server.accept(io);

        if (z.threads) |_| {
            try future_list.appendBounded(try io.concurrent(once, .{ z, &stream, io }));
        } else {
            try future_list.appendBounded(io.async(once, .{ z, &stream, io }));
        }
    }
    log.warn("closing, and cleaning up", .{});
}

const OnceFuture = std.Io.Future(@typeInfo(@TypeOf(once)).@"fn".return_type.?);

pub fn once(z: *const zWSGI, stream: *net.Stream, io: Io) !void {
    var timer = try std.time.Timer.start();
    const now = try std.Io.Clock.now(.real, io);

    defer stream.close(io);

    var arena = std.heap.ArenaAllocator.init(z.alloc);
    defer arena.deinit();
    const a = arena.allocator();

    const r_b: []u8 = try a.alloc(u8, 0x10000);
    const w_b: []u8 = try a.alloc(u8, 0x40000);
    var reader = stream.reader(io, r_b);
    var writer = stream.writer(io, w_b);

    var zreq = try zWSGIRequest.init(a, &reader.interface);
    const request_data = try requestData(a, &zreq, &reader.interface);
    const request = try Request.initZWSGI(a, &zreq, request_data, now);

    const srv_interface: *const Server.Interface = @fieldParentPtr("zwsgi", z);
    const srvr: *Server = @alignCast(@constCast(@fieldParentPtr("interface", srv_interface)));

    var frame: Frame = try .init(a, io, srvr, &request, .{
        .gateway = .{ .zwsgi = &zreq },
        .reader = &reader.interface,
        .writer = &writer.interface,
    }, z.auth);

    defer {
        const lap = timer.lap() / 1000;
        log.err(
            "zWSGI: [{d:.3}] {s} - {s}:{} {s} -- \"{s}\"",
            .{
                @as(f64, @floatFromInt(lap)) / 1000.0,
                request.remote_addr,
                @tagName(request.method),
                @intFromEnum(frame.status orelse .ok),
                zreq.known.get(.REQUEST_URI) orelse "[ERROR: URI EMPTY]",
                if (request.user_agent) |ua| ua.string else "EMPTY",
            },
        );
        if (srvr.stats) |*stats| {
            stats.log(.{
                .addr = request.remote_addr,
                .code = frame.status orelse .internal_server_error,
                .page_size = 0,
                .time = request.now.toSeconds(),
                .rss = arena.queryCapacity(),
                .ua = request.user_agent,
                .uri = request.uri,
                .us = lap,
            });
        }
    }

    const routed_endpoint = z.router.fallback(&frame, z.router.route);
    z.router.builder(&frame, routed_endpoint);
    writer.interface.flush() catch unreachable;
}

export fn sig_cb(sig: std.posix.SIG, _: *const siginfo_t, _: ?*anyopaque) callconv(.c) void {
    switch (sig) {
        std.posix.SIG.INT => {
            running = false;
            log.err("SIGINT received", .{});
        },
        // should be unreachable
        else => @panic("Unexpected, or unimplemented signal recieved"),
    }
}

fn signalListen(signal: std.posix.SIG) void {
    std.posix.sigaction(signal, &.{
        .handler = .{ .sigaction = sig_cb },
        .mask = std.posix.sigemptyset(),
        .flags = SA.SIGINFO,
    }, null);
}

pub const zWSGIParam = enum {
    // These are minimum expected values
    REMOTE_ADDR,
    REMOTE_PORT,
    REQUEST_URI,
    REQUEST_PATH,
    REQUEST_METHOD,
    REQUEST_SCHEME,
    QUERY_STRING,
    CONTENT_TYPE,
    CONTENT_LENGTH,
    SERVER_NAME,
    SERVER_PORT,
    SERVER_PROTOCOL,
    HTTPS,
    MTLS_ENABLED,
    MTLS_CERT,
    MTLS_FINGERPRINT,
    // These are seen often enough to be worth including here
    HTTP_HOST,
    HTTP_ACCEPT,
    HTTP_USER_AGENT,
    HTTP_ACCEPT_ENCODING,
    HTTP_AUTHORIZATION,
    HTTP_COOKIE,
    HTTP_REFERER,
    HTTP_FROM,

    pub const fields = @typeInfo(zWSGIParam).@"enum".fields;

    pub fn fromStr(str: []const u8) ?zWSGIParam {
        inline for (fields) |f| {
            if (eqlIgnoreCase(f.name, str)) return @enumFromInt(f.value);
        } else return null;
    }
};

pub const zWSGIRequest = struct {
    header: uProtoHeader = uProtoHeader{},
    known: std.EnumArray(zWSGIParam, ?[]const u8) = .initFill(null),
    vars: std.ArrayListUnmanaged(uWSGIVar) = .{},

    pub fn init(a: Allocator, r: *Reader) !zWSGIRequest {
        const uwsgi_header = try uProtoHeader.init(r);

        try r.fill(uwsgi_header.size);

        var zr: zWSGIRequest = .{ .header = uwsgi_header };
        try zr.readVars(a, r);
        return zr;
    }

    fn readVars(zr: *zWSGIRequest, a: Allocator, r: *Reader) !void {
        try zr.vars.ensureTotalCapacity(a, 10);
        while (r.bufferedLen() > 0) {
            const key_len = try r.takeInt(u16, sys_endian);
            const key_str = try r.take(key_len);
            const expected = zWSGIParam.fromStr(key_str);

            const val_len = try r.takeInt(u16, sys_endian);
            if (val_len > 0) {
                const val_str = try r.take(val_len);

                if (expected) |k| {
                    if (zr.known.get(k)) |old| {
                        log.err(
                            "Duplicate key found (dropping) {s} :: original {s} | new {s}",
                            .{ @tagName(k), old, val_str },
                        );
                        continue;
                    }
                    zr.known.set(k, val_str);
                } else {
                    try zr.vars.append(a, uWSGIVar{
                        .key = key_str,
                        .val = val_str,
                    });
                }
            }
        }
    }
};

const uProtoHeader = packed struct {
    mod1: u8 = 0,
    size: u16 = 0,
    mod2: u8 = 0,

    pub fn init(r: *Reader) !uProtoHeader {
        return r.takeStruct(uProtoHeader, sys_endian);
    }
};

const uWSGIVar = struct {
    key: []const u8,
    val: []const u8,

    pub fn read(_: []u8) uWSGIVar {
        return uWSGIVar{ .key = "", .val = "" };
    }

    pub fn format(self: uWSGIVar, out: anytype) !void {
        try std.fmt.format(out, "\"{s}\" = \"{s}\"", .{
            self.key,
            if (self.val.len > 0) self.val else "[Empty]",
        });
    }
};

fn requestData(a: Allocator, zreq: *zWSGIRequest, r: *Reader) !Request.Data {
    var post_data: ?Request.Data.PostData = null;

    if (zreq.known.get(.CONTENT_LENGTH)) |h_len| {
        const h_type = zreq.known.get(.CONTENT_TYPE) orelse "text/plain";

        const post_size = try std.fmt.parseInt(usize, h_len, 10);
        if (post_size > 0) {
            post_data = try Request.Data.readPost(a, r, post_size, h_type);
            log.debug(
                "post data \"{s}\" {{{any}}}",
                .{ post_data.?.rawpost, post_data.?.rawpost },
            );

            for (post_data.?.items) |itm| {
                log.debug("{}", .{itm});
            }
        }
    }

    return .{
        .post = post_data,
        .query = try Request.Data.readQuery(a, zreq.known.get(.QUERY_STRING) orelse ""),
    };
}

test init {
    const a = std.testing.allocator;

    const router = Router.Routes(&.{});

    _ = init(a, router, .{}, .{});
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;
const Io = std.Io;
const Reader = std.Io.Reader;
const log = std.log.scoped(.Verse);
const net = std.Io.net;
const siginfo_t = std.posix.siginfo_t;
const SIG = std.posix.SIG;
const SA = std.posix.SA;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
const zbuiltin = @import("builtin");
const sys_endian = zbuiltin.target.cpu.arch.endian();

const Server = @import("server.zig");
const Frame = @import("frame.zig");
const Request = @import("request.zig");
const Router = @import("router.zig");
const Auth = @import("auth.zig");
