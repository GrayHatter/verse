//! Bot Detection
//!
//! It does something, what that something is? who know, but it's big!
automated: bool,
score: f16,

pub const Browser = @import("Robots/Browser.zig");
pub const Bot = @import("Robots/Bot.zig");

const Robots = @This();

pub const default: Robots = .{
    .automated = false,
    .score = 0.0,
};

pub const default_malicious: Robots = .{
    .automated = true,
    .score = 1.0,
};

pub const ANOMALY_MAX: f16 = 0.5;
pub const BOT_DEVIANCE: f16 = 0.2;

pub fn init(r: *const Request) Robots {
    const ua: UA = r.user_agent orelse return .default_malicious;

    var robot: Robots = .default;

    inline for (rules.all) |rule|
        rule(ua, r, &robot.score);

    switch (ua.agent) {
        .bot => |bot| {
            robot.automated = true;
            if (!bot.name.isMalicious()) {
                inline for (rules.bot) |rule|
                    rule(ua, r, &robot.score);
            }

            // the score of something actively identifying itself as a bot
            // is only related to it's malfeasance
            //robot.malicious = robot.score >= BOT_DEVIANCE;
            //robot.malicious = robot.malicious or bot.malicious;
        },
        .browser => |browser| {
            inline for (rules.browser) |rule|
                rule(ua, r, &robot.score);

            // Any bot that masqurades as a browser is by definition malign
            if (robot.score >= ANOMALY_MAX) {
                robot.automated = true;
            }

            switch (browser.name) {
                inline else => |bwsr| {
                    const B = @TypeOf(bwsr);
                    inline for (comptime B.rules(bwsr)) |rule|
                        rule(ua, r, &robot.score);
                },
            }
        },
        .script => robot.automated = true,
        // Not a browser, but pretending to be one.
        .unknown => robot.score = robot.score + if (startsWith(u8, ua.string, "Mozilla/")) 1.0 else @as(f16, 0.0),
    }
    return robot;
}

