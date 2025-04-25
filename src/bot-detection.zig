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
    };
    const bots = [_]RuleFn{
        //
    };
};

pub const browsers = @import("bot-detection/browsers.zig");

test BotDetection {
    _ = std.testing.refAllDecls(@This());
    _ = &browsers;
}

const std = @import("std");
const UA = @import("user-agent.zig");
const Request = @import("request.zig");
const startsWith = std.mem.startsWith;
