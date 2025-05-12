pub const Attributes = struct {
    domain: ?[]const u8 = null,
    path: ?[]const u8 = null,
    httponly: bool = false,
    secure: bool = false,
    partitioned: bool = false,
    expires: ?i64 = null,
    same_site: ?SameSite = null,

    // TODO come up with a better hack than this one
    max_age_str: ?[]const u8 = null,
    //max_age: ?i64 = null,

    pub const SameSite = enum {
        strict,
        lax,
        none,
    };

    /// vec must be large enough for the largest cookie (10)
    pub fn writeVec(a: Attributes, vec: []IOVec) !usize {
        var used: usize = 0;
        if (a.domain) |d| {
            vec[used] = .{ .base = "; Domain=", .len = 9 };
            used += 1;
            vec[used] = .{ .base = d.ptr, .len = d.len };
            used += 1;
        }
        if (a.path) |p| {
            vec[used] = .{ .base = "; Path=", .len = 7 };
            used += 1;
            vec[used] = .{ .base = p.ptr, .len = p.len };
            used += 1;
        }
        if (a.max_age_str) |str| {
            vec[used] = .{ .base = "; Max-Age=".ptr, .len = 10 };
            used += 1;
            vec[used] = .{ .base = str.ptr, .len = str.len };
            used += 1;
        }

        if (a.same_site) |s| {
            vec[used] = switch (s) {
                .strict => .{ .base = "; SameSite=Strict", .len = 17 },
                .lax => .{ .base = "; SameSite=Lax", .len = 14 },
                .none => .{ .base = "; SameSite=None", .len = 15 },
            };
            used += 1;
        }
        if (a.partitioned) {
            vec[used] = .{ .base = "; Partitioned", .len = 13 };
            used += 1;
        }
        if (a.secure) {
            vec[used] = .{ .base = "; Secure", .len = 8 };
            used += 1;
        }
        if (a.httponly) {
            vec[used] = .{ .base = "; HttpOnly", .len = 10 };
            used += 1;
        }
        std.debug.assert(used <= 10);
        return used;
    }

    pub fn format(a: Attributes, comptime _: []const u8, _: fmt.FormatOptions, w: anytype) !void {
        if (a.domain) |d| try w.print("; Domain={s}", .{d});
        if (a.path) |p| try w.print("; Path={s}", .{p});
        if (a.max_age_str) |m| try w.print("; Max-Age={s}", .{m});
        if (a.same_site) |s| try switch (s) {
            .strict => w.writeAll("; SameSite=Strict"),
            .lax => w.writeAll("; SameSite=Lax"),
            .none => w.writeAll("; SameSite=None"),
        };
        if (a.partitioned) try w.writeAll("; Partitioned");
        if (a.secure) try w.writeAll("; Secure");
        if (a.httponly) try w.writeAll("; HttpOnly");
    }
};

pub const Cookie = struct {
    name: []const u8,
    value: []const u8,
    attr: Attributes = .{},
    // Cookie state metadata.
    source: enum { server, client, nos } = .nos,

    pub fn fromHeader(cookie: []const u8) Cookie {
        const split = indexOfScalar(u8, cookie, '=') orelse cookie.len - 1;
        return .{
            .name = cookie[0..split],
            .value = cookie[split + 1 ..],
            .source = .client,
            .attr = .{},
        };
    }

    /// vec must be large enough for the largest cookie (4 + attributes)
    pub fn writeVec(c: Cookie, vec: []IOVec) !usize {
        if (vec.len < 12) return error.NoSpaceLeft;
        var used: usize = 0;
        vec[used] = .{ .base = "Set-Cookie: ".ptr, .len = 12 };
        used += 1;
        vec[used] = .{ .base = c.name.ptr, .len = c.name.len };
        used += 1;
        vec[used] = .{ .base = "=".ptr, .len = 1 };
        used += 1;
        vec[used] = .{ .base = c.value.ptr, .len = c.value.len };
        used += 1;
        std.debug.assert(used <= 4);
        used += try c.attr.writeVec(vec[4..]);

        return used;
    }

    pub fn format(c: Cookie, comptime fstr: []const u8, _: fmt.FormatOptions, w: anytype) !void {
        if (comptime eql(u8, fstr, "header")) {
            try w.writeAll("Set-Cookie: ");
        }
        try w.print("{s}={s}{}", .{ c.name, c.value, c.attr });
    }
};

test Cookie {
    var buffer: [4096]u8 = undefined;

    const cookies = [_]Cookie{
        .{ .name = "name", .value = "value" },
        .{ .name = "name", .value = "value", .attr = .{ .secure = true } },
        .{ .name = "name", .value = "value", .attr = .{ .max_age_str = "10000" } },
        .{ .name = "name", .value = "value", .attr = .{ .max_age_str = "10000", .secure = true } },
    };

    const expected = [_][]const u8{
        "Set-Cookie: name=value",
        "Set-Cookie: name=value; Secure",
        "Set-Cookie: name=value; Max-Age=10000",
        "Set-Cookie: name=value; Max-Age=10000; Secure",
    };

    for (expected, cookies) |expect, cookie| {
        const res = try fmt.bufPrint(&buffer, "{header}", .{cookie});
        try std.testing.expectEqualStrings(expect, res);
    }

    const v_expct = [4]IOVec{
        .{ .base = "Set-Cookie: ", .len = 12 },
        .{ .base = "name", .len = 4 },
        .{ .base = "=", .len = 1 },
        .{ .base = "value", .len = 5 },
    };

    var v_buf: [14]IOVec = undefined;
    const used = try cookies[0].writeVec(v_buf[0..]);
    try std.testing.expectEqual(4, used);
    try std.testing.expectEqualDeep(v_expct[0..4], v_buf[0..4]);
}

pub const Jar = struct {
    alloc: Allocator,
    cookies: ArrayListUnmanaged(Cookie),

    /// Creates a new jar.
    pub fn init(a: Allocator) !Jar {
        const cookies = try ArrayListUnmanaged(Cookie).initCapacity(a, 8);
        return .{
            .alloc = a,
            .cookies = cookies,
        };
    }

    pub fn initFromHeader(a: Allocator, header: []const u8) !Jar {
        var jar = try init(a);
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
                .value = try fmt.allocPrint(a, "{}", .{cookie}),
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
    var j = try Jar.init(a);
    defer j.raze();

    const cookies = [_]Cookie{
        .{ .name = "cookie1", .value = "value" },
        .{ .name = "cookie2", .value = "value", .attr = .{ .secure = true } },
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

const Headers = @import("headers.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const fmt = std.fmt;
const indexOf = std.mem.indexOf;
const indexOfScalar = std.mem.indexOfScalar;
const splitSequence = std.mem.splitSequence;
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const IOVec = @import("iovec.zig").IOVec;
