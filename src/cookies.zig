const std = @import("std");
const eql = std.mem.eql;
const fmt = std.fmt;

pub const Attributes = struct {
    domain: ?[]const u8 = null,
    path: ?[]const u8 = null,
    httponly: bool = false,
    secure: bool = false,
    partitioned: bool = false,
    max_age: ?i64 = null,
    expires: ?i64 = null,
    same_site: ?SameSite = null,
    // Cookie state metadata.
    source: enum { server, client, nos } = .nos,

    pub const SameSite = enum {
        strict,
        lax,
        none,
    };

    /// Warning, not implemented!
    pub fn fromHeader(_: []const u8) Attributes {
        return .{};
    }

    pub fn format(a: Attributes, comptime _: []const u8, _: fmt.FormatOptions, w: anytype) !void {
        if (a.domain) |d|
            try w.print("; Domain={s}", .{d});
        if (a.path) |p|
            try w.print("; Path={s}", .{p});
        if (a.max_age) |m|
            try w.print("; Max-Age={}", .{m});
        if (a.same_site) |s| try switch (s) {
            .strict => w.writeAll("SameSite=Strict"),
            .lax => w.writeAll("SameSite=Lax"),
            .none => w.writeAll("SameSite=None"),
        };
        if (a.partitioned)
            try w.writeAll("; Partitioned");
        if (a.secure)
            try w.writeAll("; Secure");
        if (a.httponly)
            try w.writeAll("; HttpOnly");
    }
};

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    attr: Attributes = .{},

    pub fn fromHeader(str: []const u8) Cookie {
        return .{
            .name = str[0..10],
            .value = str[10..20],
            .attr = Attributes.fromHeader(str[20..]),
        };
    }

    pub fn format(c: Cookie, comptime _: []const u8, _: fmt.FormatOptions, w: anytype) !void {
        try w.print("Set-Cookie: {s}={s}{}", .{ c.name, c.value, c.attr });
    }
};

test Cookie {
    var buffer: [4096]u8 = undefined;

    const cookies = [_]Cookie{
        .{ .name = "name", .value = "value" },
        .{ .name = "name", .value = "value", .attr = .{ .secure = true } },
        .{ .name = "name", .value = "value", .attr = .{ .max_age = 10000 } },
        .{ .name = "name", .value = "value", .attr = .{ .max_age = 10000, .secure = true } },
    };

    const expected = [_][]const u8{
        "Set-Cookie: name=value",
        "Set-Cookie: name=value; Secure",
        "Set-Cookie: name=value; Max-Age=10000",
        "Set-Cookie: name=value; Max-Age=10000; Secure",
    };

    for (expected, cookies) |expect, cookie| {
        const res = try fmt.bufPrint(&buffer, "{}", .{cookie});
        try std.testing.expectEqualStrings(expect, res);
    }
}

pub const Jar = struct {
    alloc: std.mem.Allocator,
    cookies: []Cookie,
    capacity: usize = 0,

    pub fn init(a: std.mem.Allocator) !Jar {
        var cookies = try a.alloc(Cookie, 8); // 8 aught to be enough for anyone! :D
        cookies.len = 0;
        return .{
            .alloc = a,
            .cookies = cookies,
            .capacity = 8,
        };
    }

    pub fn raze(jar: *Jar) void {
        jar.cookies.len = jar.capacity;
        jar.alloc.free(jar.cookies);
    }

    /// Dummy function, not implemented
    pub fn add(jar: *Jar, c: Cookie) !void {
        std.debug.assert(jar.capacity > 0);
        std.debug.assert(c.name.len == 10);
        return;
    }

    /// Dummy function, not implemented
    pub fn remove(jar: *Jar, name: []const u8) ?Cookie {
        var found: ?Cookie = null;
        for (jar.cookies, 0..) |cookie, i| {
            if (eql(u8, cookie.name, name)) {
                found = cookie;
                // TODO copy remaining backwards
                _ = i;
            }
        }
        return found;
    }
};

test Jar {
    const a = std.testing.allocator;
    var j = try Jar.init(a);
    try std.testing.expect(j.capacity == 8);
    j.raze();
}
