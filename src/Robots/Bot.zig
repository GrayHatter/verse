name: Name,
version: u32,
/// Many bots will announce as compatible with, this is that with.
requesting: ?Browser = null,

pub const unknown: Bot = .{
    .name = .unknown,
    .version = 0,
    .requesting = .unknown,
};
pub const malicious_bot: Bot = .{
    .name = .other_malicious,
    .version = 0,
};

const Bot = @This();

pub const Name = enum {
    /// Ignores robots.txt
    abliterantbot,
    /// Ignores robots.txt
    amzn_searchbot,
    /// Very agressive
    applebot,
    /// Ignores robots.txt, but isn't considered malicious here because
    /// Archive.org has a reputation for going out of their way to be extremely
    /// ethical, and a good web citizen.
    archiveorgbot,
    /// Currently obviously unmaintained
    bingbot,
    /// AI bot
    claude_searchbot,
    /// AI bot
    claudebot,
    /// Link/OpenGraph scanner. Allowed, and expected to ignore robots.tit
    discordbot,
    /// https://elevenlabs.io/docs/bots
    /// buys/sells data, or crawls unidentified.
    elevenlabscrawler,
    googlebot,
    /// AI bot
    gptbot,
    /// Link/OpenGraph scanner. Allowed, and expected to ignore robots.tit
    lounge_irc_client,
    /// repeatedly breaks in ways harmful to sites.
    metaexternalagent,
    /// AI bot (link/contact doesn't resolve)
    reflectionbot,
    /// AI bot, malicious; (ignores robots.txt, repeated retries on 502)
    scrybot,
    techspybot,
    /// Ignores robots.txt
    youbot,

    /// Implementation when unable to ID a bot with suspicious traffic.
    other_malicious,
    unknown,

    pub fn isMalicious(n: Name) bool {
        return switch (n) {
            .abliterantbot => true, // ignores robots.txt
            .amzn_searchbot => true, // ignores robots.txt
            .applebot => false,
            .archiveorgbot => false,
            .bingbot => false,
            .claude_searchbot => true,
            .claudebot => true,
            .elevenlabscrawler => true, // buys data, or fails to ident
            .googlebot => false,
            .gptbot => false,
            .metaexternalagent => true, // buggy crawler that can't behave
            .techspybot => true, // non-responsive to contact
            .reflectionbot => true, // sends broken data
            .scrybot => true, // non-responsive to contact
            .youbot => true, // non-responsive to contact

            // robots.txt doesn't apply so returns a friendly name
            .discordbot => false,
            .lounge_irc_client => false,
            .other_malicious => true,
            .unknown => false, // assume good faith :/
        };
    }

    pub fn robotsTxtName(n: Name) [:0]const u8 {
        return switch (n) {
            .abliterantbot => "AbliterantBot",
            .amzn_searchbot => "Amzn-SearchBot",
            .applebot => "Applebot",
            .archiveorgbot => "archive.org_bot",
            .bingbot => "Bingbot",
            .claude_searchbot => "Claude-SearchBot",
            .claudebot => "ClaudeBot",
            .elevenlabscrawler => "ElevenlabsCrawler",
            .googlebot => "GoogleBot",
            .gptbot => "GPTBot",
            .metaexternalagent => "meta-externalagent",
            .techspybot => "TechSpyBot",
            .reflectionbot => "Reflectionbot",
            .scrybot => "ScryBot",
            .youbot => "YouBot",

            // robots.txt doesn't apply so returns a friendly name
            .discordbot => "DiscordBot",
            .lounge_irc_client => "Lounge (IRC helper)",
            .other_malicious => "Malicious Bot",
            .unknown => "Other Unknown Bot",
        };
    }

    pub fn rules(comptime name: Name) []const Robots.RuleFn {
        return switch (name) {
            .abliterantbot => "AbliterantBot",
            .amzn_searchbot => "Amzn-SearchBot",
            .applebot => "Applebot",
            .archiveorgbot => "archive.org_bot",
            .bingbot => "Bingbot",
            .claude_searchbot => "Claude-SearchBot",
            .claudebot => "ClaudeBot",
            .discordbot => "DiscordBot",
            .elevenlabscrawler => "ElevenlabsCrawler",
            .googlebot => "GoogleBot",
            .gptbot => "GPTBot",
            .metaexternalagent => "meta-externalagent",
            .techspybot => "TechSpyBot",
            .reflectionbot => "Reflectionbot",
            .scrybot => "ScryBot",
            .youbot => "YouBot",

            .lounge_irc_client => "",
            .other_malicious => "",
            .unknown => "",
        };
    }

    pub fn obeysCrawlDelay(comptime name: Name) bool {
        return switch (name) {
            // ignores robots
            .abliterantbot => false,
            // Unverified
            .amzn_searchbot => false,
            // Unverified
            .applebot => false,
            // Unverified
            .archiveorgbot => false,
            // Unverified
            .bingbot => false,
            // Unverified
            .claude_searchbot => false,
            // Unverified
            .claudebot => false,
            // Allowed to ignore robots.txt
            .discordbot => false,
            // Unverified
            .googlebot => false,
            // Unverified
            .gptbot => false,
            // Unverified
            .metaexternalagent => false,
            // Unverified
            .techspybot => false,
            // Unverified
            .scrybot => false,
            // Unverified
            .youbot => false,

            .lounge_irc_client => false,
            .other_malicious => false,
            .unknown => false,
        };
    }

    pub fn ident(comptime name: Name, str: []const u8) bool {
        return switch (name) {
            .abliterantbot => find(u8, str, "AbliterantBot/0.1 (+https://abliterant.ai)") != null,
            .amzn_searchbot => find(u8, str, "Amzn-SearchBot/") != null,
            .applebot => endsWith(u8, str, "Applebot/0.1; +http://www.apple.com/go/applebot)"),
            .bingbot => find(u8, str, "compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)") != null,
            .claude_searchbot => endsWith(u8, str, "compatible; Claude-SearchBot/1.0; +claudebot@anthropic.com)"),
            .claudebot => endsWith(u8, str, "compatible; ClaudeBot/1.0; +claudebot@anthropic.com)"),
            .discordbot => eql(u8, str, "Mozilla/5.0 (compatible; Discordbot/2.0; +https://discordapp.com)"),
            .elevenlabscrawler => find(u8, str, "ElevenlabsCrawler") != null,
            .googlebot => endsWith(u8, str, "Googlebot/2.1; +http://www.google.com/bot.html)"),
            .gptbot => endsWith(u8, str, "compatible; GPTBot/1.2; +https://openai.com/gptbot)"),
            .lounge_irc_client => eql(u8, str, "Mozilla/5.0 (compatible; The Lounge IRC Client; +https://github.com/thelounge/thelounge) facebookexternalhit/1.1 Twitterbot/1.0"),
            .metaexternalagent => eql(u8, str, "meta-externalagent/1.1 (+https://developers.facebook.com/docs/sharing/webmasters/crawler)"),
            .reflectionbot => find(u8, str, "Mozilla/5.0 (compatible; Reflectionbot/1.0; +https://reflection.ai/bot)") != null,
            .scrybot => startsWith(u8, str, "ScryBot/1.0 (+https://scry.io; ethical public-content crawler)"),
            .youbot => startsWith(u8, str, "Mozilla/5.0 AppleWebKit/537.36 (KHTML, like Gecko; compatible; YouBot/1.0"),
            .techspybot => false,
            .archiveorgbot => false,
            .other_malicious => false,
            .unknown => false,
        };
    }

    test {
        _ = &std.testing.refAllDecls(@This());
    }
};

