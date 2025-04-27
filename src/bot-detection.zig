//! Bot Detection
//!
//! It does something, what that something is? who know, but it's big!

bot: bool,
/// True when >= the anomaly score
malicious: bool,
score: f16,

const BotDetection = @This();

const default: BotDetection = .{
    .bot = false,
    .malicious = false,
    .score = 0.0,
};

const default_malicious: BotDetection = .{
    .bot = true,
    .malicious = true,
    .score = 1.0,
};

pub const ANOMALY_MAX: f16 = 0.5;

pub fn init(r: *const Request) BotDetection {
    if (r.user_agent == null) return .default_malicious;
    const ua = r.user_agent.?;

    var bot: BotDetection = .default;

    inline for (rules.global) |rule| {
        rule(ua, r, &bot.score) catch @panic("not implemented");
    }

    switch (ua.resolved) {
        .bot => {
            bot.bot = true;
            inline for (rules.bots) |rule| {
                rule(ua, r, &bot.score) catch @panic("not implemented");
            }
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

const RuleError = error{
    Generic,
};

const RuleFn = fn (UA, *const Request, *f16) RuleError!void;

const rules = struct {
    const global = [_]RuleFn{
        browsers.Rules.age,
    };
    const browser = [_]RuleFn{
        browsers.Rules.protocolVer,
        browsers.Rules.acceptStr,
    };
    const bots = [_]RuleFn{
        //
    };
};

test BotDetection {
    _ = std.testing.refAllDecls(@This());
    _ = &browsers;
}

pub fn robotsTxt(
    comptime default_allow: bool,
    delay_int: comptime_int,
    comptime robots: []const bots.TxtRules,
) Router.Match {
    const EP = struct {
        const delay = std.fmt.comptimePrint("Crawl-delay: {}\n", .{delay_int});
        const robots_txt: []const u8 = brk: {
            var compiled: []const u8 = "User-agent: *\n" ++
                (if (delay_int > 0) delay else "") ++
                (if (default_allow) "Allow: /\n\n" else "Disallow: /\n\n");
            for (robots) |each| {
                compiled = compiled ++
                    "User-agent: " ++ each.name ++ "\n" ++
                    (if (each.allow) "Allow" else "Disallow") ++ ": /\n" ++
                    (if (each.delay) "Crawl-delay: 4\n\n" else "\n");
            }

            break :brk compiled;
        };

        pub fn endpoint(f: *Frame) Router.Error!void {
            f.status = .ok;
            f.content_type = .@"text/plain";
            f.sendHeaders() catch |err| switch (err) {
                error.HeadersFinished => unreachable,
                inline else => |e| return e,
            };

            try f.sendRawSlice("\r\n");
            try f.sendRawSlice(robots_txt);
        }
    };

    return Router.ANY("robots.txt", EP.endpoint);
}

test robotsTxt {
    // TODO mock a full request frame
    _ = robotsTxt(true, 4, &[_]bots.TxtRules{.{ .name = "googlebot", .allow = false }});
}

pub const browsers = @import("bot-detection/browsers.zig");
pub const bots = @import("bot-detection/bots.zig");

const Router = @import("router.zig");
const Frame = @import("frame.zig");
const UA = @import("user-agent.zig");
const Request = @import("request.zig");

const std = @import("std");
const startsWith = std.mem.startsWith;
