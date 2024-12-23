//! Client Request Data
const Data = @This();

post: ?PostData,
query: QueryData,

pub fn validate(data: Data, comptime T: type) !T {
    return RequestData(T).init(data);
}

/// This is the preferred api to use... once it actually exists :D
pub fn Validator(comptime T: type) type {
    return struct {
        data: T,

        const Self = @This();

        pub fn init(data: T) Self {
            return Self{
                .data = data,
            };
        }

        pub fn count(v: *Self, name: []const u8) usize {
            var i: usize = 0;
            for (v.data.items) |item| {
                if (eql(u8, item.name, name)) i += 1;
            }
            return i;
        }

        pub fn require(v: *Self, name: []const u8) !DataItem {
            return v.optional(name) orelse error.DataMissing;
        }

        pub fn requirePos(v: *Self, name: []const u8, skip: usize) !DataItem {
            var skipped: usize = skip;
            for (v.data.items) |item| {
                if (eql(u8, item.name, name)) {
                    if (skipped > 0) {
                        skipped -= 1;
                        continue;
                    }
                    return item;
                }
            }
            return error.DataMissing;
        }

        pub fn optional(v: *Self, name: []const u8) ?DataItem {
            for (v.data.items) |item| {
                if (eql(u8, item.name, name)) return item;
            }
            return null;
        }

        pub fn optionalBool(v: *Self, name: []const u8) ?bool {
            if (v.optional(name)) |boolish| {
                if (eql(u8, boolish.value, "0") or eql(u8, boolish.value, "false")) {
                    return false;
                }
                return true;
            }
            return null;
        }

        pub fn files(_: *Self, _: []const u8) !void {
            return error.NotImplemented;
        }
    };
}

pub fn validator(data: anytype) Validator(@TypeOf(data)) {
    return Validator(@TypeOf(data)).init(data);
}

pub const DataKind = enum {
    @"form-data",
    json,
};

pub const DataItem = struct {
    data: []const u8,
    headers: ?[]const u8 = null,
    body: ?[]const u8 = null,

    kind: DataKind = .@"form-data",
    name: []const u8,
    value: ?[]const u8,
};

pub const PostData = struct {
    rawpost: []u8,
    items: []DataItem,

    pub fn validate(pdata: PostData, comptime T: type) !T {
        return RequestData(T).initPost(pdata);
    }

    pub fn validator(self: PostData) Validator(PostData) {
        return Validator(PostData).init(self);
    }
};

pub const QueryData = struct {
    alloc: Allocator,
    rawquery: []const u8,
    items: []DataItem,

    /// TODO leaks on error
    pub fn init(a: Allocator, query: []const u8) !QueryData {
        var itr = splitScalar(u8, query, '&');
        const count = std.mem.count(u8, query, "&") + 1;
        const items = try a.alloc(DataItem, count);
        for (items) |*item| {
            item.* = try parseSegment(a, itr.next().?);
        }

        return QueryData{
            .alloc = a,
            .rawquery = query,
            .items = items,
        };
    }

    pub fn validate(qdata: QueryData, comptime T: type) !T {
        return RequestData(T).initQuery(qdata);
    }

    /// segments name=value&name2=otherval
    /// segment in  name=%22dquote%22
    /// segment out name="dquote"
    fn parseSegment(a: Allocator, seg: []const u8) !DataItem {
        if (std.mem.indexOf(u8, seg, "=")) |i| {
            const alen = seg.len - i - 1;
            const input = seg[i + 1 .. seg.len];
            var value: []u8 = @constCast(input);
            if (alen > 0) {
                value = try a.alloc(u8, alen);
                value = try normalizeUrlEncoded(input, value);
            }
            return .{
                .data = seg,
                .name = seg[0..i],
                .value = value,
            };
        } else {
            return .{
                .data = seg,
                .name = seg,
                .value = seg[seg.len..seg.len],
            };
        }
    }

    pub fn validator(self: QueryData) Validator(QueryData) {
        return Validator(QueryData).init(self);
    }
};

