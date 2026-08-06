agent: [5]?[]const u8,
mobile: ?bool,
platform: ?Platform,

const ClientHints = @This();

pub const empty: ClientHints = .{
    .agent = @splat(null),
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

pub fn init(req: *const Request) !ClientHints {
    _ = req;
    return .{
        .agent = @splat(null),
        .mobile = null,
        .platform = null,
    };
}

test {
    const std = @import("std");
    _ = &std.testing.refAllDecls(@This());
}

const Request = @import("../Request.zig");
