//! User Agent
//!
//! Attempts to parse the user agent string provided by the client.
//! This is only the data represented by the client.
//! TODO write doc comments
string: []const u8,
agent: Agent,
validation: ?Robots = if (UA_VALIDATION) null else {},

const UserAgent = @This();

pub fn dumpValidation(ua: UserAgent, r: *const Request) void {
    if (comptime !UA_VALIDATION) @compileError("Bot Detection is currently disabled");

    const bd: Robots = ua.validation orelse .init(r);
    //std.debug.print("ua detection: {s} \n", .{ua.string});
    log.err("ua detection: {}", .{ua.agent});
    log.err("bot detection: {}", .{bd});
    if (ua.agent == .browser) {
        const age: Duration = ua.agent.browser.age(r.now) catch .fromSeconds(0);
        log.err("age: days {} seconds {}", .{ @divTrunc(age.toSeconds(), 86400), age });
    }
}

pub const Agent = union(enum) {
    bot: Bot,
    browser: Browser,
    script: Script,
    unknown: void,

    pub const malicious: Agent = .{ .bot = .malicious };

    pub fn init(str: []const u8) Agent {
        if (startsWith(u8, str, "Mozilla/")) {
            return .mozilla(str);
        } else if (asScript(str)) |scrpt| {
            return scrpt;
        }
        return .{ .unknown = {} };
    }

    fn mozilla(str: []const u8) Agent {
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

    fn asScript(str: []const u8) ?Agent {
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

    fn asBot(str: []const u8) Agent {
        if (Bot.resolve(str)) |bot| return .{ .bot = bot };
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

    fn asBrowser(str: []const u8) Agent {
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

test Agent {
    try std.testing.expectEqualDeep(Agent{ .unknown = {} }, Agent.init("unknown"));

    try std.testing.expectEqualDeep(
        Agent{ .browser = .unknown },
        Agent.init("Mozilla/5.0"),
    );

    try std.testing.expectEqualDeep(Agent{ .unknown = {} }, Agent.init("mozilla/5.0"));

    const not_google_bot = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.165 Mobile Safari/537.36";
    try std.testing.expectEqualDeep(
        Agent{ .browser = .{ .name = .chrome, .version = 134, .version_string = "134.0.6998.165" } },
        Agent.init(not_google_bot),
    );

    const mangled_version = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/a134.0.6998.165 Mobile Safari/537.36";
    try std.testing.expectEqualDeep(
        Agent{ .browser = .unknown },
        Agent.init(mangled_version),
    );

    const google_bot = "Mozilla/5.0 (Linux; Android 6.0.1; Nexus 5X Build/MMB29P) " ++
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.6998.165 Mobile Safari/537.36 " ++
        "(compatible; Googlebot/2.1; +http://www.google.com/bot.html)";
    try std.testing.expectEqualDeep(
        Agent{ .bot = .{ .name = .googlebot, .version = 2 } },
        Agent.init(google_bot),
    );

    const fake_edge_ua = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 " ++
        "(KHTML, like Gecko) Chrome/114.0.0.0 Safari/537.36 Edg/114.0.1823.43";
    try std.testing.expectEqualDeep(
        Agent{ .browser = .{ .name = .edge, .version = 114, .version_string = "114.0.1823.43" } },
        Agent.init(fake_edge_ua),
    );

    const lin_ff = "Mozilla/5.0 (X11; Linux x86_64; rv:134.0) Gecko/20100101 Firefox/134.0";
    try std.testing.expectEqualDeep(
        Agent{ .browser = .{ .name = .firefox, .version = 134, .version_string = "134.0" } },
        Agent.init(lin_ff),
    );

    const msie = "Mozilla/5.0 (compatible; MSIE 9.0; Windows NT 6.0; Trident/5.0)";
    try std.testing.expectEqualDeep(
        Agent{ .browser = .{ .name = .msie, .version = 9, .version_string = "9.0;" } },
        Agent.init(msie),
    );

    const git = "git/2.49.0";
    try std.testing.expectEqualDeep(
        Agent{ .script = .{ .name = .git, .version = 2 } },
        Agent.init(git),
    );

    const gptbot = "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; GPTBot/1.2; +https://openai.com/gptbot)";
    try std.testing.expectEqualDeep(
        Agent{ .bot = .{ .name = .gptbot, .version = 1 } },
        Agent.init(gptbot),
    );

    const lounge = "Mozilla/5.0 (compatible; The Lounge IRC Client; +https://github.com/thelounge/thelounge) facebookexternalhit/1.1 Twitterbot/1.0";
    try std.testing.expectEqualDeep(
        Agent{ .bot = .{ .name = .lounge_irc_client, .version = 0 } },
        Agent.init(lounge),
    );

    const apple = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15 (Applebot/0.1; +http://www.apple.com/go/applebot)";
    try std.testing.expectEqualDeep(
        Agent{ .bot = .{ .name = .applebot, .version = 0 } },
        Agent.init(apple),
    );

    const amzn = "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; Amzn-SearchBot/0.1) Chrome/119.0.6045.214 Safari/537.36";
    try std.testing.expectEqualDeep(
        Agent{ .bot = .{ .name = .amzn_searchbot, .version = 0, .malicious = true } },
        Agent.init(amzn),
    );
}

pub const Script = struct {
    name: Name,
    version: u32,

    pub const Name = enum {
        curl,
        git,
    };
};

pub fn init(ua_str: []const u8) UserAgent {
    return .{
        .string = ua_str,
        .agent = .init(ua_str),
        .validation = null,
    };
}

pub fn validate(source: UserAgent, r: *const Request) UserAgent {
    if (!UA_VALIDATION) @compileError("User Agent Validation is disabled");
    var ua = source;
    ua.validation = .init(r);
    return ua;
}

const UA_VALIDATION: bool = verse_buildopts.ua_validation or builtin.is_test;

test UserAgent {
    std.testing.refAllDecls(@This());
    _ = &Robots;
}

const Request = @import("Request.zig");
const Browser = @import("Robots/Browser.zig");
const Robots = if (UA_VALIDATION) @import("Robots.zig") else void;
const Bot = if (UA_VALIDATION) Robots.Bot else void;

const std = @import("std");
const Duration = std.Io.Duration;
const log = std.log.scoped(.botdetection);
const builtin = @import("builtin");
const verse_buildopts = @import("verse_buildopts");
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const indexOf = std.mem.indexOf;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const parseInt = std.fmt.parseInt;
