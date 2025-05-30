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
        number: usize,
        time: u64,
        addr: Addr,
        size: usize,
        uri: Uri,
        us: usize,
        ua: ?UserAgent,

        pub const Size = 2048;
        // These are different because I haven't finalized the expected type
        // and size yet.
        const Uri = std.BoundedArray(u8, Size);
        const Addr = std.BoundedArray(u8, Size);
        pub const empty: Line = .{
            .addr = .{},
            .number = 0,
            .size = 0,
            .time = 0,
            .uri = .{},
            .ua = null,
            .us = 0,
        };
    };

    pub const Data = struct {
        addr: []const u8,
        uri: []const u8,
        us: u64,
        ua: ?UserAgent,
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
            .addr = Line.Addr.fromSlice(data.addr[0..@min(data.addr.len, Line.Size)]) catch unreachable,
            .number = stats.count,
            .size = 0,
            .time = @intCast(std.time.timestamp()),
            .uri = Line.Uri.fromSlice(data.uri[0..@min(data.uri.len, Line.Size)]) catch unreachable,
            .ua = data.ua,
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
                .ip_address = "",
                .number = 0,
                .size = 0,
                .time = 0,
                .uri = "null",
                .verse_user_agent = null,
                .us = 0,
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
                        .script => |s| .{ .name = @tagName(s), .version = null },
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
                    .ip_address = if (include_ip) src.addr.slice() else "[redacted]",
                    .number = src.number,
                    .size = src.size,
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
