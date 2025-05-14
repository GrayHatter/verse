known: KnownMap,
extended: ExtendedMap,

const Headers = @This();

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
    list: [][]const u8,
};

const KnownMap = std.EnumMap(Expected, []const u8);
const ExtendedMap = std.StringArrayHashMapUnmanaged(HeaderList);

pub fn init() Headers {
    return .{
        .known = KnownMap{},
        .extended = ExtendedMap{},
    };
}

pub fn raze(h: *Headers, a: Allocator) void {
    const values = h.extended.values();
    for (values) |val| {
        a.free(val.list);
    }
    h.extended.deinit(a);
}

fn normalize(_: []const u8) !void {
    comptime unreachable;
}

pub fn addCustom(h: *Headers, a: Allocator, name: []const u8, value: []const u8) !void {
    // TODO normalize lower
    const gop = try h.extended.getOrPut(a, name);
    const hl: *HeaderList = gop.value_ptr;
    if (gop.found_existing) {
        if (!a.resize(hl.list, hl.list.len + 1)) {
            hl.list = try a.realloc(hl.list, hl.list.len + 1);
        }
        hl.list[hl.list.len - 1] = value;
    } else {
        hl.* = .{
            .name = name,
            .list = try a.alloc([]const u8, 1),
        };
        hl.list[0] = value;
    }
}

pub fn getCustom(h: *const Headers, name: []const u8) ?HeaderList {
    // TODO fix me
    if (h.extended.get(name)) |header| {
        return .{
            .name = name,
            .list = header.list,
        };
    } else return null;
}

/// Starting an iteration will lock the map pointers, callers must complete the
/// iteration, or manually unlock internal pointers. See also: Iterator.finish();
pub fn iterator(h: *Headers) Iterator {
    return Iterator.init(h);
}

pub const Iterator = struct {
    header: *Headers,
    inner: ExtendedMap.Iterator,
    entry: ?ExtendedMap.Entry = null,
    current: ?*HeaderList = null,
    current_idx: usize = 0,

    pub fn init(h: *Headers) Iterator {
        h.extended.lockPointers();
        return .{
            .header = h,
            .inner = h.extended.iterator(),
        };
    }

    pub fn next(i: *Iterator) ?Header {
        if (i.current) |current| {
            if (i.current_idx < current.list.len) {
                defer i.current_idx += 1;
                return .{
                    .name = current.name,
                    .value = current.list[i.current_idx],
                };
            }
        }
        i.current = null;
        i.entry = i.inner.next();
        i.current_idx = 0;
        if (i.entry) |entry| {
            i.current = entry.value_ptr;
        } else {
            i.header.extended.unlockPointers();
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

pub fn format(h: Headers, comptime fmts: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
    comptime if (fmts.len > 0) @compileError("Header format string must be empty");
    var iter = h.extended.iterator();

    while (iter.next()) |next| {
        for (next.value_ptr.list) |this| {
            try out.print("{s}: {s}\n", .{ next.value_ptr.name, this });
        }
    }
}

test {
    _ = std.testing.refAllDecls(Headers);
}

test Headers {
    const a = std.testing.allocator;
    var hmap = init();
    defer hmap.raze(a);
    try hmap.addCustom(a, "first", "1");
    try hmap.addCustom(a, "first", "2");
    try hmap.addCustom(a, "first", "3");
    try hmap.addCustom(a, "second", "4");

    try std.testing.expectEqual(2, hmap.extended.count());
    const first = hmap.extended.get("first");
    try std.testing.expectEqualStrings(first.?.list[0], "1");
    try std.testing.expectEqualStrings(first.?.list[1], "2");
    try std.testing.expectEqualStrings(first.?.list[2], "3");
    const second = hmap.extended.get("second");
    try std.testing.expectEqualStrings(second.?.list[0], "4");
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const EnumMap = std.EnumMap;
