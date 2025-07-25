const Date = i64;
const VerDate = struct { u16, Date };

const browser_count = @typeInfo(UA.Browser.Name).@"enum".fields.len;

pub const Versions: [browser_count][]const Date = brk: {
    var v: [browser_count][]const Date = undefined;
    for (@typeInfo(UA.Browser.Name).@"enum".fields) |field| {
        var name: [field.name.len]u8 = field.name[0..].*;
        name[0] ^= 0b100000;
        v[field.value] = if (@hasDecl(@This(), &name))
            &@field(@This(), &name).Version.Dates
        else
            &.{};
    }

    break :brk v;
};

pub const Brave = struct {
    pub const Version = enum(u16) {
        _,

        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 0 },
        };
    };
};

pub const Chrome = struct {
    pub const Version = enum(u16) {
        _,

        pub const revision_date: i64 = 1749531600;
        pub const Dates = compileDates(&VerDates);
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
            .{ 136, 1745884800 }, .{ 137, 1749531600 },
        };
    };
};

pub const Edge = struct {
    pub const Version = enum(u16) {
        _,

        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 0 },
        };
    };
};

pub const Firefox = struct {
    pub const Version = enum(u16) {
        _,

        pub const revision_date: i64 = 1748322000;
        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 1099980000 },   .{ 1, 1099987200 },   .{ 2, 1161673200 },   .{ 3, 1213686000 },
            .{ 4, 1300777200 },   .{ 5, 1308639600 },   .{ 6, 1313478000 },   .{ 7, 1317106800 },
            .{ 8, 1320739200 },   .{ 9, 1324368000 },   .{ 10, 1327996800 },  .{ 11, 1331622000 },
            .{ 12, 1335250800 },  .{ 13, 1338879600 },  .{ 14, 1342508400 },  .{ 15, 1346137200 },
            .{ 16, 1349766000 },  .{ 17, 1353398400 },  .{ 18, 1357632000 },  .{ 19, 1361260800 },
            .{ 20, 1364886000 },  .{ 21, 1368514800 },  .{ 22, 1372143600 },  .{ 23, 1375772400 },
            .{ 24, 1379401200 },  .{ 25, 1383030000 },  .{ 26, 1386662400 },  .{ 27, 1391500800 },
            .{ 28, 1395126000 },  .{ 29, 1398754800 },  .{ 30, 1402383600 },  .{ 31, 1406012400 },
            .{ 32, 1409641200 },  .{ 33, 1413270000 },  .{ 34, 1417420800 },  .{ 35, 1421136000 },
            .{ 36, 1424764800 },  .{ 37, 1427785200 },  .{ 38, 1431414000 },  .{ 39, 1435820400 },
            .{ 40, 1439276400 },  .{ 41, 1442905200 },  .{ 42, 1446537600 },  .{ 43, 1450166400 },
            .{ 44, 1453795200 },  .{ 45, 1457424000 },  .{ 46, 1461654000 },  .{ 47, 1465282800 },
            .{ 48, 1470121200 },  .{ 49, 1474354800 },  .{ 50, 1479196800 },  .{ 51, 1485244800 },
            .{ 52, 1488873600 },  .{ 53, 1492585200 },  .{ 54, 1497337200 },  .{ 55, 1502175600 },
            .{ 56, 1506582000 },  .{ 57, 1510646400 },  .{ 58, 1516694400 },  .{ 59, 1520924400 },
            .{ 60, 1525849200 },  .{ 61, 1529996400 },  .{ 62, 1536130800 },  .{ 63, 1540278000 },
            .{ 64, 1544515200 },  .{ 65, 1548748800 },  .{ 66, 1552978800 },  .{ 67, 1558422000 },
            .{ 68, 1562655600 },  .{ 69, 1567494000 },  .{ 70, 1571727600 },  .{ 71, 1575360000 },
            .{ 72, 1578384000 },  .{ 73, 1581408000 },  .{ 74, 1583823600 },  .{ 75, 1586242800 },
            .{ 76, 1588662000 },  .{ 77, 1591081200 },  .{ 78, 1593500400 },  .{ 79, 1595919600 },
            .{ 80, 1598338800 },  .{ 81, 1600758000 },  .{ 82, 1603177200 },  .{ 83, 1605600000 },
            .{ 84, 1608019200 },  .{ 85, 1611648000 },  .{ 86, 1614067200 },  .{ 87, 1616482800 },
            .{ 88, 1618815600 },  .{ 89, 1622530800 },  .{ 90, 1626159600 },  .{ 91, 1628578800 },
            .{ 92, 1630998000 },  .{ 93, 1633417200 },  .{ 94, 1635836400 },  .{ 95, 1638864000 },
            .{ 96, 1641888000 },  .{ 97, 1644307200 },  .{ 98, 1646726400 },  .{ 99, 1649142000 },
            .{ 100, 1651561200 }, .{ 101, 1653980400 }, .{ 102, 1656399600 }, .{ 103, 1658818800 },
            .{ 104, 1661238000 }, .{ 105, 1663657200 }, .{ 106, 1666076400 }, .{ 107, 1668499200 },
            .{ 108, 1670918400 }, .{ 109, 1673942400 }, .{ 110, 1676361600 }, .{ 111, 1678777200 },
            .{ 112, 1681196400 }, .{ 113, 1683615600 }, .{ 114, 1686034800 }, .{ 115, 1688454000 },
            .{ 116, 1690873200 }, .{ 117, 1693292400 }, .{ 118, 1695711600 }, .{ 119, 1698130800 },
            .{ 120, 1700553600 }, .{ 121, 1702972800 }, .{ 122, 1705996800 }, .{ 123, 1708416000 },
            .{ 124, 1710831600 }, .{ 125, 1713250800 }, .{ 126, 1715670000 }, .{ 127, 1718089200 },
            .{ 128, 1720508400 }, .{ 129, 1722927600 }, .{ 130, 1725346800 }, .{ 131, 1727766000 },
            .{ 132, 1730185200 }, .{ 133, 1732608000 }, .{ 134, 1736236800 }, .{ 135, 1738656000 },
            .{ 136, 1741075200 }, .{ 137, 1743490800 }, .{ 138, 1745902800 }, .{ 139, 1748322000 },
        };
    };
};

