alloc: Allocator,
map: std.StringHashMap(*anyopaque),

const ResponseData = @This();

pub const Pair = struct {
    name: []const u8,
    data: *const anyopaque,
};

pub fn init(a: Allocator) ResponseData {
    return .{
        .alloc = a,
        .map = std.StringHashMap(*anyopaque).init(a),
    };
}

fn name(comptime T: type) []const u8 {
    return comptime switch (@typeInfo(T)) {
        .Array => |a| @typeName(a.child),
        .Pointer => |p| @typeName(p.child),
        .Struct => @typeName(T),
        else => unreachable,
    };
}

pub fn add(self: *ResponseData, data: anytype) !void {
    const copy = try self.alloc.create(@TypeOf(data));
    copy.* = data;
    try self.map.put(name(@TypeOf(data)), copy);
}

pub fn get(self: ResponseData, T: type) !T {
    if (self.map.get(@typeName(T))) |data| {
        return @as(*T, @ptrCast(@alignCast(data))).*;
    } else return error.NotFound;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
