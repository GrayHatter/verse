//! User Agent
//!
//! Attempts to parse the user agent string provided by the client.
//! This is only the data represented by the client.
//! TODO write doc comments
string: []const u8,
resolved: Resolved,
bot_validation: if (BOTDETC_ENABLED) ?BotDetection else ?void = null,

const UserAgent = @This();

pub const BotDetection = @import("bot-detection.zig");

pub fn botDetectionDump(ua: UserAgent, r: *const Request) void {
    if (comptime !BOTDETC_ENABLED) @compileError("Bot Detection is currently disabled");

    const bd: BotDetection = ua.bot_validation orelse .init(r);
    //std.debug.print("ua detection: {s} \n", .{ua.string});
    std.debug.print("ua detection: {} \n", .{ua.resolved});
    std.debug.print("bot detection: {} \n", .{bd});
    if (ua.resolved == .browser) {
        const age = ua.resolved.browser.age() catch 0;
        std.debug.print("age: days {} seconds {}  \n", .{ @divTrunc(age, 86400), age });
    }
}

pub const Bot = BotDetection.bots.Bot;

pub const Resolved = union(enum) {
    bot: Bot,
    browser: Browser,
    script: Script,
    unknown: Other,

    pub const malicious: Resolved = .{
        .bot = .malicious,
    };

    pub fn init(str: []const u8) Resolved {
        if (startsWith(u8, str, "Mozilla/")) {
            return .mozilla(str);
        } else if (asScript(str)) |scrpt| {
            return scrpt;
        }
        return .{ .unknown = .{} };
    }

    fn mozilla(str: []const u8) Resolved {
        if (indexOf(u8, str, "Bot") orelse indexOf(u8, str, "bot")) |idx| {
            if (idx < str.len - 3) {
                switch (str[idx + 3]) {
                    '/' => return asBot(str),
                    ';', ')', ' ' => return .{ .bot = .unknown },
                    else => {},
                }
            }
        }
        return asBrowser(str);
    }

    fn asScript(str: []const u8) ?Resolved {
        if (startsWith(u8, str, "curl/")) {
            return .{ .script = .{
                .name = .curl,
                .version = parseVersion(str, "curl/") catch return null,
            } };
        } else if (startsWith(u8, str, "git/")) {
            return .{ .script = .{
                .name = .git,
                .version = parseVersion(str, "git/") catch return null,
            } };
        } else return null;
    }

    fn asBot(str: []const u8) Resolved {
        if (Bot.resolve(str)) |bot| {
            return .{ .bot = bot };
        }

        return .{ .bot = .unknown };
    }

    fn parseVersion(str: []const u8, target: []const u8) error{Invalid}!u32 {
        if (indexOf(u8, str, target)) |idx| {
            const start = idx + target.len;
            // 3 is the minimum reasonable tail for a version
            if (str.len < start + 3) return error.Invalid;
            const end = indexOfScalarPos(u8, str, start, '.') orelse return error.Invalid;
            return parseInt(u32, str[start..end], 10) catch return error.Invalid;
        } else return error.Invalid;
    }

    fn versionString(str: []const u8, target: []const u8) []const u8 {
        if (indexOf(u8, str, target)) |idx| {
            const start = idx + target.len;
            // 3 is the minimum reasonable tail for a version
            if (str.len < start + 3) return "";
            const end = indexOfScalarPos(u8, str, start, ' ') orelse str.len;
            return str[start..end];
        }
        return "";
    }

    fn guessBrowser(str: []const u8) !struct { Browser.Name, []const u8 } {
        // Because browsers can't be trusted the order here matters which
        // unfortunately means this is fragile
        const options = .{
            .{ .edge, "Edg/", "Edg/" },
            .{ .chrome, "Chrome/", "Chrome/" },
            .{ .firefox, "Firefox/", "Firefox/" },
            .{ .safari, "Safari/", "Version/" },
            .{ .msie, "MSIE ", "MSIE " },
        };

        inline for (options) |opt| {
            const name, const search, const txt = opt;
            if (indexOf(u8, str, search) != null) {
                return .{ name, txt };
            }
        }
        //log.warn("Unable to parse browser UA string '{s}'", .{str});
        return error.UnknownBrowser;
    }

    fn asBrowser(str: []const u8) Resolved {
        const name, const vsearch = guessBrowser(str) catch return .{ .browser = .unknown };
        const version = parseVersion(str, vsearch) catch return .{ .browser = .unknown };
        const vstr = versionString(str, vsearch); // catch return .{ .bot = .unknown };
        return .{
            .browser = .{
                .name = name,
                .version = version,
                .version_string = vstr,
            },
        };
    }
};

