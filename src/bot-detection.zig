//! Bot Detection
//!
//! It does something, what that something is? who know, but it's big!

bot: bool,
malicious: bool,

const BotDetection = @This();

pub fn init(r: *const Request) BotDetection {
    if (r.user_agent == null) return .{ .bot = true, .malicious = true };
    const ua = r.user_agent.?;
    var score: f64 = 0.0;

    inline for (rules) |rule| {
        rule(ua, r, &score) catch @panic("not implemented");
    }

    switch (ua.resolved) {
        .bot => {
            return .{
                .bot = true,
                .malicious = false,
            };
        },
        .browser => |browser| {
            switch (browser.name) {
                .chrome => {
                    return .{
                        .bot = score >= 0.5,
                        .malicious = score >= 0.5,
                    };
                },
                else => {
                    return .{
                        .bot = score >= 0.5,
                        .malicious = score >= 0.5,
                    };
                },
            }
        },
        .script => {
            return .{
                .bot = true,
                .malicious = false,
            };
        },
        .unknown => {
            return .{
                .bot = true,
                .malicious = std.mem.startsWith(u8, ua.string, "Mozilla/"),
            };
        },
    }
    comptime unreachable;
}

const RuleError = error{
    Generic,
};

const RuleFn = fn (UA, *const Request, *f64) RuleError!void;

const rules = [_]RuleFn{
    Browsers.browserAge,
};

