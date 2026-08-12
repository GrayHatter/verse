//! Uri
//! TODO write docs

index: usize = 0,
path: []const u8,
/// Non null when `?` is present in the URI. Does not include the first `?`
query: ?[]const u8,
bytes: []const u8,

const Uri = @This();

pub fn init(target: []const u8) error{BadData}!Uri {
    var i: usize = 0;
    while (i < target.len) : (i += 1) {
        if (target[i] != '/') break;
    }
    var path = target[i..];
    var query: ?[]const u8 = null;
    if (findScalarPos(u8, path, 0, '?')) |q| {
        query = path[q + 1 ..];
        path = path[0..q];
    }

    return .{
        .path = path,
        .query = query,
        .bytes = target,
    };
}

// when index == len uri ends with a trailing slash
pub fn peek(uri: *const Uri) ?[]const u8 {
    if (uri.index > uri.path.len)
        return null;

    if (findScalarPos(u8, uri.path, uri.index, '/')) |idx| {
        return uri.path[uri.index..idx];
    }
    return uri.path[uri.index..];
}

pub fn next(uri: *Uri) ?[]const u8 {
    const new = uri.peek() orelse return null;
    uri.index += new.len + 1;
    while (uri.index < uri.path.len) : (uri.index += 1) {
        if (uri.path[uri.index] != '/') break;
    }
    if (new.len == 0) uri.index += 1;
    return new;
}

pub fn isDir(uri: Uri) bool {
    return uri.path[uri.path.len - 1] == '/';
}

pub fn first(uri: *Uri) []const u8 {
    uri.index = 0;
    return uri.next() orelse unreachable;
}

pub fn withoutPrefix(uri: Uri) ?[]const u8 {
    if (uri.index < uri.path.len - 1)
        return uri.path[uri.index..];
    return null;
}

pub fn format(uri: Uri, w: *std.Io.Writer) error{WriteFailed}!void {
    try w.writeByte('/');
    try w.writeAll(uri.path);
}

test Uri {
    var uri: Uri = try .init("/repos/srctree");

    try std.testing.expectEqualStrings("repos", uri.next().?);
    try std.testing.expectEqualStrings("srctree", uri.next().?);
    try std.testing.expectEqual(null, uri.next());

    uri = try .init("/malicous/////user/uri?thing=true");
    // GET malicous///user/uri?thing=true
    // Host: srctree.gr.ht

    try std.testing.expectEqualStrings("malicous", uri.next().?);
    try std.testing.expectEqualStrings("user", uri.next().?);
    try std.testing.expectEqualStrings("uri", uri.next().?);
    try std.testing.expectEqual(null, uri.next());

    const uri_file = "/root/first/second/third";

    uri = try .init(uri_file);
    try std.testing.expectEqualStrings("root", uri.next().?);
    try std.testing.expectEqualStrings("first", uri.next().?);
    try std.testing.expectEqualStrings("second", uri.next().?);
    try std.testing.expectEqualStrings("third", uri.next().?);
    try std.testing.expectEqual(null, uri.next());

    const uri_dir = "/root/first/second/";
    uri = try .init(uri_dir);
    try std.testing.expectEqualStrings("root", uri.next().?);
    try std.testing.expectEqualStrings("first", uri.next().?);
    try std.testing.expectEqualStrings("second", uri.next().?);
    try std.testing.expectEqualStrings("", uri.next().?);
    try std.testing.expectEqual(null, uri.next());

    const uri_broken = "/root/first/////sixth/";
    uri = try .init(uri_broken);
    try std.testing.expectEqualStrings("root", uri.next().?);
    try std.testing.expectEqualStrings("first", uri.next().?);
    try std.testing.expectEqualStrings("sixth", uri.next().?);
    try std.testing.expectEqualStrings("", uri.next().?);
    try std.testing.expectEqual(null, uri.next());

    const uri_dots = "/root/first/../../../fifth";
    uri = try .init(uri_dots);
    try std.testing.expectEqualStrings("root", uri.next().?);
    try std.testing.expectEqualStrings("first", uri.next().?);
    try std.testing.expectEqualStrings("..", uri.next().?);
    try std.testing.expectEqualStrings("..", uri.next().?);
    try std.testing.expectEqualStrings("..", uri.next().?);
    try std.testing.expectEqualStrings("fifth", uri.next().?);
    try std.testing.expectEqual(null, uri.next());

    const uri_eager_start = "/////////root/first/../../../fifth";
    uri = try .init(uri_eager_start);
    try std.testing.expectEqualStrings("root", uri.next().?);
    try std.testing.expectEqualStrings("first", uri.next().?);
    try std.testing.expectEqualStrings("..", uri.next().?);
    try std.testing.expectEqualStrings("..", uri.next().?);
    try std.testing.expectEqualStrings("..", uri.next().?);
    try std.testing.expectEqualStrings("fifth", uri.next().?);
    try std.testing.expectEqual(null, uri.next());
}

pub const Builder = struct {
    base: []const u8,
    params: []const []const u8,

    pub fn uri(comptime str: []const u8, params: *const [countParam(str)][]const u8) !Builder {
        return .{
            .base = str,
            .params = params,
        };
    }

    fn countParam(str: []const u8) usize {
        return std.mem.count(u8, str, "{s}");
    }

    pub fn format(b: Builder, w: *std.Io.Writer) !void {
        var idx: usize = 0;
        var pos: usize = 0;
        while (findPos(u8, b.base, idx, "{s}")) |start| {
            defer idx = start + 3;
            try w.writeAll(b.base[idx..start]);
            defer pos += 1;
            try w.writeAll(b.params[pos]);
        }
        if (idx != b.base.len) {
            try w.writeAll(b.base[idx..]);
        }
    }
};

test Builder {
    var buf: [2048]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buf);

    const b: Builder = try .uri("/repos/{s}/search", &.{"srctree"});
    try w.print("{f}", .{b});
    try std.testing.expectEqualStrings("/repos/srctree/search", w.buffered());
    w.end = 0;

    const b1: Builder = try .uri("/repos/{s}/tags", &.{"verse"});
    try w.print("{f}", .{b1});
    try std.testing.expectEqualStrings("/repos/verse/tags", w.buffered());
    w.end = 0;

    const b2: Builder = try .uri("/repos/{s}/ref/{s}", &.{ "verse", "devel" });
    try w.print("{f}", .{b2});
    try std.testing.expectEqualStrings("/repos/verse/ref/devel", w.buffered());
    w.end = 0;

    const b3: Builder = try .uri("/srctree/repos/{s}/ref/{s}", &.{ "verse", "devel" });
    try w.print("{f}", .{b3});
    try std.testing.expectEqualStrings("/srctree/repos/verse/ref/devel", w.buffered());
    w.end = 0;

    const b4: Builder = try .uri("/repos/{s}/ref/{s}", &.{ "hastur", buf[1..6] });
    try w.print("{f}", .{b4});
    // because why *wouldn't* you do this?
    try std.testing.expectEqualStrings("/repos/hastur/ref/repos", w.buffered());
    w.end = 0;
}

const std = @import("std");
const find = std.mem.find;
const findPos = std.mem.findPos;
const findScalarLast = std.mem.findScalarLast;
const findScalar = std.mem.findScalar;
const findScalarPos = std.mem.findScalarPos;
