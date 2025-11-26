pub const Path = @This();

text: []const u8,
path_allowed: bool = false,

pub const Allowed = enum {
    path,
    file,
};

pub fn init(comptime path: Allowed, txt: []const u8) Path {
    return .{
        .text = txt,
        .path_allowed = path == .path,
    };
}

pub fn format(self: Path, out: *Writer) error{WriteFailed}!void {
    if (self.path_allowed) {
        var reader: Reader = .fixed(self.text);
        clean(&reader, out) catch |err| switch (err) {
            error.WriteFailed => return error.WriteFailed,
            error.ReadFailed => unreachable,
        };
    } else {
        for (self.text) |chr| try cleanFilename(chr, out);
    }
}

/// This function is incomplete, and may be unsafe
pub fn clean(in: *Reader, out: *Writer) error{ ReadFailed, WriteFailed }!void {
    while (in.takeDelimiterExclusive('/')) |next| {
        if (eql(u8, next, "..")) {
            if (in.bufferedLen() > 0) in.toss(1);
            continue;
        }
        for (next) |chr| {
            try cleanStem(chr, out);
        }
        if (in.bufferedLen() > 0) {
            try out.writeByte('/');
            if (comptime builtin.zig_version.order(.{ .major = 0, .minor = 15, .patch = 1 }) == .gt) in.toss(1);
        }
    } else |err| switch (err) {
        error.EndOfStream => return,
        error.ReadFailed => return error.ReadFailed,
        error.StreamTooLong => for (in.buffered()) |chr| try cleanStem(chr, out),
    }
}

pub fn cleanStem(in: u8, out: *Writer) error{WriteFailed}!void {
    switch (in) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_', '.' => return out.writeByte(in),
        ' ' => return out.writeByte('-'),
        '\n', '\t', '\\' => return,
        else => return,
    }
}

/// Filters out anything that doesn't look like very boring standard ascii.
/// Intended to be safe and mangle filenames, over allowing all correct/valid
/// names. Patches to improve allowed filenames encouraged!
pub fn cleanFilename(in: u8, out: *Writer) error{WriteFailed}!void {
    switch (in) {
        '/' => return out.writeByte('-'),
        else => return cleanStem(in, out),
    }
}

test cleanFilename {
    const a = std.testing.allocator;

    const allowed = "this-filename-is-allowed";

    var allowed_reader: Reader = .fixed(allowed);

    var w: Writer.Allocating = .init(a);
    var output = try clean(&allowed_reader, &w.writer);
    try std.testing.expectEqualStrings(allowed, w.written());
    w.clearRetainingCapacity();

    const not_allowed = "this-file\nname is !really! me$$ed up?";
    var not_allowed_reader: Reader = .fixed(not_allowed);

    output = try clean(&not_allowed_reader, &w.writer);
    try std.testing.expectEqualStrings("this-filename-is-really-meed-up", w.written());
    w.deinit();
}

/// Allows subdirectories but not parents.
pub fn cleanWord(in: u8, out: *Writer) error{WriteFailed}!void {
    switch (in) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => try out.writeByte(in),
        ' ', '.' => try out.writeByte('-'),
        '\n', '\t', '\\' => return,
        else => return,
    }
}

test cleanWord {
    var w_b: [50]u8 = undefined;
    var w: Writer = .fixed(&w_b);
    try cleanWord('a', &w);
    try std.testing.expectEqualStrings("a", w.buffered());
}

test Path {
    const a = std.testing.allocator;

    var w: Writer.Allocating = .init(a);
    defer w.deinit();

    try w.writer.print("{f}", .{Path{ .text = "valid.txt" }});
    try std.testing.expectEqualStrings("valid.txt", w.written());
    w.clearRetainingCapacity();

    try w.writer.print("{f}", .{Path{ .text = "../valid.txt", .path_allowed = true }});
    try std.testing.expectEqualStrings("valid.txt", w.written());
    w.clearRetainingCapacity();

    try w.writer.print("{f}", .{Path{ .text = "../../valid.txt", .path_allowed = true }});
    try std.testing.expectEqualStrings("valid.txt", w.written());
    w.clearRetainingCapacity();

    try w.writer.print("{f}", .{Path{ .text = "../../../../../..blerg/valid.txt", .path_allowed = true }});
    try std.testing.expectEqualStrings("..blerg/valid.txt", w.written());
    w.clearRetainingCapacity();

    try w.writer.print("{f}", .{Path{ .text = "/valid.txt", .path_allowed = true }});
    try std.testing.expectEqualStrings("/valid.txt", w.written());
    w.clearRetainingCapacity();
}

const std = @import("std");
const eql = std.mem.eql;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
const builtin = @import("builtin");