pub const Browsers = struct {
    const Date = i64;
    const VerDate = struct { u16, Date };
    const browser_count = @typeInfo(UA.Browser.Name).@"enum".fields.len;
    pub const Versions: [browser_count][]const Date = brk: {
        var v: [browser_count][]const Date = undefined;
        v[@intFromEnum(UA.Browser.Name.brave)] = &.{};
        v[@intFromEnum(UA.Browser.Name.chrome)] = &Chrome.Version.Dates;
        v[@intFromEnum(UA.Browser.Name.edge)] = &.{};
        v[@intFromEnum(UA.Browser.Name.firefox)] = &.{};
        v[@intFromEnum(UA.Browser.Name.hastur)] = &.{};
        v[@intFromEnum(UA.Browser.Name.ladybird)] = &.{};
        v[@intFromEnum(UA.Browser.Name.opera)] = &.{};
        v[@intFromEnum(UA.Browser.Name.safari)] = &.{};
        v[@intFromEnum(UA.Browser.Name.unknown)] = &.{};

        break :brk v;
    };

    pub const Chrome = struct {
        pub const Version = enum(u16) {
            _,

            pub const VerDates = [_]VerDate{
                .{ 0, 1227513600 },   .{ 1, 1228982400 },   .{ 2, 1243148400 },   .{ 3, 1255330800 },
                .{ 4, 1264406400 },   .{ 5, 1274425200 },   .{ 6, 1283410800 },   .{ 7, 1287644400 },
                .{ 8, 1291276800 },   .{ 9, 1296720000 },   .{ 10, 1299571200 },  .{ 11, 1303887600 },
                .{ 12, 1307430000 },  .{ 13, 1312268400 },  .{ 14, 1316156400 },  .{ 15, 1319526000 },
                .{ 16, 1323763200 },  .{ 17, 1328688000 },  .{ 18, 1332918000 },  .{ 19, 1337065200 },
                .{ 20, 1340694000 },  .{ 21, 1343718000 },  .{ 22, 1348556400 },  .{ 23, 1352188800 },
                .{ 24, 1357804800 },  .{ 25, 1361433600 },  .{ 26, 1364281200 },  .{ 27, 1369119600 },
                .{ 28, 1371452400 },  .{ 29, 1376982000 },  .{ 30, 1379487600 },  .{ 31, 1384243200 },
                .{ 32, 1389686400 },  .{ 33, 1392710400 },  .{ 34, 1396422000 },  .{ 35, 1400569200 },
                .{ 36, 1405407600 },  .{ 37, 1409036400 },  .{ 38, 1412665200 },  .{ 39, 1415779200 },
                .{ 40, 1421740800 },  .{ 41, 1425369600 },  .{ 42, 1428994800 },  .{ 43, 1432018800 },
                .{ 44, 1437462000 },  .{ 45, 1441090800 },  .{ 46, 1444719600 },  .{ 47, 1448956800 },
                .{ 48, 1453276800 },  .{ 49, 1456905600 },  .{ 50, 1460530800 },  .{ 51, 1464159600 },
                .{ 52, 1468998000 },  .{ 53, 1472626800 },  .{ 54, 1476255600 },  .{ 55, 1480579200 },
                .{ 56, 1485331200 },  .{ 57, 1489046400 },  .{ 58, 1492585200 },  .{ 59, 1496646000 },
                .{ 60, 1500966000 },  .{ 61, 1504594800 },  .{ 62, 1508223600 },  .{ 63, 1512460800 },
                .{ 64, 1516694400 },  .{ 65, 1520323200 },  .{ 66, 1523948400 },  .{ 67, 1527577200 },
                .{ 68, 1532415600 },  .{ 69, 1536044400 },  .{ 70, 1539673200 },  .{ 71, 1543910400 },
                .{ 72, 1548748800 },  .{ 73, 1552374000 },  .{ 74, 1556002800 },  .{ 75, 1559631600 },
                .{ 76, 1564470000 },  .{ 77, 1568098800 },  .{ 78, 1571727600 },  .{ 79, 1575964800 },
                .{ 80, 1580803200 },  .{ 81, 1586242800 },  .{ 82, 0 },           .{ 83, 1589871600 },
                // version 82 was never released
                .{ 84, 1594710000 },  .{ 85, 1598338800 },  .{ 86, 1601967600 },  .{ 87, 1605600000 },
                .{ 88, 1611043200 },  .{ 89, 1614672000 },  .{ 90, 1618297200 },  .{ 91, 1621926000 },
                .{ 92, 1626764400 },  .{ 93, 1630393200 },  .{ 94, 1630393200 },  .{ 95, 1634626800 },
                .{ 96, 1637049600 },  .{ 97, 1641196800 },  .{ 98, 1643702400 },  .{ 99, 1646208000 },
                .{ 100, 1648537200 }, .{ 101, 1651561200 }, .{ 102, 1654758000 }, .{ 103, 1655967600 },
                .{ 104, 1659423600 }, .{ 105, 1660978800 }, .{ 106, 1664262000 }, .{ 107, 1666681200 },
                .{ 108, 1669708800 }, .{ 109, 1673337600 }, .{ 110, 1675756800 }, .{ 111, 1677657600 },
                .{ 112, 1680073200 }, .{ 113, 1682492400 }, .{ 114, 1684911600 }, .{ 115, 1689145200 },
                .{ 116, 1691564400 }, .{ 117, 1694156400 }, .{ 118, 1696402800 }, .{ 119, 1698217200 },
                .{ 120, 1701244800 }, .{ 121, 1705478400 }, .{ 122, 1707897600 }, .{ 123, 1710313200 },
                .{ 124, 1712732400 }, .{ 125, 1715151600 }, .{ 126, 1717570800 }, .{ 127, 1721199600 },
                .{ 128, 1723618800 }, .{ 129, 1726038000 }, .{ 130, 1728457200 }, .{ 131, 1730880000 },
                .{ 132, 1736323200 }, .{ 133, 1738137600 }, .{ 134, 1740556800 }, .{ 135, 1743465600 },
            };
            pub const Dates: [VerDates.len]Date = brk: {
                var list: [VerDates.len]Date = @splat(0);

                for (VerDates) |line| {
                    std.debug.assert(list[line[0]] == 0);
                    list[line[0]] = line[1];
                }
                break :brk list;
            };
        };
    };

    pub fn browserAge(ua: UA, _: *const Request, score: *f64) !void {
        if (ua.resolved != .browser) return;
        if (ua.resolved.browser.name == .unknown) return;
        const delta: i64 = ua.resolved.browser.age() catch {
            std.debug.print("Unable to resolve age for {}\n", .{ua});
            return;
        };
        const DAY: i64 = 86400;
        const YEAR: i64 = 86400 * 365;
        // These are all just made up based on feeling, TODO real data analysis
        switch (delta) {
            std.math.minInt(i64)...0 => {},
            1...DAY * 45 => {},
            DAY * 45 + 1...DAY * 120 => score.* = score.* + 0.1,
            DAY * 120 + 1...YEAR => score.* = score.* + 0.3,
            YEAR + 1...YEAR * 3 => score.* = score.* + 0.4,
            YEAR * 3 + 1...std.math.maxInt(i64) => score.* = 1.0,
        }
    }

    test browserAge {
        var score: f64 = 0.0;
        try browserAge(.{ .string = "", .resolved = .{
            .browser = .{ .name = .chrome, .version = 0 },
        } }, undefined, &score);
        try std.testing.expectEqual(score, 1.0);
        score = 0;
        try browserAge(.{ .string = "", .resolved = .{
            .browser = .{
                .name = .chrome,
                .version = Browsers.Chrome.Version.VerDates[Browsers.Chrome.Version.VerDates.len - 1][0],
            },
        } }, undefined, &score);
        try std.testing.expectEqual(score, 0.0);

        score = 0.0;
        try browserAge(.{ .string = "", .resolved = .{
            .browser = .{ .name = .unknown, .version = 0 },
        } }, undefined, &score);
        try std.testing.expectEqual(score, 0.0);
    }
};

test Browsers {
    _ = &Browsers.Chrome.Version;
    try std.testing.expectEqual(Browsers.Chrome.Version.Dates[93], 1630393200);
    //for (0.., Browsers.Chrome.Versions.release) |i, date| {
    //    std.debug.print("{} on {}\n", .{ i, date });
    //}
}

const std = @import("std");
const UA = @import("user-agent.zig");
const Request = @import("request.zig");