test Resolved {
    try std.testing.expectEqualDeep(Resolved{ .unknown = .{} }, Resolved.init("unknown"));

    try std.testing.expectEqualDeep(
        Resolved{ .browser = .unknown },
        Resolved.init("Mozilla/5.0"),
    );

    try std.testing.expectEqualDeep(Resolved{ .unknown = .{} }, Resolved.init("mozilla/5.0"));

    const not_google_bot = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.165 Mobile Safari/537.36";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .{
            .name = .chrome,
            .version = 134,
            .version_string = "134.0.6998.165",
        } },
        Resolved.init(not_google_bot),
    );

    const mangled_version = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/a134.0.6998.165 Mobile Safari/537.36";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .unknown },
        Resolved.init(mangled_version),
    );

    const google_bot = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.165 Mobile Safari/537.36 " ++
        "(compatible; Googlebot/2.1; +http://www.google.com/bot.html)";
    try std.testing.expectEqualDeep(
        Resolved{ .bot = .{ .name = .googlebot, .version = 2 } },
        Resolved.init(google_bot),
    );

    const fake_edge_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " ++
        "(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .{
            .name = .edge,
            .version = 114,
            .version_string = "114.0.1823.43",
        } },
        Resolved.init(fake_edge_ua),
    );

    const lin_ff = "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .{
            .name = .firefox,
            .version = 134,
            .version_string = "134.0",
        } },
        Resolved.init(lin_ff),
    );

    const msie = "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.0; Trident/5.0)";
    try std.testing.expectEqualDeep(
        Resolved{ .browser = .{
            .name = .msie,
            .version = 9,
            .version_string = "9.0;",
        } },
        Resolved.init(msie),
    );

    const git = "git/2.49.0";
    try std.testing.expectEqualDeep(
        Resolved{ .script = .{
            .name = .git,
            .version = 2,
        } },
        Resolved.init(git),
    );
}

pub const Browser = struct {
    name: Name,
    // This was a u16, but then I realized, I don't trust browsers.
    version: u32,
    version_string: []const u8 = "",

    pub const unknown: Browser = .{
        .name = .unknown,
        .version = 0,
    };

    pub const Name = enum {
        brave,
        chrome,
        edge,
        firefox,
        hastur,
        ladybird,
        opera,
        safari,
        unknown,
        // lol, ok bro
        msie,
    };

    pub fn age(b: Browser) !i64 {
        if (comptime !BOTDETC_ENABLED) @compileError("Bot Detection is currently disabled");
        const versions = BotDetection.browsers.Versions[@intFromEnum(b.name)];
        if (b.version >= versions.len) return error.UnknownVersion;
        return std.time.timestamp() - versions[b.version];
    }

    test age {
        if (!BOTDETC_ENABLED) return error.SkipZigTest;
        const browser = Browser{ .name = .chrome, .version = 134 };
        try std.testing.expect(try browser.age() < 86400 * 3650); // breaks in 10 years, good luck future me!
        try std.testing.expect(try browser.age() > 3148551);
    }
};

pub const Script = struct {
    name: Name,
    version: u32,

    pub const Name = enum {
        curl,
        git,
    };
};

pub const Other = struct {};

pub fn init(ua_str: []const u8) UserAgent {
    return .{
        .string = ua_str,
        .resolved = .init(ua_str),
        .bot_validation = null,
    };
}

pub fn validate(ua: *UserAgent, r: *const Request) !bool {
    if (!BOTDETC_ENABLED) @compileError("Bot Detection is currently disabled");
    ua.bot_validation = .init(r);

    if (ua.bot_validation.?.malicious) {
        ua.resolved = .malicious;
        return false;
    }
    return true;
}

const BOTDETC_ENABLED: bool = verse_buildopts.botdetection or builtin.is_test;

test UserAgent {
    std.testing.refAllDecls(@This());
    _ = &BotDetection;
}

const Request = @import("request.zig");

const std = @import("std");
const log = std.log.scoped(.botdetection);
const builtin = @import("builtin");
const verse_buildopts = @import("verse_buildopts");
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const indexOf = std.mem.indexOf;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const parseInt = std.fmt.parseInt;
