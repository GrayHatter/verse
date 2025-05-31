pub const Options = struct {
    auth_mode: AuthMode,

    pub const AuthMode = enum {
        auth_required,
        sensitive,
        open,
    };

    pub const default: Options = .{
        .auth_mode = .sensitive,
    };
};

pub var options: Options = .default;

pub const Stats = struct {
    mutex: ?std.Thread.Mutex,
    start_time: i64,
    count: usize,
    mean: Mean,
    rows: [256]Line,

    const Mean = struct {
        time: [256]u64 = undefined,
        idx: u8 = 0,

        ///
        fn mean(m: Mean, count: u8) u64 {
            if (count == 0) return 0;
            // TODO vectorize
            //if (count < m.idx) {
            //    const sum = @reduce(.Add, m.time[m.idx - count .. m.idx]);
            //    return sum / count;
            //} else {
            //    var sum = @reduce(.Add, m.time[0..m.idx]);
            //    sum += @reduce(.Add, m.time[m.time.len - count - m.idx .. m.time.len]);
            //    return sum / count;
            //}
            var sum: u128 = 0;
            for (0..count) |i| {
                sum += m.time[m.idx -| 1 -| i];
            }
            return @truncate(sum / count);
        }
    };

    pub const Line = struct {
        addr: Addr,
        code: std.http.Status,
        number: usize,
        page_size: usize,
        rss: usize,
        time: u64,
        ua: ?UserAgent,
        uri: Uri,
        us: usize,

        pub const Size = 2048;
        // These are different because I haven't finalized the expected type
        // and size yet.
        const Uri = std.BoundedArray(u8, Size);
        const Addr = std.BoundedArray(u8, Size);
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
        rss: usize,
        ua: ?UserAgent,
        uri: []const u8,
        us: u64,
    };

    pub fn init(threaded: bool) Stats {
        return .{
            .count = 0,
            .mean = .{},
            .mutex = if (threaded) .{} else null,
            .rows = @splat(.empty),
            .start_time = std.time.timestamp(),
        };
    }

    pub fn log(stats: *Stats, data: Data) void {
        if (stats.mutex) |*mx| mx.lock();
        defer if (stats.mutex) |*mx| mx.unlock();

        stats.rows[stats.count % stats.rows.len] = .{
            .code = data.code,
            .addr = Line.Addr.fromSlice(data.addr[0..@min(data.addr.len, Line.Size)]) catch unreachable,
            .number = stats.count,
            .page_size = data.page_size,
            .rss = data.rss,
            .time = @intCast(std.time.timestamp()),
            .ua = data.ua,
            .uri = Line.Uri.fromSlice(data.uri[0..@min(data.uri.len, Line.Size)]) catch unreachable,
            .us = data.us,
        };
        stats.count += 1;

        stats.mean.time[stats.mean.idx] = data.us;
        stats.mean.idx +%= 1;

        return;
    }
};

pub const Endpoint = struct {
    //const EP = @import("endpoint.zig");
    const Router = @import("router.zig");
    const PageData = @import("template.zig").PageData;
    const S = @import("template.zig").Structs;
    pub const verse_name = .stats;

    const StatsPage = PageData("builtin-html/verse-stats.html");

    pub const stats = index;

    fn codeSlice(code: std.http.Status) []const u8 {
        return switch (code) {
            inline .ok,
            .not_found,
            .internal_server_error,
            => |c| std.fmt.comptimePrint("{}: {s}", .{ @as(usize, @intFromEnum(c)), @tagName(c) }),
            else => "status code not implemented",
        };
    }

    pub fn index(f: *Frame) Router.Error!void {
        var include_ip: bool = false;
        switch (options.auth_mode) {
            .auth_required => {
                if (f.auth_provider.vtable.valid == null) return f.sendDefaultErrorPage(.not_implemented);
            },
            .sensitive => {
                if (f.user) |user| if (f.auth_provider.valid(&user)) {
                    include_ip = true;
                };
            },
            .open => include_ip = true,
        }

        var data: [60]S.VerseStatsList = @splat(
            .{
                .code = "",
                .ip_address = "",
                .number = 0,
                .page_size = 0,
                .rss = 0,
                .time = 0,
                .uri = "null",
                .us = 0,
                .verse_user_agent = null,
            },
        );
        var count: usize = 0;
        var uptime = std.time.timestamp();
        var mean_time: u64 = 0;

        if (@as(*Server, @ptrCast(@constCast(f.server))).stats) |active| {
            count = active.count;
            uptime -|= active.start_time;
            mean_time = active.mean.mean(@truncate(count));
            for (0..data.len) |i| {
                if (i >= count) break;
                const idx = count - i - 1;
                const src = &active.rows[idx % active.rows.len];
                const ua: ?S.VerseUserAgent = if (src.ua) |sua|
                    switch (sua.resolved) {
                        .bot => |b| .{
                            .name = @tagName(b.name),
                            .version = 0,
                        },
                        .browser => |b| .{
                            .name = @tagName(b.name),
                            .version = b.version,
                        },
                        .script => |s| .{ .name = @tagName(s.name), .version = s.version },
                        .unknown => .{ .name = "[unknown]", .version = null },
                    }
                else
                    null;

                var is_bot: ?[]const u8 = null;
                if (src.ua) |sua| {
                    if (sua.resolved == .bot) is_bot = " bot";
                    if (@TypeOf(sua.bot_validation) != ?void) {
                        const bv: UserAgent.BotDetection = sua.bot_validation orelse .init(f.request);
                        if (bv.malicious or bv.bot and sua.resolved != .bot) is_bot = " bot-malicious";
                    }
                }

                data[i] = .{
                    .code = codeSlice(src.code),
                    .ip_address = if (include_ip) src.addr.slice() else "[redacted]",
                    .number = src.number,
                    .rss = src.rss,
                    .page_size = src.page_size,
                    .time = src.time,
                    .uri = src.uri.slice(),
                    .verse_user_agent = ua orelse .{
                        .name = "[No User Agent Provided]",
                        .version = 0,
                    },
                    .is_bot = is_bot,
                    .us = src.us,
                };
            }
        }

        const page = StatsPage.init(.{
            .uptime = @intCast(uptime),
            .count = count,
            .mean_resp_time = mean_time,
            .verse_stats_list = data[0..@min(count, data.len)],
        });
        return f.sendPage(&page);
    }

    pub fn websocket(_: *Frame) Router.Error!void {}
};

const std = @import("std");
const Frame = @import("frame.zig");
const Server = @import("server.zig");
const UserAgent = @import("user-agent.zig");
