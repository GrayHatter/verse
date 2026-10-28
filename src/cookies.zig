pub const Attributes = struct {
    domain: ?[]const u8,
    http_only: bool,
    max_age: ?i64,
    partitioned: bool,
    path: ?[]const u8,
    same_site: SameSite,
    secure: bool,

    pub const default: Attributes = .{
        .domain = null,
        .http_only = true,
        .max_age = null,
        .partitioned = false,
        .path = null,
        .same_site = .unset,
        .secure = true,
    };

    pub const strict: Attributes = .{
        .domain = null,
        .http_only = true,
        .max_age = null,
        .partitioned = false,
        .path = null,
        .same_site = .strict,
        .secure = true,
    };

    pub const lax: Attributes = .{
        .domain = null,
        .http_only = true,
        .max_age = null,
        .partitioned = false,
        .path = null,
        .same_site = .lax,
        .secure = true,
    };

    pub const session: Attributes = .{
        .domain = null,
        .http_only = true,
        .max_age = null,
        .partitioned = false,
        .path = null,
        .same_site = .strict,
        .secure = true,
    };

    //pub const default: Attributes = .{};
    //pub const default: Attributes = .{};
    //pub const default: Attributes = .{};

    pub const SameSite = enum {
        unset,
        strict,
        lax,
        none,
    };

    pub fn age(seconds: i64) Attributes {
        var attr: Attributes = .default;
        attr.max_age = seconds;
        return attr;
    }

    pub fn format(a: Attributes, w: *Writer) !void {
        try switch (a.same_site) {
            .strict => w.writeAll("; SameSite=Strict"),
            .unset => {}, // equiv to lax
            .lax => w.writeAll("; SameSite=Lax"),
            .none => w.writeAll("; SameSite=None"),
        };
        if (a.max_age) |m| try w.print("; Max-Age={d}", .{m});
        if (a.secure or a.partitioned) try w.writeAll("; Secure");
        if (a.domain) |d| try w.print("; Domain={s}", .{d});
        if (a.path) |p| try w.print("; Path={s}", .{p});
        if (a.http_only) try w.writeAll("; HttpOnly");
        if (a.partitioned) try w.writeAll("; Partitioned");
    }
};

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    attr: Attributes = .default,
    // Cookie state metadata.
    source: enum { server, client, nos } = .nos,

    pub fn new(name: []const u8, value: []const u8, attr: Attributes) Cookie {
        return .{
            .name = name,
            .value = value,
            .attr = attr,
            .source = .server,
        };
    }

    pub fn fromHeader(cookie: []const u8) Cookie {
        const split = indexOfScalar(u8, cookie, '=') orelse cookie.len - 1;
        return .{
            .name = cookie[0..split],
            .value = cookie[split + 1 ..],
            .source = .client,
        };
    }

    pub fn header(c: Cookie, w: *Writer) !void {
        try w.writeAll("Set-Cookie: ");

        try w.print("{s}={s}{f}", .{ c.name, c.value, c.attr });
    }

    pub fn format(c: Cookie, w: *Writer) !void {
        try w.print("{s}={s}{f}", .{ c.name, c.value, c.attr });
    }
};

test Cookie {
    var buffer: [4096]u8 = undefined;

    const cookies = [_]Cookie{
        .{ .name = "name", .value = "value", .attr = .default },
        .{ .name = "name", .value = "value" },
        .{ .name = "name", .value = "value", .attr = .{
            .secure = true,
            .max_age = null,
            .http_only = false,
            .domain = null,
            .path = null,
            .same_site = .unset,
            .partitioned = false,
        } },
        .{ .name = "name", .value = "value", .attr = .strict },
        .{ .name = "name", .value = "value", .attr = .age(10000) },
        .{ .name = "name", .value = "value", .attr = .age(0) },
        .new("other", "cookie", .session),
        .new("other", "cookie", .default),
        .new("other", "cookie", .lax),
        .new("other", "cookie", .age(10)),
    };

    const expected = [_][]const u8{
        "Set-Cookie: name=value; Secure; HttpOnly",
        "Set-Cookie: name=value; Secure; HttpOnly",
        "Set-Cookie: name=value; Secure",
        "Set-Cookie: name=value; SameSite=Strict; Secure; HttpOnly",
        "Set-Cookie: name=value; Max-Age=10000; Secure; HttpOnly",
        "Set-Cookie: name=value; Max-Age=0; Secure; HttpOnly",
        "Set-Cookie: other=cookie; SameSite=Strict; Secure; HttpOnly",
        "Set-Cookie: other=cookie; Secure; HttpOnly",
        "Set-Cookie: other=cookie; SameSite=Lax; Secure; HttpOnly",
        "Set-Cookie: other=cookie; Max-Age=10; Secure; HttpOnly",
    };

    for (expected, cookies) |expect, cookie| {
        const res = try fmt.bufPrint(&buffer, "{f}", .{std.fmt.alt(cookie, .header)});
        try std.testing.expectEqualStrings(expect, res);
    }
}

