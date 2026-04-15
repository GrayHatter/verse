options: Options,
mutex: Mutex,
start_time: Timestamp,
count: usize,
mean: Mean,
rows: []Line,

const Stats = @This();

pub const Options = struct {
    auth_mode: AuthMode,
    threaded: bool = true,

    pub const AuthMode = enum {
        auth_required,
        sensitive,
        open,
        stats_disabled,
    };

    pub const default: Options = .{ .auth_mode = .sensitive };
    pub const disabled: Options = .{ .auth_mode = .stats_disabled };
};

pub const disabled: Stats = .{
    .options = .disabled,
    .mutex = .init,
    .start_time = undefined,
    .count = 0,
    .mean = .{},
    .rows = &.{},
};

const Mean = struct {
    sum: u64 = 0,

    fn add(m: *Mean, ts: u64) void {
        m.sum +%= ts;
    }

    fn mean(m: Mean, count: u64) u64 {
        if (count == 0) return 0;
        return @truncate(m.sum / count);
    }
};

pub const Line = struct {
    addr: ArrBuf,
    code: std.http.Status,
    number: usize,
    page_size: usize,
    rss: usize,
    time: u64,
    ua: ?UserAgent,
    uri: ArrBuf,
    us: usize,

    pub const ArrBuf = struct {
        buf: [size]u8 = undefined,
        len: usize = 0,

        pub fn init(str: []const u8) ArrBuf {
            var ab: ArrBuf = undefined;
            ab.len = @min(size, str.len);
            @memcpy(ab.buf[0..ab.len], str[0..ab.len]);
            return ab;
        }

        pub fn slice(ab: *const ArrBuf) []const u8 {
            return ab.buf[0..ab.len];
        }
    };

    pub const size = 2048;
    pub const empty: Line = .{
        .addr = .{},
        .code = .internal_server_error,
        .number = 0,
        .page_size = 0,
        .rss = 0,
        .time = 0,
        .ua = null,
        .uri = .{},
        .us = 0,
    };
};

pub const Data = struct {
    addr: []const u8,
    code: std.http.Status,
    page_size: usize,
    time: i96,
    rss: usize,
    ua: ?UserAgent,
    uri: []const u8,
    us: u64,
};

pub fn init(rows: []Line, start: Timestamp, opts: Options) Stats {
    return .{
        .options = opts,
        .count = 0,
        .mean = .{},
        .mutex = .init,
        .rows = rows,
        .start_time = start,
    };
}

pub fn log(stats: *Stats, data: Data, io: Io) void {
    if (stats.options.auth_mode == .stats_disabled) return;
    stats.mutex.lock(io) catch return;
    defer stats.mutex.unlock(io);
    const row: *Line = &stats.rows[stats.count % stats.rows.len];
    row.* = .{
        .addr = .init(data.addr),
        .code = data.code,
        .number = stats.count,
        .page_size = data.page_size,
        .rss = data.rss,
        .time = @intCast(data.time), // TODO FIXME
        .ua = data.ua,
        .uri = .init(data.uri),
        .us = data.us,
    };
    stats.count += 1;
    stats.mean.add(data.us);

    return;
}

pub const Endpoint = struct {
    const Router = @import("router.zig");
    const PageData = @import("template.zig").PageData;
    const S = @import("template.zig").Structs;
    pub const verse_name = .stats;

    const StatsPage = PageData("builtin-html/verse-stats.html");

    pub const stats = index;

    fn codeString(code: std.http.Status) []const u8 {
        return switch (code) {
            .ok => "Ok",
            .found => "Found",
            .not_found => "Not Found",
            .internal_server_error => "Internal Server Error",
            else => "not implemented",
        };
    }

    pub fn index(f: *Frame) Router.Error!void {
        const server: *Server = @ptrCast(@alignCast(@constCast(f.server)));
        const include_ip: bool = switch (server.stats.options.auth_mode) {
            .stats_disabled => return f.sendDefaultErrorPage(.gone),
            .auth_required => if (f.user) |user|
                if (f.auth_provider.valid(&user)) true else return error.Unauthorized
            else
                return f.sendDefaultErrorPage(.not_implemented),
            .sensitive => if (f.user) |user| f.auth_provider.valid(&user) else false,
            .open => true,
        };

        var data: [60]S.VerseStatsHtml.VerseStatsList = undefined;
        const uptime: u64 = @intCast(server.stats.start_time.untilNow(f.io, .real).toSeconds());
        const mean_time: u64 = server.stats.mean.mean(@truncate(server.stats.count));
        const rows = data[0..@min(server.stats.count, data.len)];

        for (rows, 0..) |*row, i| {
            const src = &server.stats.rows[i % server.stats.rows.len];
            const ua_str: []const u8, const ua_ver: ?usize = if (src.ua) |sua|
                switch (sua.agent) {
                    .bot => |b| .{ @tagName(b.name), 0 },
                    .browser => |b| .{ @tagName(b.name), b.version },
                    .script => |s| .{ @tagName(s.name), s.version },
                    .unknown => .{ "[unknown]", null },
                }
            else
                .{ "[No User Agent Provided]", 0 };

            var is_bot: ?[]const u8 = null;
            if (src.ua) |sua| {
                if (sua.agent == .bot) is_bot = " verse-bot";
                if (@TypeOf(sua.validation) != void) {
                    const bv: Robots = sua.validation orelse .init(f.request);
                    if (bv.malicious or bv.automated and sua.agent != .bot) is_bot = " verse-bot-malicious";
                }
            }

            const status_class = switch (src.code) {
                .ok => " verse-stats-200",
                .moved_permanently => " verse-stats-301",
                .found => " verse-stats-302",
                .see_other => " verse-stats-303",
                .bad_request => " verse-stats-400",
                .unauthorized => " verse-stats-401",
                .forbidden => " verse-stats-403",
                .not_found => " verse-stats-404",
                .internal_server_error => " verse-stats-500",
                else => "",
            };

            row.* = .{
                .number = src.number,
                .time = src.time,
                .ip_address = if (include_ip) src.addr.slice() else "[redacted]",
                .code = @intFromEnum(src.code),
                .code_string = codeString(src.code),
                .status_class = status_class,
                .rss = src.rss,
                .page_size = src.page_size,
                .uri = .abx(src.uri.slice()),
                .user_agent_name = ua_str,
                .user_agent_version = ua_ver,
                .is_bot = is_bot,
                .us = src.us,
            };
        }

        const page = StatsPage.init(.{
            .uptime = @intCast(uptime),
            .count = server.stats.count,
            .mean_resp_time = mean_time,
            .verse_stats_list = rows,
        });
        return f.sendPage(&page);
    }

    pub fn websocket(_: *Frame) Router.Error!void {}
};

const std = @import("std");
const Frame = @import("frame.zig");
const Server = @import("server.zig");
const UserAgent = @import("UserAgent.zig");
const Robots = @import("Robots.zig");
const Timestamp = std.Io.Timestamp;
const Io = std.Io;
const Mutex = std.Io.Mutex;
