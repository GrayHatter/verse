pub const Stats = struct {
    mutex: ?std.Thread.Mutex,
    start_time: i64,
    count: usize,
    mean: Mean,
    rows: [30]Line,

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
        size: usize,
        time: u64,
        uri: Array,
        us: usize,

        const Array = std.BoundedArray(u8, 2048);
        pub const empty: Line = .{
            .number = 0,
            .size = 0,
            .time = 0,
            .uri = .{},
            .us = 0,
        };
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
            .rows = @splat(.empty),
        };
    }

    pub fn log(stats: *Stats, data: Data) void {
        if (stats.mutex) |*mx| mx.lock();
        defer if (stats.mutex) |*mx| mx.unlock();

        stats.rows[stats.count % stats.rows.len] = .{
            .number = stats.count,
            .size = 0,
            .time = @intCast(std.time.timestamp()),
            .uri = Line.Array.fromSlice(data.uri[0..@min(data.uri.len, 2048)]) catch unreachable,
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

    const StatsPage = PageData("builtin-html/stats.html");

    pub const stats = index;

    pub fn index(f: *Frame) Router.Error!void {
        var data: [30]S.StatsList = @splat(.{
            .number = 0,
            .size = 0,
            .time = 0,
            .uri = "null",
            .us = 0,
        });
        var count: usize = 0;
        var uptime = std.time.timestamp();
        var mean_time: u64 = 0;

        if (f.server.stats) |active| {
            count = active.count;
            uptime -|= active.start_time;
            mean_time = active.mean.mean(@truncate(count));
            for (&data, &active.rows) |*dst, *src| {
                dst.* = .{
                    .number = src.number,
                    .size = src.size,
                    .time = src.time,
                    .uri = src.uri.slice(),
                    .us = src.us,
                };
            }
        }

        var first = data[0..@min(count % data.len, data.len)];
        var last = data[count % data.len .. @min(count, data.len)];

        if (count > data.len) {
            last = first;
            first = data[count % data.len .. @min(count, data.len)];
        }

        const page = StatsPage.init(.{
            .uptime = @intCast(uptime),
            .count = count,
            .mean_resp_time = mean_time,
            .stats_list = first,
            .stats_list_last = @ptrCast(last),
        });
        return f.sendPage(&page);
    }

    pub fn websocket(_: *Frame) Router.Error!void {}
};

const std = @import("std");
const Frame = @import("frame.zig");
