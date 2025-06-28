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

    const uaddr = try std.net.Address.initUnix(z.unix_file);
    var server = try uaddr.listen(.{});
    defer server.deinit();

    if (z.options.chmod) |cmod| {
        var b: [2048:0]u8 = undefined;
        const path = try cwd.realpath(z.unix_file, b[0..]);
        const zpath = try z.alloc.dupeZ(u8, path);
        defer z.alloc.free(zpath);
        _ = std.os.linux.chmod(zpath, cmod);
    }
    log.warn("Unix server listening", .{});

    var thr_pool: std.Thread.Pool = undefined;
    if (z.threads) |thread_count| {
        try thr_pool.init(.{ .allocator = z.alloc, .n_jobs = thread_count });
    }
    defer thr_pool.deinit();

    while (running) {
        var pollfds = [1]std.os.linux.pollfd{
            .{ .fd = server.stream.handle, .events = std.math.maxInt(i16), .revents = 0 },
        };
        const ready = try std.posix.poll(&pollfds, 100);
        if (ready == 0) continue;
        const acpt = try server.accept();

        if (z.threads) |_| {
            try thr_pool.spawn(onceThreaded, .{ z, acpt });
        } else {
            try once(z, acpt);
        }
    }
    log.warn("closing, and cleaning up", .{});
}

pub fn once(z: *const zWSGI, acpt: net.Server.Connection) !void {
    var timer = try std.time.Timer.start();

    var conn = acpt;
    defer acpt.stream.close();

    var arena = std.heap.ArenaAllocator.init(z.alloc);
    defer arena.deinit();
    const a = arena.allocator();

    var zreq = try zWSGIRequest.init(a, &conn);
    const request_data = try requestData(a, &zreq);
    const request = try Request.initZWSGI(a, &zreq, request_data);

    const ifc: *const Server.Interface = @fieldParentPtr("zwsgi", z);
    const srvr: *Server = @constCast(@fieldParentPtr("interface", ifc));

    var frame: Frame = try .init(a, srvr, &request, z.auth);

    defer {
        const lap = timer.lap() / 1000;
        log.err(
            "zWSGI: [{d:.3}] {s} - {s}:{} {s} -- \"{s}\"",
            .{
                @as(f64, @floatFromInt(lap)) / 1000.0,
                request.remote_addr,
                request.method,
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
                .rss = arena.queryCapacity(),
                .ua = request.user_agent,
                .uri = request.uri,
                .us = lap,
            });
        }
    }

    const routed_endpoint = z.router.fallback(&frame, z.router.route);
    z.router.builder(&frame, routed_endpoint);
}

fn onceThreaded(z: *const zWSGI, acpt: net.Server.Connection) void {
    once(z, acpt) catch |err| {
        log.err("Unexpected endpoint error {} in threaded mode", .{err});
        running = false;
    };
}

export fn sig_cb(sig: c_int, _: *const siginfo_t, _: ?*const anyopaque) callconv(.C) void {
    switch (sig) {
        std.posix.SIG.INT => {
            running = false;
            log.err("SIGINT received", .{});
        },
        // should be unreachable
        else => @panic("Unexpected, or unimplemented signal recieved"),
    }
}

fn signalListen(signal: u6) void {
    std.posix.sigaction(signal, &std.posix.Sigaction{
        .handler = .{ .sigaction = sig_cb },
        .mask = std.posix.empty_sigset,
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
    conn: *net.Server.Connection,
    header: uProtoHeader = uProtoHeader{},
    buffer: []u8,
    known: std.EnumArray(zWSGIParam, ?[]const u8) = .initFill(null),
    vars: std.ArrayListUnmanaged(uWSGIVar) = .{},

    pub fn init(a: Allocator, c: *net.Server.Connection) !zWSGIRequest {
        const uwsgi_header = try uProtoHeader.init(c);

        const buf: []u8 = try a.alloc(u8, uwsgi_header.size);
        const read = try c.stream.read(buf);
        if (read != uwsgi_header.size) {
            std.log.err("unexpected read size {} {}", .{ read, uwsgi_header.size });
            @panic("unreachable");
        }

        var zr: zWSGIRequest = .{
            .conn = c,
            .header = uwsgi_header,
            .buffer = buf,
        };
        try zr.readVars(a);
        return zr;
    }

    fn readVars(zr: *zWSGIRequest, a: Allocator) !void {
        var buf = zr.buffer;
        try zr.vars.ensureTotalCapacity(a, 10);
        while (buf.len > 0) {
            const key_len = readU16(buf[0..2]);
            buf = buf[2..];
            const key_str = buf[0..key_len];
            buf = buf[key_len..];
            const expected = zWSGIParam.fromStr(key_str);

            const val_len = readU16(buf[0..2]);
            buf = buf[2..];
            if (val_len > 0) {
                const val_str = buf[0..val_len];
                buf = buf[val_len..];

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

fn readU16(b: *const [2]u8) u16 {
    std.debug.assert(b.len >= 2);
    return @as(u16, @bitCast(b[0..2].*));
}

test "readu16" {
    const buffer = [2]u8{ 238, 1 };
    const size: u16 = 494;
    try std.testing.expectEqual(size, readU16(&buffer));
}

const uProtoHeader = packed struct {
    mod1: u8 = 0,
    size: u16 = 0,
    mod2: u8 = 0,

    pub fn init(c: *net.Server.Connection) !uProtoHeader {
        var self: uProtoHeader = .{};
        var ptr: [*]u8 = @ptrCast(&self);
        if (try c.stream.read(ptr[0..4]) != 4) {
            return error.InvalidRead;
        }
        return self;
    }
};

const uWSGIVar = struct {
    key: []const u8,
    val: []const u8,

    pub fn read(_: []u8) uWSGIVar {
        return uWSGIVar{ .key = "", .val = "" };
    }

    pub fn format(self: uWSGIVar, comptime _: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
        try std.fmt.format(out, "\"{s}\" = \"{s}\"", .{
            self.key,
            if (self.val.len > 0) self.val else "[Empty]",
        });
    }
};

fn find(list: []uWSGIVar, search: []const u8) ?[]const u8 {
    for (list) |each| {
        if (std.mem.eql(u8, each.key, search)) return each.val;
    }
    return null;
}

fn findOr(list: []uWSGIVar, search: []const u8) []const u8 {
    return find(list, search) orelse "[missing]";
}

fn requestData(a: Allocator, zreq: *zWSGIRequest) !Request.Data {
    var post_data: ?Request.Data.PostData = null;

    if (find(zreq.vars.items, "HTTP_CONTENT_LENGTH")) |h_len| {
        const h_type = findOr(zreq.vars.items, "HTTP_CONTENT_TYPE");

        const post_size = try std.fmt.parseInt(usize, h_len, 10);
        if (post_size > 0) {
            var reader = zreq.conn.stream.reader().any();
            post_data = try Request.Data.readPost(a, &reader, post_size, h_type);
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
const log = std.log.scoped(.Verse);
const net = std.net;
const siginfo_t = std.posix.siginfo_t;
const SIG = std.posix.SIG;
const SA = std.posix.SA;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;

const Server = @import("server.zig");
const Frame = @import("frame.zig");
const Request = @import("request.zig");
const Router = @import("router.zig");
const Auth = @import("auth.zig");