pub fn isMalicious(r: *const Robots) bool {
    return r.score >= BOT_DEVIANCE;
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

pub const RuleFn = *const fn (UA, *const Request, *f16) void;

const rules = struct {
    const all: []const RuleFn = &.{
        global.exampleCom,
    };

    const browser = Browser.rules.all;
    const bot = Bot.rules.all;

    const global = struct {
        pub fn exampleCom(ua: UA, _: *const Request, score: *f16) void {
            if (findPos(u8, ua.string, 0, "example.com")) |_| {
                // I need a shovel
                score.* = score.* + 1.0;
            }
        }
    };
};

pub const RobotsTxt = struct {
    pub const Allowed = enum(u1) { deny, allow };

    const global_allow: []const u8 =
        \\User-agent: *
        \\Allow: /
        \\
        \\
    ;

    const global_disallow: []const u8 =
        \\User-agent: *
        \\Disallow: /
        \\
        \\
    ;

    pub const Rule = struct {
        bot: union(enum) {
            name: Bot.Name,
            custom: []const u8,
        },
        allow: Allowed,
        extra: ?[]const u8 = null,

        pub fn name(comptime bot: Bot.Name, comptime allow: Allowed) Rule {
            return .{ .bot = .{ .name = bot }, .allow = allow };
        }

        pub fn custom(comptime bot: []const u8, comptime allow: Allowed) Rule {
            return .{ .bot = .{ .custom = bot }, .allow = allow };
        }

        pub const Set = struct {
            allows: []const []const u8,
            disallows: []const []const u8,

            pub const empty: Set = .{
                .allows = &.{},
                .disallows = &.{},
            };

            pub const allow_all: Set = .{
                .allows = &.{"/"},
                .disallows = &.{},
            };

            pub const disallow_all: Set = .{
                .allows = &.{},
                .disallows = &.{"/"},
            };
        };
    };

    pub const Generated = struct {
        name: []const u8,
        allow: Allowed,
        extra: ?[]const u8 = null,

        pub fn named(comptime name: Bot.Name, comptime allow: Allowed) Rule {
            return .{ .name = .{ .bot = name }, .allow = allow };
        }

        pub fn custom(comptime name: []const u8, comptime allow: Allowed) Rule {
            return .{ .name = .{ .custom = name }, .allow = allow };
        }
    };

    pub const Options = struct {
        default_answer: Allowed,
        extra_rules: ?[]const u8,

        pub const default: Options = .{
            .default_answer = .allow,
            .extra_rules = null,
        };
    };

    pub const Magic = struct {
        rules: []const Rule,
        allow_full: Allowed,
        entry: *const Router.BuildFn,

        pub fn robotsTxt(comptime default_stance: Allowed, comptime rule: []const Rule) Magic {
            const MagicEndpoint = struct {
                const magic_error_string = "Write {s} failed for robots.txt. (client disconnect?)";
                const ruleset = if (default_stance == .allow) global_allow else global_disallow;

                /// Not a browser, but not a known bot
                fn respondUnknown(f: *Frame) !void {
                    f.status = .ok;
                    f.content_type = .@"text/plain";
                    try f.sendHeaders(.done);
                    f.downstream.writer.interface.writeAll(ruleset);
                }

                fn respondBot(f: *Frame) void {
                    f.status = .ok;
                    f.content_type = .@"text/plain";
                    f.sendHeaders(.done) catch {
                        log.err(magic_error_string, .{"headers"});
                        return;
                    };
                    const bot: Bot.Name = f.request.user_agent.?.agent.bot;
                    switch (bot) {
                        .googlebot => f.downstream.writer.interface.writeAll(ruleset) catch
                            log.err(magic_error_string, .{"body"}),
                    }
                }

                fn respondBrowser(f: *Frame) !void {
                    _ = f;
                }

                fn respond(f: *Frame) !void {
                    const ua: UA = f.request.user_agent orelse return respondUnknown(f);
                    return switch (ua.agent) {
                        .bot => respondBot(f),
                        .browser => respondBrowser(f),
                        .script, .unknown => respondUnknown(f),
                    };
                }
            };

            return .{
                .rules = rule,
                .allow_full = default_stance,
                .entry = MagicEndpoint.respond,
            };
        }
    };

    pub fn customTxt(comptime custom: []const u8, comptime ruleset: Rule.Set) []const u8 {
        const allows: []const u8 = comptime brk: {
            if (ruleset.allows.len == 0) break :brk &.{};
            var allows: []const u8 = &.{};

            for (ruleset.allows) |r|
                allows = allows ++ "Allow: " ++ trim(u8, r, " \t\n") ++ "\n";
            break :brk allows[0..allows.len];
        };

        const disallows: []const u8 = comptime brk: {
            if (ruleset.disallows.len == 0) break :brk &.{};
            var disallows: []const u8 = &.{};
            for (ruleset.disallows) |r|
                disallows = disallows ++ "Disallow: " ++ trim(u8, r, " \t\n") ++ "\n";
            break :brk disallows[0..disallows.len];
        };

        return std.fmt.comptimePrint(
            \\User-agent: {s}
            \\{s}{s}
            \\
        , .{ custom, allows, disallows });
    }

    pub fn botTxt(comptime name: Bot.Name, comptime ruleset: Rule.Set) []const u8 {
        return customTxt(name.robotsTxtName(), ruleset);
    }
    test botTxt {
        const text: []const u8 = comptime botTxt(.googlebot, .{ .allows = &.{"/"}, .disallows = &.{"/src"} });
        try std.testing.expectEqualStrings(
            \\User-agent: GoogleBot
            \\Allow: /
            \\Disallow: /src
            \\
            \\
        ,
            text,
        );

        // wow, there really is no other option than google is there?
        const text2: []const u8 = comptime botTxt(.bingbot, .{ .allows = &.{"/src"}, .disallows = &.{"/"} });
        try std.testing.expectEqualStrings(
            \\User-agent: Bingbot
            \\Allow: /src
            \\Disallow: /
            \\
            \\
        ,
            text2,
        );
    }

    pub fn robotsTxt(
        comptime default_dispo: Allowed,
        comptime robots: []const Rule,
        comptime _: Options,
    ) Router.Match {
        const EP = struct {
            const robot_rules: []const u8 = brk: {
                var compiled: []const u8 = &.{};
                for (robots) |each| {
                    compiled = compiled ++ switch (each.bot) {
                        .name => |bot| botTxt(
                            bot,
                            if (each.allow == .allow) .allow_all else .disallow_all,
                        ),
                        .custom => |custom| customTxt(
                            custom,
                            if (each.allow == .allow) .allow_all else .disallow_all,
                        ),
                    };
                }

                break :brk compiled;
            };

            fn respond(f: *Frame, text: []const u8) Router.Error!void {
                f.status = .ok;
                f.content_type = .@"text/plain";
                try f.sendHeaders(.done);
                try f.downstream.writer.writeAll(
                    if (comptime default_dispo == .allow)
                        global_allow
                    else
                        global_disallow,
                );
                try f.downstream.writer.writeAll(text);
            }

            pub fn endpoint(f: *Frame) Router.Error!void {
                return respond(f, robot_rules);
            }
        };

        return Router.ANY("robots.txt", EP.endpoint);
    }

    test robotsTxt {
        // TODO mock a full request frame
        var fr_resp: testing.FrameResponse = try .init(std.testing.allocator, std.testing.io);
        defer fr_resp.raze(std.testing.allocator);

        const match = robotsTxt(
            .allow,
            &.{
                .name(.googlebot, .allow),
            },
            .default,
        );
        fr_resp.frame.uri = try .init("/robots.txt");

        try fr_resp.routeTo(match);
        try std.testing.expectEqual(1, fr_resp.call_count);
        const headers, const body = try fr_resp.splitContent();
        try std.testing.expectEqualStrings("HTTP/1.1 200 OK\r\nServer: verse/0.1", headers[0..34]);
        try std.testing.expect(endsWith(u8, headers, "Content-Type: text/plain\r\n"));

        try std.testing.expectEqualStrings(
            \\User-agent: *
            \\Allow: /
            \\
            \\User-agent: GoogleBot
            \\Allow: /
            \\
            \\
        , body);
    }

    test "robotsTxt 2" {
        // TODO mock a full request frame
        var fr_resp: testing.FrameResponse = try .init(std.testing.allocator, std.testing.io);
        defer fr_resp.raze(std.testing.allocator);

        const match = robotsTxt(
            .allow,
            &.{
                .name(.googlebot, .allow),
                .name(.bingbot, .deny),
                .name(.applebot, .deny),
                .name(.metaexternalagent, .deny),
            },
            .default,
        );
        fr_resp.frame.uri = try .init("/robots.txt");

        try fr_resp.routeTo(match);
        try std.testing.expectEqual(1, fr_resp.call_count);
        const headers, const body = try fr_resp.splitContent();
        try std.testing.expectEqualStrings("HTTP/1.1 200 OK\r\nServer: verse/0.1", headers[0..34]);
        try std.testing.expect(endsWith(u8, headers, "Content-Type: text/plain\r\n"));

        try std.testing.expectEqualStrings(
            \\User-agent: *
            \\Allow: /
            \\
            \\User-agent: GoogleBot
            \\Allow: /
            \\
            \\User-agent: Bingbot
            \\Disallow: /
            \\
            \\User-agent: Applebot
            \\Disallow: /
            \\
            \\User-agent: meta-externalagent
            \\Disallow: /
            \\
            \\
        , body);
    }

    test "robotsTxt 3" {
        // TODO mock a full request frame
        var fr_resp: testing.FrameResponse = try .init(std.testing.allocator, std.testing.io);
        defer fr_resp.raze(std.testing.allocator);

        const match = robotsTxt(
            .deny,
            &.{
                .name(.bingbot, .deny),
                .name(.googlebot, .allow),
                .name(.applebot, .deny),
                .name(.metaexternalagent, .deny),
                .custom("ExaSearchBot", .deny),
                .custom("PerplexityBot", .deny),
                .custom("Reflectionbot", .deny),
                .custom("Lounge (IRC helper)", .allow),
                .custom("Keenable-User", .deny),
            },
            .default,
        );
        fr_resp.frame.uri = try .init("/robots.txt");

        try fr_resp.routeTo(match);
        try std.testing.expectEqual(1, fr_resp.call_count);
        const headers, const body = try fr_resp.splitContent();
        try std.testing.expectEqualStrings("HTTP/1.1 200 OK\r\nServer: verse/0.1", headers[0..34]);
        try std.testing.expect(endsWith(u8, headers, "Content-Type: text/plain\r\n"));

        try std.testing.expectEqualStrings(
            \\User-agent: *
            \\Disallow: /
            \\
            \\User-agent: Bingbot
            \\Disallow: /
            \\
            \\User-agent: GoogleBot
            \\Allow: /
            \\
            \\User-agent: Applebot
            \\Disallow: /
            \\
            \\User-agent: meta-externalagent
            \\Disallow: /
            \\
            \\User-agent: ExaSearchBot
            \\Disallow: /
            \\
            \\User-agent: PerplexityBot
            \\Disallow: /
            \\
            \\User-agent: Reflectionbot
            \\Disallow: /
            \\
            \\User-agent: Lounge (IRC helper)
            \\Allow: /
            \\
            \\User-agent: Keenable-User
            \\Disallow: /
            \\
            \\
        , body);
    }
};

test Robots {
    _ = &std.testing.refAllDecls(@This());
    _ = &std.testing.refAllDecls(RobotsTxt);
    _ = &RobotsTxt;
    _ = &Browser;
    _ = &Bot;
}

const Router = @import("Router.zig");
const Frame = @import("Frame.zig");
const UA = @import("UserAgent.zig");
const Request = @import("Request.zig");

const std = @import("std");
const testing = @import("testing.zig");
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const trim = std.mem.trim;
const Timestamp = std.Io.Timestamp;
const findPos = std.mem.findPos;
const log = std.log.scoped(.verse_robots);