pub const Hastur = struct {
    pub const Version = enum(u16) {
        _,

        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 0 },
        };
    };
};

pub const Ladybird = struct {
    pub const Version = enum(u16) {
        _,

        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 0 },
        };
    };
};

pub const Opera = struct {
    pub const Version = enum(u16) {
        _,

        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 0 },
        };
    };
};

pub const Safari = struct {
    pub const Version = enum(u16) {
        _,

        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 0 },
        };
    };
};

pub const Msie = struct {
    pub const Version = enum(u16) {
        _,
        pub const Dates = compileDates(&VerDates);
        pub const VerDates = [_]VerDate{
            .{ 0, 0 },  .{ 1, 0 },  .{ 2, 0 }, .{ 3, 0 }, .{ 4, 0 },
            .{ 5, 0 },  .{ 6, 0 },  .{ 7, 0 }, .{ 8, 0 }, .{ 9, 0 },
            .{ 10, 0 }, .{ 11, 0 },
        };
    };
};

fn compileDates(comptime vd: []const VerDate) [vd.len]Date {
    var list: [vd.len]Date = @splat(0);

    for (vd) |line| {
        std.debug.assert(list[line[0]] == 0);
        list[line[0]] = line[1];
    }
    return list;
}

pub const Rules = struct {
    const DAY: i64 = 86400;
    pub const AGE_STEP: usize = DAY * 45;

    pub fn age(ua: UA, _: *const Request, score: *f16) !void {
        if (ua.resolved != .browser) return;
        if (ua.resolved.browser.name == .unknown) return;
        const delta: i64 = ua.resolved.browser.age() catch {
            return;
        };
        const YEAR: i64 = 86400 * 365;
        // These are all just made up based on feeling, TODO real data analysis
        switch (delta) {
            std.math.minInt(i64)...0 => {},
            1...AGE_STEP => {},
            AGE_STEP + 1...AGE_STEP * 3 => score.* = score.* + 0.1,
            AGE_STEP * 3 + 1...YEAR => score.* = score.* + 0.3,
            YEAR + 1...YEAR * 3 => score.* = score.* + 0.4,
            YEAR * 3 + 1...std.math.maxInt(i64) => score.* = if (score.* < 0.9)
                0.9
            else
                score.*,
        }
    }

    test age {
        var score: f16 = 0.0;
        try age(.{ .string = "", .resolved = .{
            .browser = .{ .name = .chrome, .version = 0 },
        } }, undefined, &score);
        try std.testing.expectEqual(score, 0.9);
        score = 0;
        try age(.{ .string = "", .resolved = .{
            .browser = .{
                .name = .chrome,
                .version = Chrome.Version.VerDates[Chrome.Version.VerDates.len - 1][0],
            },
        } }, undefined, &score);
        std.testing.expectEqual(0.0, score) catch |err| {
            if (Chrome.Version.revision_date < std.time.timestamp() - AGE_STEP) {
                std.debug.print("bot-detection.browsers.version is out of date\n", .{});
                return error.SkipZigTest;
            }
            return err;
        };

        score = 0.0;
        try age(.{ .string = "", .resolved = .{
            .browser = .{ .name = .unknown, .version = 0 },
        } }, undefined, &score);
        try std.testing.expectEqual(score, 0.0);
    }

    pub fn acceptStr(ua: UA, r: *const Request, score: *f16) !void {
        std.debug.assert(ua.resolved == .browser);
        switch (ua.resolved.browser.name) {
            .chrome => {},
            else => {
                const normal = "text/html,application/xhtml+xml,";
                // My apologies for the obfuscation here, this signal is way to strong
                // to release to the unmotivated opfor.
                const obfuscated = [_]u8{
                    97,  112, 112, 108, 105, 99,  97,  116, 105, 111, 110, 47,  120,
                    109, 108, 59,  113, 61,  48,  46,  57,  44,  105, 109, 97,  103,
                    101, 47,  97,  118, 105, 102, 44,  105, 109, 97,  103, 101, 47,
                    119, 101, 98,  112, 44,  105, 109, 97,  103, 101, 47,  97,  112,
                    110, 103, 44,  42,  47,  42,  59,  113, 61,  48,  46,  56,  44,
                    97,  112, 112, 108, 105, 99,  97,  116, 105, 111, 110, 47,  115,
                    105, 103, 110, 101, 100, 45,  101, 120, 99,  104, 97,  110, 103,
                    101, 59,  118, 61,  98,  51,  59,  113, 61,  48,  46,  55,
                };
                const accept_str = normal ++ obfuscated;
                if (r.accept) |racpt| if (eql(u8, racpt, accept_str)) {
                    score.* = @max(score.*, 1.0);
                };
            },
        }
    }

    pub fn protocolVer(_: UA, r: *const Request, score: *f16) !void {
        if (!r.secure) return;

        // TODO To actually be correct, this should do a browser version check as well

        switch (r.protocol) {
            .http => |http| switch (http) {
                .@"1.0" => score.* += 1.0,
                .@"1.1" => score.* += 1.0,
                .@"2.0" => {},
            },
            .malformed => |_| {},
        }
    }
};

const browsers = @This();
test browsers {
    _ = std.testing.refAllDecls(browsers);
}

const std = @import("std");
const UA = @import("../user-agent.zig");
const Request = @import("../request.zig");

const eql = std.mem.eql;
