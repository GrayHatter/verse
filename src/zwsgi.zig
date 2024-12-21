const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.Verse);
const net = std.net;
const siginfo_t = std.posix.siginfo_t;
const SIG = std.posix.SIG;
const SA = std.posix.SA;

const Verse = @import("verse.zig");
const Request = @import("request.zig");
const Router = @import("router.zig");

pub const zWSGI = @This();

alloc: Allocator,
unix_file: []const u8,
options: Options,
router: Router,

pub const Options = struct {
    file: []const u8 = "./zwsgi_file.sock",
    chmod: ?std.posix.mode_t = null,
};

pub fn init(a: Allocator, opts: Options, router: Router) zWSGI {
    return .{
        .alloc = a,
        .unix_file = opts.file,
        .router = router,
        .options = opts,
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

    signalListen(SIG.INT) catch {
        log.err("Unable to install sigint handler", .{});
        return error.Unexpected;
    };

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

    while (running) {
        var pollfds = [1]std.os.linux.pollfd{
            .{ .fd = server.stream.handle, .events = std.math.maxInt(i16), .revents = 0 },
        };
        const ready = try std.posix.poll(&pollfds, 100);
        if (ready == 0) continue;
        var acpt = try server.accept();
        defer acpt.stream.close();
        var timer = try std.time.Timer.start();

        var arena = std.heap.ArenaAllocator.init(z.alloc);
        defer arena.deinit();
        const a = arena.allocator();

        var zreq = try zWSGIRequest.init(a, &acpt);
        const request_data = try requestData(a, &zreq);
        const request = try Request.initZWSGI(a, &zreq, request_data);
        var verse = try Verse.init(a, &request);

        defer {
            const vars = verse.request.raw.zwsgi.vars;
            log.err("zWSGI: [{d:.3}] {s} - {s}: {s} -- \"{s}\"", .{
                @as(f64, @floatFromInt(timer.lap())) / 1000000.0,
                findOr(vars, "REMOTE_ADDR"),
                findOr(vars, "REQUEST_METHOD"),
                findOr(vars, "REQUEST_URI"),
                findOr(vars, "HTTP_USER_AGENT"),
            });
        }

        const callable = z.router.routerfn(&verse, z.router.routefn);
        z.router.builderfn(&verse, callable);
    }
    log.warn("closing, and cleaning up", .{});
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

fn signalListen(signal: u6) !void {
    try std.posix.sigaction(signal, &std.posix.Sigaction{
        .handler = .{ .sigaction = sig_cb },
        .mask = std.posix.empty_sigset,
        .flags = SA.SIGINFO,
    }, null);
}

pub const zWSGIRequest = struct {
    conn: *net.Server.Connection,
    header: uProtoHeader = uProtoHeader{},
    vars: []uWSGIVar = &[0]uWSGIVar{},

    pub fn init(a: Allocator, c: *net.Server.Connection) !zWSGIRequest {
        const uwsgi_header = try uProtoHeader.init(c);

        const buf: []u8 = try a.alloc(u8, uwsgi_header.size);
        const read = try c.stream.read(buf);
        if (read != uwsgi_header.size) {
            std.log.err("unexpected read size {} {}", .{ read, uwsgi_header.size });
        }

        const vars = try readVars(a, buf);
        for (vars) |v| {
            log.debug("{}", .{v});
        }

        return .{
            .conn = c,
            .header = uwsgi_header,
            .vars = vars,
        };
    }
    fn readVars(a: Allocator, b: []const u8) ![]uWSGIVar {
        var list = std.ArrayList(uWSGIVar).init(a);
        var buf = b;
        while (buf.len > 0) {
            const keysize = readU16(buf[0..2]);
            buf = buf[2..];
            const key = try a.dupe(u8, buf[0..keysize]);
            buf = buf[keysize..];

            const valsize = readU16(buf[0..2]);
            buf = buf[2..];
            const val = try a.dupe(u8, if (valsize == 0) "" else buf[0..valsize]);
            buf = buf[valsize..];

            try list.append(uWSGIVar{
                .key = key,
                .val = val,
            });
        }
        return try list.toOwnedSlice();
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

    if (find(zreq.vars, "HTTP_CONTENT_LENGTH")) |h_len| {
        const h_type = findOr(zreq.vars, "HTTP_CONTENT_TYPE");

        const post_size = try std.fmt.parseInt(usize, h_len, 10);
        if (post_size > 0) {
            var reader = zreq.conn.stream.reader().any();
            post_data = try Request.Data.readBody(a, &reader, post_size, h_type);
            log.debug(
                "post data \"{s}\" {{{any}}}",
                .{ post_data.?.rawpost, post_data.?.rawpost },
            );

            for (post_data.?.items) |itm| {
                log.debug("{}", .{itm});
            }
        }
    }

    var query: Request.Data.QueryData = undefined;
    if (find(zreq.vars, "QUERY_STRING")) |qs| {
        query = try Request.Data.readQuery(a, qs);
    }
    return .{
        .post = post_data,
        .query = query,
    };
}

test init {
    const a = std.testing.allocator;

    const R = struct {
        fn route(verse: *Verse) Router.RoutingError!Router.BuildFn {
            return Verse.Router.router(verse, &.{});
        }
    };

    _ = init(a, .{}, .{ .routefn = R.route });
}