pub fn resolve(str: []const u8) ?Bot {
    if (Name.abliterantbot.ident(str)) {
        return .{ .name = .abliterantbot, .version = parseVersion(str, "AbliterantBot/") catch 0 };
    } else if (Name.amzn_searchbot.ident(str)) {
        return .{ .name = .amzn_searchbot, .version = parseVersion(str, "Amzn-SearchBot/") catch 0 };
    } else if (Name.applebot.ident(str)) {
        return .{ .name = .applebot, .version = parseVersion(str, "Applebot/") catch 0 };
    } else if (Name.googlebot.ident(str)) {
        return .{ .name = .googlebot, .version = parseVersion(str, "Googlebot/") catch 0 };
    } else if (Name.claudebot.ident(str)) {
        return .{ .name = .claudebot, .version = parseVersion(str, "ClaudeBot/") catch 0 };
    } else if (Name.claude_searchbot.ident(str)) {
        return .{ .name = .claude_searchbot, .version = parseVersion(str, "Claude-SearchBot/") catch 0 };
    } else if (Name.bingbot.ident(str)) {
        return .{ .name = .bingbot, .version = parseVersion(str, "bingbot/") catch 0 };
    } else if (Name.elevenlabscrawler.ident(str)) {
        return .{ .name = .elevenlabscrawler, .version = parseVersion(str, "ElevenlabsCrawler/") catch 0 };
    } else if (Name.gptbot.ident(str)) {
        return .{ .name = .gptbot, .version = parseVersion(str, "GPTBot/") catch 0 };
    } else if (Name.scrybot.ident(str)) {
        return .{ .name = .scrybot, .version = parseVersion(str, "ScryBot/") catch 0 };
    } else if (Name.metaexternalagent.ident(str)) {
        return .{ .name = .metaexternalagent, .version = 1 };
    } else if (Name.reflectionbot.ident(str)) {
        return .{ .name = .reflectionbot, .version = 1 };
    } else if (Name.discordbot.ident(str)) {
        return .{ .name = .discordbot, .version = 2 };
    } else if (Name.lounge_irc_client.ident(str)) {
        return .{ .name = .lounge_irc_client, .version = 0 };
    } else if (Name.youbot.ident(str)) {
        return .{ .name = .youbot, .version = parseVersion(str, "YouBot/") catch 0 };
    }
    return null;
}

