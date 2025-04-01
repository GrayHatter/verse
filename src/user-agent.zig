//! User Agent
//! TODO write doc comments
string: []const u8,
resolved: Resolved,

const UserAgent = @This();

pub const Resolved = union(enum) {
    bot: Bot,
    browser: Browser,
    script: Script,
    unknown: Other,

    pub fn init(str: []const u8) Resolved {
        if (startsWith(u8, str, "Mozilla/")) {
            return .mozilla(str);
        } else if (startsWith(u8, str, "curl/")) {
            return .{ .script = .curl };
        }
        return .{ .unknown = .{} };
    }

    fn mozilla(str: []const u8) Resolved {
        if (indexOf(u8, str, "bot/") != null or
            indexOf(u8, str, "Bot/") != null or
            indexOf(u8, str, "bot.html") != null or
            indexOf(u8, str, "Bot.html") != null)
        {
            return asBot(str);
        }
        return asBrowser(str);
    }

    fn asBot(str: []const u8) Resolved {
        if (endsWith(u8, str, "Googlebot/2.1; +http://www.google.com/bot.html)")) {
            return .{ .bot = .{ .name = .googlebot } };
        }
        return .{ .bot = .{ .name = .unknown } };
    }

    fn parseVersion(str: []const u8, comptime target: []const u8) error{Invalid}!u32 {
        if (indexOf(u8, str, target)) |idx| {
            const start = idx + target.len;
            // 3 is the minimum reasonable tail for a version
            if (str.len < start + 3) return error.Invalid;
            const end = indexOfScalarPos(u8, str, start, '.') orelse return error.Invalid;
            return parseInt(u32, str[start..end], 10) catch return error.Invalid;
        } else return error.Invalid;
    }

    fn asBrowser(str: []const u8) Resolved {
        if (indexOf(u8, str, "Edg/") != null) {
            return .{ .browser = .{
                .name = .edge,
                .version = parseVersion(str, "Edg/") catch return .{ .bot = .unknown },
            } };
        } else if (indexOf(u8, str, "Chrome/") != null) {
            return .{
                .browser = .{
                    .name = .chrome,
                    .version = parseVersion(str, "Chrome/") catch return .{ .bot = .unknown },
                },
            };
        } else if (indexOf(u8, str, "Firefox/") != null) {
            return .{
                .browser = .{
                    .name = .firefox,
                    .version = parseVersion(str, "Firefox/") catch return .{ .bot = .unknown },
                },
            };
        } else {
            return .{ .bot = .unknown };
        }
    }
};

test Resolved {
    try std.testing.expectEqualDeep(Resolved{ .unknown = .{} }, Resolved.init("unknown"));

    try std.testing.expectEqualDeep(
        Resolved{ .bot = .unknown },
        Resolved.init("Mozilla/5.0"),
    );

    try std.testing.expectEqualDeep(Resolved{ .unknown = .{} }, Resolved.init("mozilla/5.0"));

    const not_google_bot = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.165 Mobile Safari/537.36";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .{ .name = .chrome, .version = 134 } },
        Resolved.init(not_google_bot),
    );

    const mangled_version = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/a134.0.6998.165 Mobile Safari/537.36";
    try std.testing.expectEqualDeep(
        Resolved{ .bot = .unknown },
        Resolved.init(mangled_version),
    );

    const google_bot = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.165 Mobile Safari/537.36 " ++
        "(compatible; Googlebot/2.1; +http://www.google.com/bot.html)";
    try std.testing.expectEqualDeep(
        Resolved{ .bot = .{ .name = .googlebot } },
        Resolved.init(google_bot),
    );

    const fake_edge_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " ++
        "(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .{ .name = .edge, .version = 114 } },
        Resolved.init(fake_edge_ua),
    );

    const lin_ff = "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .{ .name = .firefox, .version = 134 } },
        Resolved.init(lin_ff),
    );
}

pub const Bot = struct {
    name: Name = .unknown,

    pub const Name = enum {
        googlebot,
        unknown,
    };

    pub const unknown: Bot = .{ .name = .unknown };
};

pub const Browser = struct {
    name: Name,
    // This was a u16, but then I realized, I don't trust browsers.
    version: u32,
    version_string: []const u8 = "",

    pub const Name = enum {
        chrome,
        edge,
        firefox,
        hastur,
        opera,
        safari,
        brave,
        ladybird,
    };
};

pub const Script = enum {
    curl,
};

pub const Other = struct {};

pub fn init(ua_str: []const u8) UserAgent {
    return .{
        .string = ua_str,
        .resolved = .init(ua_str),
    };
}

const Request = @import("request.zig");
//const bot = @import("bot-detection.zig");

const std = @import("std");
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const indexOf = std.mem.indexOf;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const parseInt = std.fmt.parseInt;
