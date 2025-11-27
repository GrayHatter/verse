//! Verse zwsgi server
//! Speaks the uwsgi protocol
router: *const Router,
options: Options,
auth: Auth.Provider,

unix_file_name: []const u8,

const zWSGI = @This();

pub const Options = struct {
    file: []const u8,
    chmod: ?std.posix.mode_t,
    stats: bool,

    pub const default: Options = .{
        .file = "./zwsgi_file.sock",
        .chmod = null,
        .stats = false,
    };
};

pub fn init(router: *const Router, opts: Options, sopts: Server.Options) zWSGI {
    return .{
        .unix_file_name = opts.file,
        .router = router,
        .options = opts,
        .auth = sopts.auth,
    };
}

var running: bool = true;

pub fn serve(z: *zWSGI, gpa: Allocator, io: Io) !void {
    var cwd = Io.Dir.cwd();
    if (cwd.access(io, z.unix_file_name, .{})) {
        log.warn("File {s} already exists, zwsgi can not start.", .{z.unix_file_name});
        return error.FileExists;
    } else |err| switch (err) {
        error.FileNotFound => {},
        else => {
            log.err("Unexpected error during zwsgi startup {}", .{err});
            return err;
        },
    }

    defer std.fs.Dir.adaptFromNewApi(cwd).deleteFile(z.unix_file_name) catch |err| switch (err) {
        error.FileNotFound => {}, // Not optimal, but not fatal.
        else => {
            log.err(
                "Unable to delete file {s} during cleanup ({}this is unrecoverable)",
                .{ z.unix_file_name, err },
            );
            @panic("Cleanup failed");
        },
    };

    var future_buf: [20]OnceFuture = undefined;
    var future_list: ArrayList(OnceFuture) = .initBuffer(&future_buf);

    const uaddr = try net.UnixAddress.init(z.unix_file_name);
    var server: net.Server = try uaddr.listen(io, .{});
    log.warn("Unix server listening", .{});
    defer server.deinit(io);
    var pollfds: [2]pollfd = undefined;

    if (z.options.chmod) |cmod| {
        var b: [2048:0]u8 = undefined;
        const path: []u8 = try std.fs.Dir.adaptFromNewApi(cwd).realpath(z.unix_file_name, b[0..]);
        b[path.len] = 0;
        _ = std.os.linux.chmod(b[0..path.len :0], cmod);
    }

    const sigset = system.defaultSigSet();
    const sigfd: Io.File = .{ .handle = posix.signalfd(-1, &sigset, @bitCast(linux.O{ .NONBLOCK = false })) catch @panic("fd failed") };

    while (true) {
        pollfds = .{
            .{ .fd = sigfd.handle, .events = std.math.maxInt(i16), .revents = 0 },
            .{ .fd = server.socket.handle, .events = std.math.maxInt(i16), .revents = 0 },
        };
        const ready = posix.ppoll(
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
                var r_b: [@sizeOf(linux.signalfd_siginfo)]u8 = undefined;
                var r = sigfd.reader(io, &r_b);
                const siginfo: linux.signalfd_siginfo = r.interface.takeStruct(linux.signalfd_siginfo, system.endian) catch unreachable;
                std.debug.print("siginfo {}\n\n\n", .{siginfo});
                break;
            }
            if (pollfds[1].revents != 0) {
                var stream = try server.accept(io);
                try future_list.appendBounded(io.async(once, .{ z, &stream, gpa, io }));
                continue;
            }
        }

        while (future_list.pop()) |future_| {
            var future = future_;
            _ = try future.await(io);
        }
    }
    while (future_list.pop()) |future_| {
        var future = future_;
        _ = try future.await(io);
    }
    log.warn("closing, and cleaning up", .{});
}

const OnceFuture = Io.Future(@typeInfo(@TypeOf(once)).@"fn".return_type.?);

pub fn once(z: *const zWSGI, stream: *net.Stream, gpa: Allocator, io: Io) !void {
    var timer = try std.time.Timer.start();
    const now = try std.Io.Clock.now(.real, io);

    defer stream.close(io);

    var arena = std.heap.ArenaAllocator.init(gpa);
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
    writer.interface.flush() catch {};
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
            const key_len = try r.takeInt(u16, system.endian);
            const key_str = try r.take(key_len);
            const expected = zWSGIParam.fromStr(key_str);

            const val_len = try r.takeInt(u16, system.endian);
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
        return r.takeStruct(uProtoHeader, system.endian);
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
    const router = Router.Routes(&.{});
    _ = init(&router, .default, .{ .mode = .{ .zwsgi = .default }, .auth = .disabled });
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
const pollfd = linux.pollfd;
const posix = std.posix;
const linux = std.os.linux;
const ns_per_ms = std.time.ns_per_ms;
const system = @import("system.zig");

const Server = @import("server.zig");
const Frame = @import("frame.zig");
const Request = @import("request.zig");
const Router = @import("router.zig");
const Auth = @import("auth.zig");
