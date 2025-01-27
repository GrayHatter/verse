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
            return v.optionalItem(name) orelse error.DataMissing;
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

        pub fn optionalItem(v: *Self, name: []const u8) ?DataItem {
            for (v.data.items) |item| {
                if (eql(u8, item.name, name)) return item;
            }
            return null;
        }

        pub fn optional(v: *Self, OT: type, name: []const u8) ?OT {
            if (v.optionalItem(name)) |item| {
                switch (OT) {
                    bool => {
                        if (eql(u8, item.value, "0") or eql(u8, item.value, "false")) {
                            return false;
                        }
                        return true;
                    },
                    else => return item,
                }
            } else return null;
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
    kind: DataKind = .@"form-data",
    segment: []u8,
    name: []const u8,
    value: []const u8,
};

pub const PostData = struct {
    rawpost: []u8,
    items: []DataItem,

    pub fn init(a: Allocator, size: usize, reader: *AnyReader, ct: ContentType) !PostData {
        const post_buf: []u8 = try a.alloc(u8, size);
        const read_size = try reader.read(post_buf);
        if (read_size != size) return error.UnexpectedHttpBodySize;

        const items = switch (ct.base) {
            .application => |ap| try parseApplication(a, ap, post_buf),
            .multipart, .message => |mp| try parseMulti(a, mp, post_buf),
            .audio, .font, .image, .text, .video => @panic("content-type not implemented"),
        };

        return .{
            .rawpost = post_buf,
            .items = items,
        };
    }

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
        const segment = try a.dupe(u8, seg);
        if (std.mem.indexOf(u8, segment, "=")) |i| {
            const value_len = segment.len - i - 1;

            if (value_len > 0) {
                var value = segment[i + 1 ..];
                value = try normalizeUrlEncoded(seg[i + 1 ..], value);
                return .{
                    .segment = segment,
                    .name = segment[0..i],
                    .value = value,
                };
            }
            return .{
                .segment = segment,
                .name = segment[0..i],
                .value = segment[i + 1 ..],
            };
        } else {
            return .{
                .segment = segment,
                .name = segment,
                .value = segment[segment.len..segment.len],
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
            inline for (@typeInfo(T).@"struct".fields) |field| {
                if (mpost_valid) |*post_valid| {
                    @field(req, field.name) = get(field.type, field.name, post_valid, field.defaultValue()) catch
                        try get(field.type, field.name, &query_valid, field.defaultValue());
                } else {
                    @field(req, field.name) = try get(field.type, field.name, &query_valid, field.defaultValue());
                }
            }
            return req;
        }

        pub fn initMap(a: Allocator, data: Data) !T {
            if (data.post) |post| return initPostMap(a, post);

            // Only post is implemented
            return error.NotImplemented;
        }

        fn get(FT: type, comptime name: []const u8, valid: anytype, default: ?FT) !FT {
            return switch (@typeInfo(FT)) {
                .optional => |opt| get(opt.child, name, valid, null) catch |err| switch (err) {
                    error.DataMissing => if (default) |d| d else return null,
                    else => return err,
                },
                .bool => valid.optional(bool, name) orelse return error.DataMissing,
                .int => try parseInt(FT, (try valid.require(name)).value, 10),
                .float => try parseFloat(FT, (try valid.require(name)).value),
                .@"enum" => return stringToEnum(FT, (try valid.require(name)).value) orelse error.InvalidEnumMember,
                .pointer => (try valid.require(name)).value,
                else => comptime unreachable, // Not yet implemented
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
                @field(req, field.name) = try get(field.type, field.name, &valid, field.defaultValue());
            }
            return req;
        }

        fn initPostMap(a: Allocator, data: PostData) !T {
            var valid = data.validator();

            var req: T = undefined;
            inline for (std.meta.fields(T)) |field| {
                @field(req, field.name) = switch (@typeInfo(field.type)) {
                    .optional => if (valid.optionalItem(field.name)) |o| o.value else null,
                    .pointer => |fptr| switch (fptr.child) {
                        u8 => (try valid.require(field.name)).value,
                        []const u8 => arr: {
                            const count = valid.count(field.name);
                            var map = try a.alloc([]const u8, count);
                            for (0..count) |i| {
                                map[i] = (try valid.requirePos(field.name, i)).value;
                            }
                            break :arr map;
                        },
                        else => comptime unreachable, // Not yet implemented
                    },
                    else => comptime unreachable, // Not yet implemented
                };
            }
            return req;
        }
    };
}

