//! Antibiotic: some basic input sanitation helpers.
//! It won't cure every condition, but it can help treat many diseases

const abx = @This();

pub const Error = error{
    ReadFailed,
    WriteFailed,
};

pub const Rule = enum {
    html,
    path,
    title,
    word,

    pub fn func(r: Rule) RuleFn {
        return switch (r) {
            .html => .{ .chr = cleanHtml },
            .path => .{ .str = cleanPath },
            .title => .{ .chr = cleanHtml },
            .word => .{ .chr = cleanWord },
        };
    }
};

pub const RuleFn = union(enum) {
    chr: *const fn (u8, *Writer) Error!void,
    str: *const fn (*Reader, *Writer) Error!void,
};

pub fn clean(comptime rule: Rule, in: *Reader, out: *Writer) Error!void {
    switch (comptime rule.func()) {
        .chr => |func| {
            while (in.takeByte()) |c| {
                try func(c, out);
            } else |err| if (err != error.EndOfStream) return err;
        },
        .str => |func| return try func(in, out),
    }
}

pub const Html = struct {
    text: []const u8,

    pub fn format(self: Html, out: *Writer) error{WriteFailed}!void {
        for (self.text) |c| {
            try cleanHtml(c, out);
        }
    }

    pub fn clean(src: u8) ?[]const u8 {
        return switch (src) {
            '<' => "&lt;",
            '&' => "&amp;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&apos;",
            else => null,
        };
    }
};

/// Basic html sanitizer. Will replace all chars, even when it may be
/// unnecessary to do so in context.
pub fn cleanHtml(in: u8, out: *Writer) error{WriteFailed}!void {
    var same = [1:0]u8{in};
    _ = try out.writeAll(switch (in) {
        '<' => "&lt;",
        '&' => "&amp;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&apos;",
        else => &same,
    });
}

test Html {
    var a = std.testing.allocator;
    const cleaned = try std.fmt.allocPrint(a, "{f}", .{Html{ .text = "<tags not allowed>" }});
    defer a.free(cleaned);

    try std.testing.expectEqualStrings("&lt;tags not allowed&gt;", cleaned);
}

pub const Path = struct {
    text: []const u8,
    path_allowed: bool = false,

    pub fn format(self: Path, out: *Writer) error{WriteFailed}!void {
        if (self.path_allowed) {
            var reader: Reader = .fixed(self.text);
            cleanPath(&reader, out) catch |err| switch (err) {
                error.WriteFailed => return error.WriteFailed,
                error.ReadFailed => unreachable,
            };
        } else {
            for (self.text) |chr| try cleanFilename(chr, out);
        }
    }
};

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

/// This function is incomplete, and may be unsafe
pub fn cleanPath(in: *Reader, out: *Writer) Error!void {
    while (in.takeDelimiterExclusive('/')) |next| {
        if (eql(u8, next, "..")) continue;
        for (next) |chr| {
            try cleanStem(chr, out);
        }
        if (in.bufferedLen() > 0) {
            try out.writeByte('/');
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
    var output = try clean(.path, &allowed_reader, &w.writer);
    try std.testing.expectEqualStrings(allowed, w.written());
    w.clearRetainingCapacity();

    const not_allowed = "this-file\nname is !really! me$$ed up?";
    var not_allowed_reader: Reader = .fixed(not_allowed);

    output = try clean(.path, &not_allowed_reader, &w.writer);
    try std.testing.expectEqualStrings("this-filename-is-really-meed-up", w.written());
    w.deinit();
}

/// Allows subdirectories but not parents.
pub fn cleanWord(in: u8, out: *Writer) Error!void {
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

const std = @import("std");
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
