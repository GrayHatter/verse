pub const Rules = struct {
    pub fn rfc9110_10_1_2(ua: UA, r: *const Request, score: *f16) !void {
        // https://www.rfc-editor.org/rfc/rfc9110#section-10.1.2

        _ = ua;
        _ = r;
        _ = score;
        if (false) {}
    }

    pub fn knownSubnet(ua: UA, r: *const Request, score: *f16) !void {
        if (ua.resolved != .bot) return error.NotABot;

        if (bots.get(ua.resolved.bot.name).network) |nw| {
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
};

/// This isn't the final implementation, I'm just demoing some ideas
pub const Network = struct {
    nets: []const []const u8,
    exaustive: bool = true,
};

pub const Identity = struct {
    bot: Bots,
    network: ?Network,
};

pub const Bots = enum {
    googlebot,
    unknown,

    pub const fields = @typeInfo(Bots).@"enum".fields;
    pub const len = fields.len;
};

pub const bots: std.EnumArray(Bots, Identity) = .{
    .values = [Bots.len]Identity{
        .{
            .bot = .googlebot,
            .network = Network{
                // Yes, I know strings are the stupid way of doing this, this is
                // "temporary"
                .nets = &[_][]const u8{
                    "66.249",
                },
            },
        },
        .{ .bot = .unknown, .network = null },
    },
};

const UA = @import("../user-agent.zig");
const Request = @import("../request.zig");
const std = @import("std");
const startsWith = std.mem.startsWith;
