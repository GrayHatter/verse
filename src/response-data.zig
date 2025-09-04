map: HashMap = .{},

const ResponseData = @This();

fn name(comptime T: type) []const u8 {
    return comptime switch (@typeInfo(T)) {
        .array => |a| @typeName(a.child),
        .pointer => |p| @typeName(p.child),
        .@"struct" => @typeName(T),
        else => unreachable,
    };
}

pub fn add(rd: *ResponseData, T: type, a: Allocator, data: *T) !void {
    try rd.map.put(a, name(T), data);
}

pub fn clone(rd: *ResponseData, T: type, a: Allocator, data: T) !void {
    const copy = try a.create(@TypeOf(data));
    copy.* = data;
    try rd.add(T, a, copy);
}

pub fn get(rd: ResponseData, T: type) ?*T {
    if (rd.map.get(@typeName(T))) |data| {
        return @as(*T, @ptrCast(@alignCast(data)));
    }
    return null;
}

pub fn raze(rd: *ResponseData, a: Allocator) void {
    rd.map.deinit(a);
}

test ResponseData {
    const a = std.testing.allocator;

    var rd: ResponseData = .{};
    defer rd.raze(a);

    const Type = struct {
        name: []const u8,
        number: usize,
    };

    try std.testing.expectEqual(rd.get(Type), null);
    try rd.clone(Type, a, .{ .name = "name", .number = 345 });
    const found: ?*Type = rd.get(Type);
    const expect: ?*const Type = &.{ .name = "name", .number = 345 };
    try std.testing.expectEqualDeep(expect, found);

    a.destroy(found.?);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const HashMap = std.StringHashMapUnmanaged(*anyopaque);
const eql = std.mem.eql;
