pub const Rules = struct {
    pub fn rfc9110_10_1_2(ua: UA, r: *const Request, score: *f16) !void {
        // https://www.rfc-editor.org/rfc/rfc9110#section-10.1.2

        _ = ua;
        _ = r;
        _ = score;
        if (false) {}
    }

    pub fn knownSubnet(ua: UA, r: *const Request, score: *f16) !void {
        if (ua.agent != .bot) return error.NotABot;

        if (bots.get(ua.agent.bot.name).network) |nw| {
            for (nw.nets) |net| {
                if (startsWith(u8, r.remote_addr, net)) break;
            } else {
                if (nw.exaustive) score.* = @max(score.*, 1.0);
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
};

pub const Bot = struct {
    name: Name,
    version: u32,

    pub const Name = enum {
        applebot,
        bingbot,
        claudebot,
        googlebot,
        gptbot,
        lounge_irc_client,

        malicious,
        unknown,

        pub const fields = @typeInfo(Name).@"enum".fields;
        pub const len = fields.len;
    };

    pub fn resolve(str: []const u8) ?Bot {
        if (endsWith(u8, str, "Applebot/0.1; +http://www.apple.com/go/applebot)")) {
            return .{ .name = .applebot, .version = parseVersion(str, "Applebot/") catch 0 };
        } else if (endsWith(u8, str, "Googlebot/2.1; +http://www.google.com/bot.html)")) {
            return .{ .name = .googlebot, .version = parseVersion(str, "Googlebot/") catch 0 };
        } else if (endsWith(u8, str, "compatible; ClaudeBot/1.0; +claudebot@anthropic.com)")) {
            return .{ .name = .claudebot, .version = parseVersion(str, "ClaudeBot/") catch 0 };
        } else if (indexOf(u8, str, "compatible; bingbot/2.0; +http://www.bing.com/bingbot.htm)")) |_| {
            return .{ .name = .bingbot, .version = parseVersion(str, "bingbot/") catch 0 };
        } else if (endsWith(u8, str, "compatible; GPTBot/1.2; +https://openai.com/gptbot)")) {
            return .{ .name = .gptbot, .version = parseVersion(str, "GPTBot/") catch 0 };
        } else if (eql(u8, str, "Mozilla/5.0 (compatible; The Lounge IRC Client; +https://github.com/thelounge/thelounge) facebookexternalhit/1.1 Twitterbot/1.0")) {
            return .{ .name = .lounge_irc_client, .version = 0 };
        }
        return null;
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

    pub const unknown: Bot = .{ .name = .unknown, .version = 0 };
    pub const malicious: Bot = .{ .name = .malicious, .version = 0 };
};

pub const Identity = struct {
    bot: Bot.Name,
    network: ?*const Network,
};

pub const bots: std.EnumArray(Bot.Name, Identity) = .{
    .values = [Bot.Name.len]Identity{
        .{ .bot = .applebot, .network = null },
        .{ .bot = .bingbot, .network = null },
        .{ .bot = .claudebot, .network = null },
        .{
            .bot = .googlebot,
            .network = &.{
                // Yes, I know strings are the stupid way of doing this, this is
                // "temporary"
                .nets = &[_][]const u8{"66.249"},
            },
        },
        .{ .bot = .gptbot, .network = &.{ .nets = &[_][]const u8{"74.7.227"} } }, // incomplete ip list
        .{ .bot = .lounge_irc_client, .network = null },
        .{ .bot = .malicious, .network = null },
        .{ .bot = .unknown, .network = null },
    },
};

test "bot ident order" {
    inline for (Bot.Name.fields) |bot| {
        const bot_: Bot.Name = @enumFromInt(bot.value);
        try std.testing.expectEqual(bot_, bots.get(bot_).bot);
    }
}

const UA = @import("../user-agent.zig");
const Request = @import("../Request.zig");
const std = @import("std");
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const indexOf = std.mem.indexOf;
const eql = std.mem.eql;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const parseInt = std.fmt.parseInt;