pub fn RequestData(comptime T: type) type {
    return struct {
        req: T,

        const Self = @This();

        pub fn init(data: Data) !T {
            var query_valid = data.query.validator();
            var mpost_valid = if (data.post) |post| post.validator() else null;
            var req: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                if (mpost_valid) |*post_valid| {
                    @field(req, field.name) = get(field.type, field.name, post_valid, field.default_value) catch try get(field.type, field.name, &query_valid, field.default_value);
                } else {
                    @field(req, field.name) = try get(field.type, field.name, &query_valid, field.default_value);
                }
            }
            return req;
        }

        pub fn initMap(a: Allocator, data: Data) !T {
            if (data.post) |post| return initPostMap(a, post);

            // Only post is implemented
            return error.NotImplemented;
        }

        fn get(FieldType: type, comptime name: []const u8, valid: anytype, default: ?*const anyopaque) !FieldType {
            return switch (@typeInfo(FieldType)) {
                .Optional => |opt| switch (opt.child) {
                    bool => if (valid.optionalBool(name)) |b|
                        b
                    else if (default != null)
                        @as(*const ?bool, @ptrCast(default.?)).*
                    else
                        null,
                    else => if (valid.optional(name)) |o| o.value else null,
                },
                .Bool => {
                    const item = try valid.require(name);
                    if (item.value) |value| {
                        if (eql(u8, value, "true")) {
                            return true;
                        }

                        if (eql(u8, value, "false")) {
                            return false;
                        }

                        return error.InvalidBool;
                    }

                    return error.UnexpectedNull;
                },
                .Int => {
                    const item = try valid.require(name);
                    if (item.value) |value| {
                        return try std.fmt.parseInt(FieldType, value, 10);
                    }

                    return error.UnexpectedNull;
                },
                .Float => {
                    const item = try valid.require(name);
                    if (item.value) |value| {
                        return try std.fmt.parseFloat(FieldType, value);
                    }

                    return error.UnexpectedNull;
                },
                .Enum => {
                    const item = try valid.require(name);
                    if (item.value) |value| {
                        return std.meta.stringToEnum(FieldType, value) orelse error.InvalidEnumMember;
                    }

                    return error.UnexpectedNull;
                },
                .Pointer => {
                    const item = try valid.require(name);
                    if (item.value) |value| {
                        return value;
                    }

                    return error.UnexpectedNull;
                },
                else => comptime unreachable,
            };
        }

        fn initQuery(query: QueryData) !T {
            var valid = query.validator();
            var req: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(req, field.name) = try get(field.type, field.name, &valid, field.default_value);
            }
            return req;
        }

        fn initPost(data: PostData) !T {
            var valid = data.validator();

            var req: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(req, field.name) = try get(field.type, field.name, &valid, field.default_value);
            }
            return req;
        }

        fn initPostMap(a: Allocator, data: PostData) !T {
            var valid = data.validator();

            var req: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(req, field.name) = switch (@typeInfo(field.type)) {
                    .Optional => if (valid.optional(field.name)) |o| o.value else null,
                    .Pointer => |fptr| switch (fptr.child) {
                        u8 => (try valid.require(field.name)).value,
                        []const u8 => arr: {
                            const count = valid.count(field.name);
                            var map = try a.alloc([]const u8, count);
                            for (0..count) |i| {
                                map[i] = (try valid.requirePos(field.name, i)).value;
                            }
                            break :arr map;
                        },
                        else => comptime unreachable,
                    },
                    else => unreachable,
                };
            }
            return req;
        }
    };
}

fn normalizeUrlEncoded(in: []const u8, out: []u8) ![]u8 {
    var len: usize = 0;
    var i: usize = 0;
    while (i < in.len) {
        const c = &in[i];
        var char: u8 = 0xff;
        switch (c.*) {
            '+' => char = ' ',
            '%' => {
                if (i + 2 >= in.len) {
                    char = c.*;
                    continue;
                }
                char = std.fmt.parseInt(u8, in[i + 1 ..][0..2], 16) catch '%';
                i += 2;
            },
            else => |o| char = o,
        }
        out[len] = char;
        len += 1;
        i += 1;
    }
    return out[0..len];
}