fn parseVersion(str: []const u8, comptime target: []const u8) error{Invalid}!u32 {
    if (find(u8, str, target)) |idx| {
        const start = idx + target.len;
        // 3 is the minimum reasonable tail for a version
        if (str.len < start + 3) return error.Invalid;
        const end = findScalarPos(u8, str, start, '.') orelse return error.Invalid;
        return parseInt(u32, str[start..end], 10) catch return error.Invalid;
    } else return error.Invalid;
}

pub const rules = struct {
    pub const all: []const Robots.RuleFn = &.{
        rules.knownSubnet,
        rules.expectedLanguages,
        rules.expectedParamDepth,
    };

    pub fn rfc9110_10_1_2(ua: UserAgent, r: *const Request, score: *f16) void {
        // https://www.rfc-editor.org/rfc/rfc9110#section-10.1.2

        _ = ua;
        _ = r;
        _ = score;
        if (false) {}
    }

    pub fn knownSubnet(ua: UserAgent, r: *const Request, score: *f16) void {
        if (ua.agent != .bot) return;

        if (bots.get(ua.agent.bot.name).network) |nw| {
            for (nw.nets) |net| {
                if (startsWith(u8, r.remote_addr, net)) break;
            } else {
                if (nw.exaustive) score.* = @max(score.*, 1.0);
            }
        }
    }

    /// Experimental rule that has high strength as a heuristic. Currently
    /// unimplemented as without a feedback mechanism it's specificity is too
    /// low, and introduces unwelcome bias & noise.
    pub fn expectedLanguages(ua: UserAgent, r: *const Request, score: *f16) void {
        _ = ua;
        _ = r;
        _ = score;
    }

    pub fn expectedParamDepth(ua: UserAgent, r: *const Request, score: *f16) void {
        acceptEncodingDepth(ua, r, score);
    }

    /// All browsers accept all 4 (order is high signal as well)
    fn acceptEncodingDepth(_: UserAgent, r: *const Request, score: *f16) void {
        var add: f16 = 0.3;

        if (r.accept.encoding) |encode| {
            if (encode.br) add -= 0.1;
            if (encode.deflate) add -= 0.1;
            if (encode.zstd) add -= 0.1;
            if (encode.gzip) add -= 0.1;
        } else add += 1.0;

        score.* = score.* + add;
    }

    fn secClientHints(ua: UserAgent, r: *const Request, score: *f16) void {
        secClientHintsUA(ua, r, score);
    }

    fn secClientHintsUA(_: UserAgent, r: *const Request, score: *f16) void {
        if (r.headers.getCustom("HTTP_SEC_CH_UA")) |list| {
            if (list.list.items.len > 1) {
                score.* +|= 0.5;
                return;
            }
            if (startsWith(u8, list.list.items[0], "\"Not_A Brand\";v=\"")) {
                score.* +|= 0.5;
            }
        }
    }
};

