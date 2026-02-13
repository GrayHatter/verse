//! Client Request Data
post: ?Post,
query: Query,

const Data = @This();

pub fn validate(data: Data, comptime T: type) !T {
    return Validate(T).init(data);
}

pub fn Validate(comptime T: type) type {
    return struct {
        pub fn init(data: Data) !T {
            var request: T = undefined;
            var query: From(Query) = .init(&data.query);
            if (data.post) |data_post| {
                const post: From(Post) = .init(&data_post);
                inline for (@typeInfo(T).@"struct".fields) |field| {
                    @field(request, field.name) = post.get(field.type, field.name, field.defaultValue()) catch
                        try query.get(field.type, field.name, field.defaultValue());
                }
            } else {
                inline for (@typeInfo(T).@"struct".fields) |field| {
                    @field(request, field.name) = try query.get(field.type, field.name, field.defaultValue());
                }
            }
            return request;
        }

        pub fn initAlloc(a: Allocator, data: Data) !T {
            if (data.post) |post|
                return initPostAlloc(a, post);

            // Only post is implemented
            return error.NotImplemented;
        }

        fn initQuery(query: Query) !T {
            var req: T = undefined;
            var q: From(Query) = .init(&query);
            inline for (@typeInfo(T).@"struct".fields) |field| {
                // TODO this has no test
                @field(req, field.name) = try q.get(field.type, field.name, field.defaultValue());
            }
            return req;
        }

        fn initPost(post: Post) !T {
            var p: From(Post) = .init(&post);
            var req: T = undefined;
            inline for (@typeInfo(T).@"struct".fields) |field| {
                @field(req, field.name) = try p.get(field.type, field.name, field.defaultValue());
            }
            return req;
        }

        fn initPostAlloc(a: Allocator, post: Post) !T {
            var p: From(Post) = .init(&post);
            var req: T = undefined;
            inline for (@typeInfo(T).@"struct".fields) |field| {
                @field(req, field.name) = switch (@typeInfo(field.type)) {
                    .optional => if (p.optionalItem(field.name)) |o| o.value else null,
                    .pointer => |fptr| switch (fptr.child) {
                        u8 => (try p.require(field.name)).value,
                        []const u8 => arr: {
                            const count = p.count(field.name);
                            var map = try a.alloc([]const u8, count);
                            for (0..count) |i| {
                                map[i] = (try p.requirePos(field.name, i)).value;
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

        pub fn From(Group: type) type {
            return struct {
                data: *const Group,

                pub const Valid = @This();

                pub fn init(g: *const Group) Valid {
                    return .{ .data = g };
                }

                pub fn get(v: Valid, FT: type, comptime name: []const u8, default: ?FT) error{ InvalidInt, InvalidFloat, InvalidEnumMember, DataMissing }!FT {
                    return switch (@typeInfo(FT)) {
                        .optional => |opt| v.get(opt.child, name, null) catch |err| switch (err) {
                            error.DataMissing => if (default) |d| d else return null,
                            else => return err,
                        },
                        .bool => v.optional(bool, name) orelse return error.DataMissing,
                        .int => parseInt(FT, (try v.require(name)).value, 10) catch return error.InvalidInt,
                        .float => parseFloat(FT, (try v.require(name)).value) catch return error.InvalidFloat,
                        .@"enum" => return stringToEnum(FT, (try v.require(name)).value) orelse error.InvalidEnumMember,
                        .pointer => (try v.require(name)).value,
                        else => comptime unreachable, // Not yet implemented
                    };
                }

                pub fn count(v: *const Valid, name: []const u8) usize {
                    var i: usize = 0;
                    for (v.data.items) |item| {
                        if (eql(u8, item.name, name)) i += 1;
                    }
                    return i;
                }

                pub fn require(v: *const Valid, name: []const u8) !Item {
                    return v.optionalItem(name) orelse error.DataMissing;
                }

                pub fn requirePos(v: *const Valid, name: []const u8, skip: usize) !Item {
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

                pub fn optionalItem(v: *const Valid, name: []const u8) ?Item {
                    for (v.data.items) |item| {
                        if (eql(u8, item.name, name)) return item;
                    }
                    return null;
                }

                pub fn optional(v: *const Valid, OT: type, name: []const u8) ?OT {
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

                pub fn files(_: *const Valid, _: []const u8) !void {
                    return error.NotImplemented;
                }
            };
        }
    };
}

pub const Kind = enum {
    @"form-data",
    json,
};

pub const Item = struct {
    kind: Kind = .@"form-data",
    segment: []u8,
    name: []const u8,
    value: []const u8,
};

pub const Post = struct {
    bytes: []u8,
    items: []Item,

    pub fn init(a: Allocator, size: usize, reader: *Reader, ct: ContentType) !Post {
        //reader.fillMore() catch {}; // TODO fix me
        const read_b = reader.readAlloc(a, size) catch |err| switch (err) {
            error.EndOfStream => {
                log.err("unable to read full amount, {} seek {} end {}", .{ size, reader.seek, reader.end });
                return err;
            },
            else => {
                log.err("read alloc failed, {}", .{err});
                return err;
            },
        };
        if (read_b.len != size) return error.UnexpectedHttpBodySize;

        const items = switch (ct.base) {
            .application => |ap| try parseApplication(a, ap, read_b),
            .multipart, .message => |mp| try Multi.parseContentType(a, mp, read_b),
            .text => |tx| try parseText(a, tx, read_b),
            .audio, .font, .image, .video => @panic("content-type not implemented"),
        };

        return .{
            .bytes = read_b,
            .items = items,
        };
    }

    pub fn validate(pdata: Post, comptime T: type) !T {
        return Validate(T).initPost(pdata);
    }

    pub fn validateAlloc(pdata: Post, comptime T: type, alloc: Allocator) !T {
        return Validate(T).initPostAlloc(alloc, pdata);
    }
};

pub const Query = struct {
    bytes: []const u8,
    items: []Item,

    /// TODO leaks on error
    pub fn init(a: Allocator, query: []const u8) !Query {
        var itr = splitScalar(u8, query, '&');
        const count = std.mem.count(u8, query, "&") + 1;
        const items = try a.alloc(Item, count);
        for (items) |*item| {
            item.* = try parseSegment(a, itr.next().?);
        }

        return .{
            .bytes = query,
            .items = items,
        };
    }

    pub fn validate(qdata: Query, comptime T: type) !T {
        return Validate(T).initQuery(qdata);
    }

    /// segments name=value&name2=otherval
    /// segment in  name=%22dquote%22
    /// segment out name="dquote"
    fn parseSegment(a: Allocator, seg: []const u8) !Item {
        const segment = try a.dupe(u8, seg);
        if (indexOf(u8, segment, "=")) |i| {
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
};

test Validate {
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

    var reader = std.Io.Reader.fixed(all_valid);
    const post: Post = try .init(a, all_valid.len, &reader, try .fromStr(
        "application/x-www-form-urlencoded",
    ));
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

    a.free(post.bytes);
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

fn normWwwFormUrlEncoded(a: Allocator, data: []u8) ![]Item {
    var itr = splitScalar(u8, data, '&');
    const count = std.mem.count(u8, data, "&") +| 1;
    const items = try a.alloc(Item, count);
    for (items) |*item| {
        const idata = itr.next().?;
        item.segment = try a.dupe(u8, idata);
        if (indexOf(u8, idata, "=")) |i| {
            item.name = try normalizeUrlEncoded(idata[0..i], item.segment[0..i]);
            item.value = try normalizeUrlEncoded(idata[i + 1 ..], item.segment[i + 1 ..]);
        }
    }
    return items;
}

fn normJson(a: Allocator, data: []u8) ![]Item {
    var parsed = try json.parseFromSlice(json.Value, a, data, .{});
    defer parsed.deinit();
    const root = parsed.value.object;

    var list = try a.alloc(Item, root.count());
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

fn parseApplication(a: Allocator, ap: ContentType.Application, data: []u8) ![]Item {
    return switch (ap) {
        .@"x-www-form-urlencoded" => try normWwwFormUrlEncoded(a, data),
        // Git just uses the raw data instead, no need to preprocess
        .@"x-git-upload-pack-request" => &[0]Item{},
        .@"octet-stream" => @panic("not implemented"),
        .json => try normJson(a, data),
    };
}

const Header = enum {
    @"Content-Disposition",
    @"Content-Type",

    pub fn fromStr(str: []const u8) ?Header {
        inline for (std.meta.fields(Header)) |field| {
            if (std.mem.startsWith(u8, str, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        std.log.info("'{s}'", .{str});
        return null;
    }
};

const Multi = struct {
    str: []const u8,
    name: ?[]const u8 = null,
    filename: ?[]const u8 = null,

    fn update(md: *Multi, str: []const u8) void {
        var trimmed = std.mem.trim(u8, str, " \t\n\r");
        if (indexOf(u8, trimmed, "=")) |i| {
            if (eql(u8, trimmed[0..i], "name")) {
                md.name = std.mem.trim(u8, trimmed[i + 1 ..], "\"");
            } else if (eql(u8, trimmed[0..i], "filename")) {
                md.filename = std.mem.trim(u8, trimmed[i + 1 ..], "\"");
            }
        }
    }

    fn parse(data: []const u8) !Multi {
        if (std.mem.startsWith(u8, data, "Content-Disposition: form-data")) {
            var mdata: Multi = .{
                .str = data["Content-Disposition: form-data".len + 1 ..],
            };

            var extra = splitScalar(u8, data, ';');
            _ = extra.first();
            while (extra.next()) |each| {
                mdata.update(each);
            }

            return mdata;
        }
        return error.ParseError;
    }

    fn parseFormData(a: Allocator, data: []const u8) !Item {
        std.debug.assert(std.mem.startsWith(u8, data, "\r\n"));
        if (indexOf(u8, data, "\r\n\r\n")) |i| {
            var post_item = Item{
                .segment = try a.dupe(u8, data),
                .name = &.{},
                .value = data[i + 4 ..],
            };

            if (indexOfPos(u8, data, 2, "\r\n")) |h_idx| {
                const md = try parse(data[2..h_idx]);
                if (md.name) |name|
                    post_item.name = name;
            }
            return post_item;
        }
        return error.UnableToParseFormData;
    }

    /// Pretends to follow RFC2046
    fn parseContentType(a: Allocator, mp: ContentType.MultiPart, data: []const u8) ![]Item {
        var boundry_buffer: [74]u8 = @splat('-');
        switch (mp) {
            .mixed => {
                return error.NotImplemented;
            },
            .@"form-data" => |fd| {
                @memcpy(boundry_buffer[2..][0..fd.boundary.len], fd.boundary);
                const boundry = boundry_buffer[0 .. fd.boundary.len + 2];
                const count = std.mem.count(u8, data, boundry) -| 1;
                const items = try a.alloc(Item, count);
                var itr = splitSequence(u8, data, boundry);
                _ = itr.first(); // the RFC says I'm supposed to ignore the preamble :<
                for (items) |*itm| {
                    itm.* = try Multi.parseFormData(a, itr.next().?);
                }
                std.debug.assert(eql(u8, itr.rest(), "--\r\n"));
                return items;
            },
        }
    }
};

fn parseText(a: Allocator, tx: ContentType.Text, data: []const u8) ![]Item {
    _ = tx;
    const dupe = try a.dupe(u8, data);
    return try a.dupe(Item, &[1]Item{.{
        .segment = dupe,
        .name = &.{},
        .value = dupe,
    }});
}

pub fn readQuery(a: Allocator, query: []const u8) !Query {
    return Query.init(a, query);
}

test {
    std.testing.refAllDecls(@This());
}

test "multipart/mixed" {}

test "multipart/form-data" {}

test "multipart/multipart" {}

test "application/x-www-form-urlencoded" {}

test "postdata init" {
    const a = std.testing.allocator;
    const vect =
        \\title=&desc=&thing=
    ;
    var reader = std.Io.Reader.fixed(vect);
    const post: Post = try .init(a, vect.len, &reader, try .fromStr(
        "application/x-www-form-urlencoded",
    ));

    try std.testing.expectEqual(3, post.items.len);

    inline for (post.items, .{ .{ "title", "" }, .{ "desc", "" }, .{ "thing", "" } }) |item, expect| {
        try std.testing.expectEqualStrings(expect[0], item.name);
        try std.testing.expectEqualStrings(expect[1], item.value);
    }

    a.free(post.bytes);
    for (post.items) |item| a.free(item.segment);
    a.free(post.items);

    const vectextra =
        \\title=&desc=&thing=%22double quote%22
    ;
    reader = std.Io.Reader.fixed(vectextra);
    const postextra: Post = try .init(a, vectextra.len, &reader, try .fromStr(
        "application/x-www-form-urlencoded",
    ));

    inline for (postextra.items, .{ .{ "title", "" }, .{ "desc", "" }, .{ "thing", "\"double quote\"" } }) |item, expect| {
        try std.testing.expectEqualStrings(expect[0], item.name);
        try std.testing.expectEqualStrings(expect[1], item.value);
    }
    a.free(postextra.bytes);
    for (postextra.items) |item| a.free(item.segment);
    a.free(postextra.items);
}

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
const Reader = std.Io.Reader;
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const Type = @import("builtin").Type;
const parseInt = std.fmt.parseInt;
const parseFloat = std.fmt.parseFloat;
const stringToEnum = std.meta.stringToEnum;
const ContentType = @import("../content-type.zig");
const eql = std.mem.eql;
const splitScalar = std.mem.splitScalar;
const splitSequence = std.mem.splitSequence;
const indexOf = std.mem.indexOf;
const indexOfPos = std.mem.indexOfPos;
const json = std.json;
const log = std.log.scoped(.verse_request_data);