fn jsonValueToString(a: std.mem.Allocator, value: json.Value) !?[]u8 {
    return switch (value) {
        .null => null,
        .bool => |b| try std.fmt.allocPrint(a, "{any}", .{b}),
        .integer => |i| try std.fmt.allocPrint(a, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(a, "{d}", .{f}),
        .string => |s| try a.dupe(u8, s),
        .number_string => |s| try a.dupe(u8, s),
        else => @panic("not implemented"),
    };
}

fn parseApplication(a: Allocator, ap: ContentType.Application, data: []u8, htype: []const u8) ![]DataItem {
    switch (ap) {
        .@"x-www-form-urlencoded" => {
            std.debug.assert(std.mem.startsWith(u8, htype, "application/x-www-form-urlencoded"));

            var itr = splitScalar(u8, data, '&');
            const count = std.mem.count(u8, data, "&") +| 1;
            const items = try a.alloc(DataItem, count);
            for (items) |*itm| {
                const idata = itr.next().?;
                var odata = try a.dupe(u8, idata);
                var name = odata;
                var value = odata;
                if (std.mem.indexOf(u8, idata, "=")) |i| {
                    name = try normalizeUrlEncoded(idata[0..i], odata[0..i]);
                    value = try normalizeUrlEncoded(idata[i + 1 ..], odata[i + 1 ..]);
                }
                itm.* = .{
                    .data = odata,
                    .name = name,
                    .value = value,
                };
            }
            return items;
        },
        .@"x-git-upload-pack-request" => {
            // Git just uses the raw data instead, no need to preprocess
            return &[0]DataItem{};
        },
        .@"octet-stream" => {
            unreachable; // Not implemented
        },
        .json => {
            var parsed = try json.parseFromSlice(json.Value, a, data, .{});
            const root = parsed.value.object;

            var list = try ArrayListUnmanaged(DataItem).initCapacity(a, root.count());
            for (root.keys(), root.values()) |k, v| {
                if (v == .array) {
                    const array = v.array;

                    try list.ensureTotalCapacityPrecise(a, list.capacity + array.items.len);
                    for (array.items) |item| {
                        const element = try jsonValueToString(a, item);

                        const array_item = .{
                            .kind = .json,
                            .data = "", // TODO: determine what should go here
                            .name = try a.dupe(u8, k),
                            .value = element,
                        };
                        list.appendAssumeCapacity(array_item);
                    }

                    continue;
                }

                const val = switch (v) {
                    .null,
                    .bool,
                    .integer,
                    .float,
                    .string,
                    .number_string,
                    => try jsonValueToString(a, v),
                    else => @panic("not implemented"), // TODO: determine how we want to handle objects
                };

                const item = .{
                    .kind = .json,
                    .data = "", // TODO: determine what should go here
                    .name = try a.dupe(u8, k),
                    .value = val,
                };
                list.appendAssumeCapacity(item);
            }

            parsed.deinit();

            return try list.toOwnedSlice(a);
        },
    }
}

const DataHeader = enum {
    @"Content-Disposition",
    @"Content-Type",

    pub fn fromStr(str: []const u8) !DataHeader {
        inline for (std.meta.fields(DataHeader)) |field| {
            if (std.mem.startsWith(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        std.log.info("'{s}'", .{str});
        return error.UnknownHeader;
    }
};

const MultiData = struct {
    header: DataHeader,
    str: []const u8,
    name: ?[]const u8 = null,
    filename: ?[]const u8 = null,

    fn update(md: *MultiData, str: []const u8) void {
        var trimmed = std.mem.trim(u8, str, " \t\n\r");
        if (std.mem.indexOf(u8, trimmed, "=")) |i| {
            if (std.mem.eql(u8, trimmed[0..i], "name")) {
                md.name = trimmed[i + 1 ..];
            } else if (std.mem.eql(u8, trimmed[0..i], "filename")) {
                md.filename = trimmed[i + 1 ..];
            }
        }
    }
};

fn parseMultiData(data: []const u8) !MultiData {
    var extra = splitScalar(u8, data, ';');
    const first = extra.first();
    const header = try DataHeader.fromStr(first);
    var mdata: MultiData = .{
        .header = header,
        .str = first[@tagName(header).len + 1 ..],
    };

    while (extra.next()) |each| {
        mdata.update(each);
    }

    return mdata;
}

fn parseMultiFormData(a: Allocator, data: []const u8) !DataItem {
    _ = a;
    std.debug.assert(std.mem.startsWith(u8, data, "\r\n"));
    if (std.mem.indexOf(u8, data, "\r\n\r\n")) |i| {
        var post_item = DataItem{
            .data = data,
            .name = undefined,
            .value = data[i + 4 ..],
        };

        post_item.headers = data[0..i];
        var headeritr = splitSequence(u8, post_item.headers.?, "\r\n");
        while (headeritr.next()) |header| {
            if (header.len == 0) continue;
            const md = try parseMultiData(header);
            if (md.name) |name| post_item.name = name;
            // TODO look for other headers or other data
        }
        return post_item;
    }
    return error.UnableToParseFormData;
}

/// Pretends to follow RFC2046
fn parseMulti(a: Allocator, mp: ContentType.MultiPart, data: []const u8, htype: []const u8) ![]DataItem {
    var boundry_buffer = [_]u8{'-'} ** 74;
    switch (mp) {
        .mixed => {
            return error.NotImplemented;
        },
        .@"form-data" => {
            std.debug.assert(std.mem.startsWith(u8, htype, "multipart/form-data; boundary="));
            std.debug.assert(htype.len > 30);
            const bound_given = htype[30..];
            @memcpy(boundry_buffer[2 .. bound_given.len + 2], bound_given);

            const boundry = boundry_buffer[0 .. bound_given.len + 2];
            const count = std.mem.count(u8, data, boundry) -| 1;
            const items = try a.alloc(DataItem, count);
            var itr = splitSequence(u8, data, boundry);
            _ = itr.first(); // the RFC says I'm supposed to ignore the preamble :<
            for (items) |*itm| {
                itm.* = try parseMultiFormData(a, itr.next().?);
            }
            std.debug.assert(std.mem.eql(u8, itr.rest(), "--\r\n"));
            return items;
        },
    }
}

pub fn readBody(
    a: Allocator,
    reader: *std.io.AnyReader,
    size: usize,
    htype: []const u8,
) !PostData {
    const post_buf: []u8 = try a.alloc(u8, size);
    const read_size = try reader.read(post_buf);
    if (read_size != size) return error.UnexpectedHttpBodySize;

    const items = switch ((try ContentType.fromStr(htype)).base) {
        .application => |ap| try parseApplication(a, ap, post_buf, htype),
        .multipart, .message => |mp| try parseMulti(a, mp, post_buf, htype),
        .audio, .font, .image, .text, .video => @panic("content-type not implemented"),
    };

    return .{
        .rawpost = post_buf,
        .items = items,
    };
}

pub fn readQuery(a: Allocator, query: []const u8) !QueryData {
    return QueryData.init(a, query);
}

test {
    std.testing.refAllDecls(@This());
}

test "multipart/mixed" {}

test "multipart/form-data" {}

test "multipart/multipart" {}

test "application/x-www-form-urlencoded" {}

test json {
    const json_string =
        \\{
        \\    "string": "value",
        \\    "number": 10,
        \\    "float": 7.9,
        \\    "large_number": 47283472348080234,
        \\    "null": null,
        \\    "array": ["one", "two"]
        \\}
    ;

    const alloc = std.testing.allocator;
    const items = try parseApplication(alloc, .json, @constCast(json_string), "application/json");

    try std.testing.expectEqualStrings(items[0].name, "string");
    try std.testing.expectEqualStrings(items[0].value.?, "value");

    try std.testing.expectEqualStrings(items[1].name, "number");
    try std.testing.expectEqualStrings(items[1].value.?, "10");

    try std.testing.expectEqualStrings(items[2].name, "float");
    try std.testing.expectEqualStrings(items[2].value.?, "7.9");

    try std.testing.expectEqualStrings(items[3].name, "large_number");
    try std.testing.expectEqualStrings(items[3].value.?, "47283472348080234");

    try std.testing.expectEqualStrings(items[4].name, "null");
    try std.testing.expectEqual(items[4].value, null);

    try std.testing.expectEqualStrings(items[5].name, "array");
    try std.testing.expectEqualStrings(items[5].value.?, "one");
    try std.testing.expectEqualStrings(items[6].name, "array");
    try std.testing.expectEqualStrings(items[6].value.?, "two");

    for (items) |i| {
        alloc.free(i.name);
        if (i.value) |v| {
            alloc.free(v);
        }
    }

    alloc.free(items);
}

pub const ContentType = @import("content-type.zig");

const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Type = @import("builtin").Type;
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const splitScalar = std.mem.splitScalar;
const splitSequence = std.mem.splitSequence;
const json = std.json;
