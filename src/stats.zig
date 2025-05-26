pub const Stats = struct {
    mutex: ?std.Thread.Mutex,
    start_time: i64,
    count: usize,
    mean: Mean,

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

    pub const Data = struct {
        uri: []const u8,
        us: u64,
    };

    pub fn init(threaded: bool) Stats {
        return .{
            .mutex = if (threaded) .{} else null,
            .start_time = std.time.timestamp(),
            .count = 0,
            .mean = .{},
        };
    }

    pub fn log(stats: *Stats, data: Data) void {
        if (stats.mutex) |*mx| mx.lock();
        defer if (stats.mutex) |*mx| mx.unlock();

        stats.count += 1;
        stats.mean.time[stats.mean.idx] = data.us;
        stats.mean.idx +%= 1;
        return;
    }
};

pub var active_stats: ?*Stats = null;

pub const Endpoint = struct {
    //const EP = @import("endpoint.zig");
    const PageData = @import("template.zig").PageData;
    const S = @import("template.zig").Structs;
    pub const verse_name = .stats;

    pub const verse_routes = [_]Router.Match{};

    const StatsPage = PageData("builtin-html/stats.html");

    pub fn index(f: *Frame) Router.Error!void {
        var data: [30]S.StatsList = @splat(.{ .uri = "null", .time = "never", .size = "unknown" });
        var count: usize = 0;
        var uptime = std.time.timestamp();
        var mean_time: u64 = 0;

        if (active_stats) |active| {
            count = active.count;
            uptime -|= active.start_time;
            mean_time = active.mean.mean(@truncate(count));
        }

        const page = StatsPage.init(.{
            .uptime = @intCast(uptime),
            .count = count,
            .mean_resp_time = mean_time,
            .stats_list = data[0..@min(count, data.len)],
        });
        return f.sendPage(&page);
    }

    pub fn websocket(_: *Frame) Router.Error!void {}
};

const std = @import("std");
const Server = @import("server.zig");
const Frame = @import("frame.zig");
const Router = @import("router.zig");