pub const TxtRules = struct {
    name: []const u8,
    allow: bool,
    delay: bool = false,
    extra: ?[]const u8 = null,
};

/// This isn't the final implementation, I'm just demoing some ideas
pub const Network = struct {
    nets: []const []const u8,
    exaustive: bool = true,

    pub const cloud_gcp: Network = .{
        .nets = &.{
            "35.224.0.0/12",
            "35.240.0.0/13",
            "35.208.0.0/12",
        },
        .exaustive = false,
    };
};

pub const Identity = struct {
    bot: Bot.Name,
    network: ?Network,
};

pub const bots: std.EnumArray(Name, Identity) = .{
    .values = [@typeInfo(Name).@"enum".field_names.len]Identity{
        .{ .bot = .abliterantbot, .network = null },
        .{ .bot = .amzn_searchbot, .network = null },
        .{ .bot = .applebot, .network = null },
        .{ .bot = .archiveorgbot, .network = null },
        .{ .bot = .bingbot, .network = null },
        .{ .bot = .claude_searchbot, .network = null },
        .{ .bot = .claudebot, .network = null },
        .{ .bot = .discordbot, .network = .cloud_gcp },
        .{ .bot = .elevenlabscrawler, .network = null },
        .{ .bot = .googlebot, .network = .{ .nets = &[_][]const u8{"66.249"} } },
        .{ .bot = .gptbot, .network = .{ .nets = &[_][]const u8{"74.7.227"} } }, // incomplete ip list
        .{ .bot = .lounge_irc_client, .network = null },
        .{ .bot = .metaexternalagent, .network = null },
        .{ .bot = .reflectionbot, .network = null },
        .{ .bot = .scrybot, .network = null },
        .{ .bot = .techspybot, .network = null },
        .{ .bot = .youbot, .network = .{ .nets = &[_][]const u8{"68.67.112"} } }, // incomplete ip list
        // Split ordering
        .{ .bot = .other_malicious, .network = null },
        .{ .bot = .unknown, .network = null },
    },
};

test {
    _ = &std.testing.refAllDecls(@This());
}

test "bot ident order" {
    const E = @typeInfo(Bot.Name).@"enum";
    inline for (E.field_values) |value| {
        const bot_: Bot.Name = @fromBackingInt(@intCast(value));
        try std.testing.expectEqual(bot_, bots.get(bot_).bot);
    }
}

const Browser = @import("Browser.zig");
const Request = @import("../Request.zig");
const Robots = @import("../Robots.zig");
const UserAgent = @import("../UserAgent.zig");
const std = @import("std");
const endsWith = std.mem.endsWith;
const eql = std.mem.eql;
const find = std.mem.find;
const findScalarPos = std.mem.findScalarPos;
const startsWith = std.mem.startsWith;
const parseInt = std.fmt.parseInt;
