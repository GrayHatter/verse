alloc: Allocator,
known: KnownMap,
custom: CustomMap,

const Headers = @This();

pub const KnownHeaders = enum {
    accept,
    accept_encoding,
    host,
    user_agent,
    cookies,
};

pub const Header = struct {
    name: []const u8,
    value: []const u8,
};

/// Unstable API that may get removed
pub const HeaderList = struct {
    name: []const u8,
    value_list: *ValueList,
};

const ValueList = struct {
    value: []const u8,
    next: ?*ValueList = null,
};

const KnownMap = EnumMap(KnownHeaders, []const u8);
const CustomMap = std.StringArrayHashMap(*ValueList);

pub fn init(a: Allocator) Headers {
    return .{
        .alloc = a,
        .known = KnownMap{},
        .custom = CustomMap.init(a),
    };
}

pub fn raze(h: *Headers) void {
    const values = h.custom.values();
    for (values) |val| {
        var next: ?*ValueList = val.*.next;
        h.alloc.destroy(val);
        while (next != null) {
            const destroy = next.?;
            next = next.?.next;
            h.alloc.destroy(destroy);
        }
    }
    h.custom.deinit();
}

fn normalize(_: []const u8) !void {
    comptime unreachable;
}

pub fn addCustom(h: *Headers, name: []const u8, value: []const u8) !void {
    // TODO normalize lower
    const gop = try h.custom.getOrPut(name);
    if (gop.found_existing) {
        var end: *ValueList = gop.value_ptr.*;
        while (end.*.next != null) {
            end = end.next.?;
        }
        end.next = try h.alloc.create(ValueList);
        end.next.?.value = value;
        end.next.?.next = null;
    } else {
        gop.value_ptr.* = try h.alloc.create(ValueList);
        gop.value_ptr.*.value = value;
        gop.value_ptr.*.next = null;
    }
}

pub fn getCustom(h: *const Headers, name: []const u8) ?HeaderList {
    if (h.custom.get(name)) |header| {
        return .{
            .name = name,
            .value_list = header,
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
    inner: CustomMap.Iterator,
    entry: ?CustomMap.Entry = null,
    current: ?*ValueList = null,
    current_name: ?[]const u8 = null,

    pub fn init(h: *Headers) Iterator {
        h.custom.lockPointers();
        return .{
            .header = h,
            .inner = h.custom.iterator(),
        };
    }

    pub fn next(i: *Iterator) ?Header {
        if (i.current) |current| {
            defer i.current = current.next;
            return .{
                .name = i.current_name.?,
                .value = current.value,
            };
        } else {
            i.current_name = null;
            i.entry = i.inner.next();
            if (i.entry) |entry| {
                i.current = entry.value_ptr.*;
                i.current_name = entry.key_ptr.*;
            } else {
                i.header.custom.unlockPointers();
                return null;
            }
            return i.next();
        }
    }

    /// Helper
    pub fn finish(i: *Iterator) void {
        while (i.next()) |_| {}
    }
};

pub fn toSlice(h: Headers, a: Allocator) ![]Header {
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
    var iter = h.custom.iterator();

    while (iter.next()) |next| {
        var old: ?*ValueList = next.value_ptr.*;
        while (old) |this| {
            try out.print("{s}: {s}\n", .{ next.key_ptr.*, this.value });
            old = this.next;
        }
    }
}

test Headers {
    const a = std.testing.allocator;
    var hmap = init(a);
    defer hmap.raze();
    try hmap.addCustom("first", "1");
    try hmap.addCustom("first", "2");
    try hmap.addCustom("first", "3");
    try hmap.addCustom("second", "4");

    try std.testing.expectEqual(2, hmap.custom.count());
    const first = hmap.custom.get("first");
    try std.testing.expectEqualStrings(first.?.value, "1");
    try std.testing.expectEqualStrings(first.?.next.?.value, "2");
    try std.testing.expectEqualStrings(first.?.next.?.next.?.value, "3");
    const second = hmap.custom.get("second");
    try std.testing.expectEqualStrings(second.?.value, "4");
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const EnumMap = std.EnumMap;