pub const Jar = struct {
    alloc: Allocator,
    cookies: ArrayList(Cookie),

    /// Creates a new jar.
    pub fn init(a: Allocator) Jar {
        return .{ .alloc = a, .cookies = .empty };
    }

    pub fn initFromHeader(a: Allocator, header: []const u8) !Jar {
        var jar: Jar = .init(a);
        var cookies = splitSequence(u8, header, "; ");
        while (cookies.next()) |cookie| {
            try jar.add(Cookie.fromHeader(cookie));
        }

        return jar;
    }

    pub fn raze(jar: *Jar) void {
        jar.cookies.deinit(jar.alloc);
    }

    /// Adds a cookie to the jar.
    pub fn add(jar: *Jar, c: Cookie) !void {
        try jar.cookies.append(jar.alloc, c);
    }

    /// Only returns the first cookie with this name
    pub fn get(jar: *const Jar, name: []const u8) ?Cookie {
        for (jar.cookies.items) |cookie| {
            if (eql(u8, cookie.name, name)) {
                return cookie;
            }
        }

        return null;
    }

    /// Remove a cookie from the jar by name.
    ///
    /// TODO: cookie names don't need to be unique; but swap remove might skip
    /// removing a cookie if only one exists.
    pub fn remove(jar: *Jar, name: []const u8) ?Cookie {
        var found: ?Cookie = null;

        for (jar.cookies.items, 0..) |cookie, i| {
            if (eql(u8, cookie.name, name)) {
                found = jar.cookies.swapRemove(i);
            }
        }

        return found;
    }

    /// Caller owns the array, and each name and value string
    pub fn toHeaderSlice(jar: *Jar, a: Allocator) ![]Headers.Header {
        const slice = try a.alloc(Headers.Header, jar.cookies.items.len);
        for (slice, jar.cookies.items) |*s, cookie| {
            s.* = .{
                .name = try a.dupe(u8, "Set-Cookie"),
                .value = try fmt.allocPrint(a, "{f}", .{cookie}),
            };
        }
        return slice;
    }

    /// Reduces size of cookies to it's current length.
    pub fn shrink(jar: *Jar) void {
        jar.cookies.shrinkAndFree(jar.alloc, jar.cookies.len);
    }
};

test Jar {
    const a = std.testing.allocator;
    var j: Jar = .init(a);
    defer j.raze();

    const cookies = [_]Cookie{
        .{ .name = "cookie1", .value = "value" },
        .{ .name = "cookie2", .value = "value", .attr = .default },
    };

    for (cookies) |cookie| {
        try j.add(cookie);
    }

    try std.testing.expectEqual(j.cookies.items.len, 2);

    const removed = j.remove("cookie1");
    try std.testing.expect(removed != null);
    try std.testing.expectEqualStrings(removed.?.name, "cookie1");

    try std.testing.expectEqual(j.cookies.items.len, 1);
}

const Headers = @import("Headers.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const fmt = std.fmt;
const indexOf = std.mem.indexOf;
const indexOfScalar = std.mem.indexOfScalar;
const splitSequence = std.mem.splitSequence;
const ArrayList = std.ArrayList;
const Writer = std.Io.Writer;