test RequestData {
    const a = std.testing.allocator;

    const Struct = struct {
        bool: bool,
        int: usize,
        float: f64,
        char: u8,
        str: []const u8,

        opt_bool: ?bool,
        opt_int: ?usize,
        opt_float: ?f64,
        opt_char: ?u8,
        opt_str: ?[]const u8,
    };

    const all_valid =
        \\bool=true&int=10&float=0.123&char=32&str=this%20is%20a%20string
    ;

    var fbs = std.io.fixedBufferStream(all_valid);
    var r = fbs.reader().any();
    const post = try readPost(a, &r, all_valid.len, "application/x-www-form-urlencoded");
    const data = try post.validate(Struct);

    try std.testing.expectEqualDeep(Struct{
        .bool = true,
        .int = 10,
        .float = 0.123,
        .char = ' ',
        .str = "this is a string",

        .opt_bool = null,
        .opt_int = null,
        .opt_float = null,
        .opt_char = null,
        .opt_str = null,
    }, data);

    a.free(post.rawpost);
    for (post.items) |item| a.free(item.segment);
    a.free(post.items);
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

fn jsonValueToString(a: std.mem.Allocator, value: json.Value) ![]u8 {
    return switch (value) {
        .null => a.dupe(u8, "null"),
        .bool => |b| try std.fmt.allocPrint(a, "{any}", .{b}),
        .integer => |i| try std.fmt.allocPrint(a, "{d}", .{i}),
        .float => |f| try std.fmt.allocPrint(a, "{d}", .{f}),
        .string => |s| try a.dupe(u8, s),
        .number_string => |s| try a.dupe(u8, s),
        else => @panic("not implemented"),
    };
}

fn normWwwFormUrlEncoded(a: Allocator, data: []u8) ![]DataItem {
    var itr = splitScalar(u8, data, '&');
    const count = std.mem.count(u8, data, "&") +| 1;
    const items = try a.alloc(DataItem, count);
    for (items) |*item| {
        const idata = itr.next().?;
        item.segment = try a.dupe(u8, idata);
        if (std.mem.indexOf(u8, idata, "=")) |i| {
            item.name = try normalizeUrlEncoded(idata[0..i], item.segment[0..i]);
            item.value = try normalizeUrlEncoded(idata[i + 1 ..], item.segment[i + 1 ..]);
        }
    }
    return items;
}

fn normJson(a: Allocator, data: []u8) ![]DataItem {
    var parsed = try json.parseFromSlice(json.Value, a, data, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    var list = try a.alloc(DataItem, root.count());
    for (root.keys(), root.values(), 0..) |k, v, i| {
        const val = switch (v) {
            .null,
            .bool,
            .integer,
            .float,
            .string,
            .number_string,
            => try jsonValueToString(a, v),
            .object, .array => @panic("not implemented"), // TODO: determine how we want to handle objects
        };
        const name = try a.dupe(u8, k);
        list[i] = .{
            .kind = .json,
            .segment = name, // TODO: determine what should go here
            .name = name,
            .value = val,
        };
    }

    return list;
}

fn parseApplication(a: Allocator, ap: ContentType.Application, data: []u8) ![]DataItem {
    return switch (ap) {
        .@"x-www-form-urlencoded" => try normWwwFormUrlEncoded(a, data),
        // Git just uses the raw data instead, no need to preprocess
        .@"x-git-upload-pack-request" => &[0]DataItem{},
        .@"octet-stream" => @panic("not implemented"),
        .json => try normJson(a, data),
    };
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
            if (eql(u8, trimmed[0..i], "name")) {
                md.name = trimmed[i + 1 ..];
            } else if (eql(u8, trimmed[0..i], "filename")) {
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
    std.debug.assert(std.mem.startsWith(u8, data, "\r\n"));
    if (std.mem.indexOf(u8, data, "\r\n\r\n")) |i| {
        const post_item = DataItem{
            .segment = try a.dupe(u8, data),
            .name = undefined,
            .value = data[i + 4 ..],
        };

        // Commented out while pending rewrite to be more const
        //post_item.headers = data[0..i];
        //var headeritr = splitSequence(u8, post_item.headers.?, "\r\n");
        //while (headeritr.next()) |header| {
        //    if (header.len == 0) continue;
        //    const md = try parseMultiData(header);
        //    if (md.name) |name| post_item.name = name;
        //    // TODO look for other headers or other data
        //}
        return post_item;
    }
    return error.UnableToParseFormData;
}

/// Pretends to follow RFC2046
fn parseMulti(a: Allocator, mp: ContentType.MultiPart, data: []const u8) ![]DataItem {
    var boundry_buffer = [_]u8{'-'} ** 74;
    switch (mp) {
        .mixed => {
            return error.NotImplemented;
        },
        .@"form-data" => |fd| {
            @memcpy(boundry_buffer[2..][0..fd.boundary.len], fd.boundary);
            const boundry = boundry_buffer[0 .. fd.boundary.len + 2];
            const count = std.mem.count(u8, data, boundry) -| 1;
            const items = try a.alloc(DataItem, count);
            var itr = splitSequence(u8, data, boundry);
            _ = itr.first(); // the RFC says I'm supposed to ignore the preamble :<
            for (items) |*itm| {
                itm.* = try parseMultiFormData(a, itr.next().?);
            }
            std.debug.assert(eql(u8, itr.rest(), "--\r\n"));
            return items;
        },
    }
}

pub fn readPost(a: Allocator, reader: *AnyReader, size: usize, htype: []const u8) !PostData {
    return PostData.init(a, size, reader, try ContentType.fromStr(htype));
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

test readPost {
    const a = std.testing.allocator;
    const vect =
        \\title=&desc=&thing=
    ;
    var fbs = std.io.fixedBufferStream(vect);
    var r = fbs.reader().any();
    const post = try readPost(a, &r, vect.len, "application/x-www-form-urlencoded");

    try std.testing.expectEqual(3, post.items.len);

    inline for (post.items, .{ .{ "title", "" }, .{ "desc", "" }, .{ "thing", "" } }) |item, expect| {
        try std.testing.expectEqualStrings(expect[0], item.name);
        try std.testing.expectEqualStrings(expect[1], item.value);
    }

    a.free(post.rawpost);
    for (post.items) |item| a.free(item.segment);
    a.free(post.items);

    const vectextra =
        \\title=&desc=&thing=%22double quote%22
    ;
    fbs = std.io.fixedBufferStream(vectextra);
    r = fbs.reader().any();
    const postextra = try readPost(a, &r, vectextra.len, "application/x-www-form-urlencoded");

    inline for (postextra.items, .{ .{ "title", "" }, .{ "desc", "" }, .{ "thing", "\"double quote\"" } }) |item, expect| {
        try std.testing.expectEqualStrings(expect[0], item.name);
        try std.testing.expectEqualStrings(expect[1], item.value);
    }
    a.free(postextra.rawpost);
    for (postextra.items) |item| a.free(item.segment);
    a.free(postextra.items);
}

test Validator {}

test json {
    const json_string =
        \\{
        \\    "string": "value",
        \\    "number": 10,
        \\    "float": 7.9,
        \\    "large_number": 47283472348080234,
        \\    "Null": null
        //\\    "array": ["one", "two"]
        \\}
    ;

    const alloc = std.testing.allocator;
    const items = try parseApplication(alloc, .json, @constCast(json_string));

    try std.testing.expectEqualStrings(items[0].name, "string");
    try std.testing.expectEqualStrings(items[0].value, "value");

    try std.testing.expectEqualStrings(items[1].name, "number");
    try std.testing.expectEqualStrings(items[1].value, "10");

    try std.testing.expectEqualStrings(items[2].name, "float");
    try std.testing.expectEqualStrings(items[2].value, "7.9");

    try std.testing.expectEqualStrings(items[3].name, "large_number");
    try std.testing.expectEqualStrings(items[3].value, "47283472348080234");

    try std.testing.expectEqualStrings(items[4].name, "Null");
    try std.testing.expectEqualStrings(items[4].value, "null");

    //try std.testing.expectEqualStrings(items[5].name, "array");
    //try std.testing.expectEqualStrings(items[5].value, "one");
    //try std.testing.expectEqualStrings(items[6].name, "array");
    //try std.testing.expectEqualStrings(items[6].value, "two");

    for (items) |i| {
        alloc.free(i.name);
        alloc.free(i.value);
    }

    alloc.free(items);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const AnyReader = std.io.AnyReader;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Type = @import("builtin").Type;
const parseInt = std.fmt.parseInt;
const parseFloat = std.fmt.parseFloat;
const stringToEnum = std.meta.stringToEnum;
const ContentType = @import("content-type.zig");
const eql = std.mem.eql;
const splitScalar = std.mem.splitScalar;
const splitSequence = std.mem.splitSequence;
const json = std.json;
