//! Bot Detection
//!
//! It does something, what that something is? who know, but it's big!

bot: bool,
/// True when >= the anomaly score
malicious: bool,
score: f16,

const Robots = @This();

const default: Robots = .{
    .bot = false,
    .malicious = false,
    .score = 0.0,
};

const default_malicious: Robots = .{
    .bot = true,
    .malicious = true,
    .score = 1.0,
};

pub const ANOMALY_MAX: f16 = 0.5;
pub const BOT_DEVIANCE: f16 = 0.2;

pub fn init(r: *const Request) Robots {
    const ua: UA = r.user_agent orelse return .default_malicious;

    var bot: Robots = .default;

    inline for (rules.age) |rule| {
        rule(ua, r, &bot.score) catch @panic("not implemented");
    }

    switch (ua.agent) {
        .bot => {
            bot.bot = true;
            inline for (rules.bot) |rule| {
                rule(ua, r, &bot.score) catch @panic("not implemented");
            }
            // the score of something actively identifying itself as a bot
            // is only related to it's malfeasance
            bot.malicious = bot.score >= BOT_DEVIANCE;
        },
        .browser => |browser| {
            inline for (rules.browser) |rule| {
                rule(ua, r, &bot.score) catch @panic("not implemented");
            }
            // Any bot that masqurades as a browser is by definition malign
            if (bot.score >= ANOMALY_MAX) {
                bot.bot = true;
                bot.malicious = true;
            }
            switch (browser.name) {
                .chrome => {},
                .msie => {
                    bot.bot = true;
                    bot.malicious = true;
                },
                else => {},
            }
        },
        .script => bot.bot = true,
        .unknown => bot.malicious = startsWith(u8, ua.string, "Mozilla/"),
    }
    return bot;
}

pub const Label = enum {
    subnet_tagged_suspicious,
    subnet_tagged_hostile,
    ua_age_months,
    ua_age_years,
    headers_missing,
    headers_unexpected,
    protocol_mismatch,
};

const RuleError = error{
    Generic,
    NotABot,
};

const RuleFn = fn (UA, *const Request, *f16) RuleError!void;

const rules = struct {
    const age = [_]RuleFn{
        browsers.Rules.age,
    };
    const browser = [_]RuleFn{
        browsers.Rules.protocolVer,
        browsers.Rules.acceptStr,
    };
    const bot = [_]RuleFn{
        bots.Rules.knownSubnet,
    };
};

test Robots {
    _ = std.testing.refAllDecls(@This());
    _ = &browsers;
}

pub const RobotOptions = struct {
    default_allow: bool = true,
    delay: u16 = 0,
    extra_rules: ?[]const u8,
    customized: bool = false,

    pub const default: RobotOptions = .{
        .default_allow = true,
        .delay = 10,
        .extra_rules = null,
        .customized = false,
    };
};

pub fn robotsTxt(
    comptime robots: []const bots.TxtRules,
    comptime options: RobotOptions,
) Router.Match {
    const EP = struct {
        const delay = std.fmt.comptimePrint("Crawl-delay: {}\n", .{options.delay});
        const robot_rules: [robots.len + 1][]const u8 = brk: {
            var compiled: [robots.len + 1][]const u8 = undefined;
            for (robots, 1..) |each, i| {
                compiled[i] = "User-agent: " ++ each.name ++ "\n" ++
                    (if (each.allow) "Allow" else "Disallow") ++ ": /\n" ++
                    (if (options.extra_rules) |er| er else "") ++
                    (if (each.extra) |ex| ex else "") ++
                    (if (each.delay) "Crawl-delay: 4\n\n" else "\n");
            } else {
                compiled[0] = "User-agent: *\n" ++
                    (if (options.delay > 0) delay else "") ++
                    (if (options.extra_rules) |er| er else "") ++
                    (if (options.default_allow) "Allow: /\n\n" else "Disallow: /\n\n");
            }
            break :brk compiled;
        };
        const robots_txt: []const u8 = brk: {
            var compiled: []const u8 = "User-agent: *\n" ++
                (if (options.delay > 0) delay else "") ++
                (if (options.default_allow) "Allow: /\n" else "Disallow: /\n") ++
                (if (options.extra_rules) |er| er else "") ++
                "\n";
            for (robots) |each| {
                compiled = compiled ++
                    "User-agent: " ++ each.name ++ "\n" ++
                    (if (each.allow) "Allow" else "Disallow") ++ ": /\n" ++
                    (if (options.extra_rules) |er| er else "") ++
                    (if (each.extra) |ex| ex else "") ++
                    (if (each.delay) "Crawl-delay: 4\n\n" else "\n");
            }

            break :brk compiled;
        };

        fn respond(f: *Frame, text: []const u8) Router.Error!void {
            f.status = .ok;
            f.content_type = .@"text/plain";
            try f.sendHeaders(.close);
            try f.downstream.writer.writeAll(text);
        }

        pub fn endpoint(f: *Frame) Router.Error!void {
            return respond(f, robots_txt);
        }

        pub fn endpointCustomized(f: *Frame) Router.Error!void {
            return respond(f, robots_txt);
        }
    };

    return Router.ANY(
        "robots.txt",
        if (comptime options.customized) EP.endpointCustomized else EP.endpoint,
    );
}

test robotsTxt {
    // TODO mock a full request frame
    _ = robotsTxt(&[_]bots.TxtRules{.{ .name = "googlebot", .allow = false }}, .default);
}

pub const browsers = @import("Robots/browsers.zig");
pub const bots = @import("Robots/bots.zig");

const Router = @import("router.zig");
const Frame = @import("frame.zig");
const UA = @import("user-agent.zig");
const Request = @import("request.zig");

const std = @import("std");
const startsWith = std.mem.startsWith;
const Timestamp = std.Io.Timestamp;
