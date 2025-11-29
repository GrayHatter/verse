known: KnownMap,
extra: ExtendedMap,

const Headers = @This();

pub const empty: Headers = .{ .known = .{}, .extra = .{} };

pub const Expected = enum {
    accept,
    accept_encoding,
    accept_language,
    authorization,
    cookie,
    from,
    host,
    referer,
    user_agent,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Unstable API that may get removed
pub const HeaderList = struct {
    name: []const u8,
    list: ArrayList([]const u8),
};

const KnownMap = std.EnumMap(Expected, []const u8);
const ExtendedMap = std.StringArrayHashMapUnmanaged(HeaderList);

pub fn raze(h: *Headers, a: Allocator) void {
    const values = h.extra.values();
    for (values) |*val| {
        val.list.deinit(a);
    }
    h.extra.deinit(a);
}

fn normalize(_: []const u8) !void {
    comptime unreachable;
}

/// Caller is responsible for the lifetime of both `name` and `value`. Both must outlive
/// `Headers`
pub fn addCustom(h: *Headers, a: Allocator, name: []const u8, value: []const u8) !void {
    // TODO normalize lower
    const gop = try h.extra.getOrPut(a, name);
    const hl: *HeaderList = gop.value_ptr;
    if (gop.found_existing) {
        try hl.*.list.append(a, value);
    } else {
        hl.* = .{
            .name = name,
            .list = try .initCapacity(a, 4),
        };
        hl.list.appendAssumeCapacity(value);
    }
}

pub fn getCustom(h: *const Headers, name: []const u8) ?HeaderList {
    // TODO fix me
    if (h.extra.get(name)) |header| {
        return .{
            .name = name,
            .list = header.list,
        };
    } else return null;
}

/// Returns the value associated with the given header or an error if it's missing or there is
/// more than one header for `name`.
pub fn getCustomValue(h: *const Headers, name: []const u8) error{ Missing, MultipleValues }![]const u8 {
    // TODO fix me
    if (h.extra.get(name)) |header| {
        if (header.list.items.len == 1) {
            return header.list.items[0];
        } else if (header.list.items.len > 1) {
            return error.MultipleValues;
        }
    }
    return error.Missing;
}

/// Starting an iteration will lock the map pointers, callers must complete the
/// iteration, or manually unlock internal pointers. See also: Iterator.finish();
pub fn iterator(h: *Headers) Iterator {
    return .init(h);
}

pub const Iterator = struct {
    header: *Headers,
    inner: ExtendedMap.Iterator,
    entry: ?ExtendedMap.Entry = null,
    current: ?*HeaderList = null,
    current_idx: usize = 0,

    pub fn init(h: *Headers) Iterator {
        h.extra.lockPointers();
        return .{
            .header = h,
            .inner = h.extra.iterator(),
        };
    }

    pub fn next(i: *Iterator) ?Header {
        if (i.current) |current| {
            if (i.current_idx < current.list.items.len) {
                defer i.current_idx += 1;
                return .{
                    .name = current.name,
                    .value = current.list.items[i.current_idx],
                };
            }
        }
        i.current = null;
        i.entry = i.inner.next();
        i.current_idx = 0;
        if (i.entry) |entry| {
            i.current = entry.value_ptr;
        } else {
            i.header.extra.unlockPointers();
            return null;
        }
        return i.next();
    }

    /// Helper
    pub fn finish(i: *Iterator) void {
        while (i.next()) |_| {}
    }
};

pub fn toSlice(h: *Headers, a: Allocator) ![]Header {
    var itr = h.iterator();
    var count: usize = 0;
    while (itr.next()) |_| count += 1;

    const slice = try a.alloc(Header, count);
    itr = h.iterator();
    for (slice) |*s| {
        s.* = itr.next() orelse unreachable;
    }
    return slice;
}

pub fn fmt(h: Headers, w: *Writer) !void {
    var iter = h.extra.iterator();

    while (iter.next()) |next| {
        for (next.value_ptr.list.items) |this| {
            try w.print("{s}: {s}\r\n", .{ next.value_ptr.name, this });
        }
    }
}

test {
    _ = std.testing.refAllDecls(Headers);
}

test Headers {
    const a = std.testing.allocator;
    var hmap: Headers = .empty;
    defer hmap.raze(a);
    try hmap.addCustom(a, "first", "1");
    try hmap.addCustom(a, "first", "2");
    try hmap.addCustom(a, "first", "3");
    try hmap.addCustom(a, "second", "4");

    try std.testing.expectEqual(2, hmap.extra.count());
    const first = hmap.extra.get("first");
    try std.testing.expectEqualStrings(first.?.list.items[0], "1");
    try std.testing.expectEqualStrings(first.?.list.items[1], "2");
    try std.testing.expectEqualStrings(first.?.list.items[2], "3");
    const second = hmap.extra.get("second");
    try std.testing.expectEqualStrings(second.?.list.items[0], "4");
}

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const EnumMap = std.EnumMap;
