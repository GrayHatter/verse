agent: ?Agent,
mobile: ?bool,
platform: ?Platform,

const ClientHints = @This();

pub const empty: ClientHints = .{
    .agent = null,
    .mobile = null,
    .platform = null,
};

pub const Platform = union(enum) {
    windows: []const u8,
    linux: []const u8,
    macos: []const u8,
    other: []const u8,

    pub fn init(str: []const u8) Platform {
        return .{ .other = str };
    }
};

pub const Agent = struct {
    count: usize,
    bytes: []const u8,

    pub fn init(ch_ua: []const u8) Agent {
        return .{
            .count = std.mem.countScalar(u8, ch_ua, ',') + 1, // lol, sorry!
            .bytes = ch_ua,
        };
    }
};

pub fn init(headers: *const Headers) ClientHints {
    return .{
        .agent = if (headers.getCustomValue("HTTP_SEC_CH_UA")) |v|
            .init(v)
        else |_|
            null,
        .mobile = if (headers.getCustomValue("HTTP_SEC_CH_MOBILE")) |v|
            std.mem.eql(u8, v, "?1")
        else |_|
            null,
        .platform = if (headers.getCustomValue("HTTP_SEC_CH_PLATFORM")) |v|
            .init(v)
        else |_|
            null,
    };
}

test {
    _ = &std.testing.refAllDecls(@This());
}

test Agent {
    const spam =
        \\"Google Chrome";v="141", "Not?A_Brand";v="8", "Chromium";v="141"
    ;
    try std.testing.expectEqualDeep(Agent{ .count = 3, .bytes = spam }, Agent.init(spam));
}

const Headers = @import("../Headers.zig");
const std = @import("std");
