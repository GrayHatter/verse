text: []const u8,
text_cleaned: []const u8 = &.{},

const Html = @This();

pub const empty: Html = .safe(&.{});

pub fn abx(str: []const u8) Html {
    return .{ .text = str };
}

pub fn safe(str: []const u8) Html {
    return .{ .text_cleaned = str, .text = &.{} };
}

pub fn abxAlloc(str: []const u8, a: Allocator) error{OutOfMemory}!Html {
    const cleaned = try a.alloc(u8, cleanLen(str));
    var w: Writer = .fixed(cleaned);
    for (str) |c|
        clean(c, &w) catch unreachable;
    return .{ .text = &.{}, .text_cleaned = cleaned };
}

pub fn format(html: Html, w: *Writer) error{WriteFailed}!void {
    if (html.text_cleaned.len >= html.text.len) {
        return w.writeAll(html.text_cleaned);
    }

    for (html.text) |c|
        try clean(c, w);
}

/// Basic html sanitizer. Will replace all chars, even when it may be
/// unnecessary to do so in context.
pub fn clean(in: u8, w: *Writer) error{WriteFailed}!void {
    var same = [1:0]u8{in};
    _ = try w.writeAll(switch (in) {
        '<' => "&lt;",
        '&' => "&amp;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&apos;",
        else => &same,
    });
}

pub fn cleanLen(text: []const u8) usize {
    var w: Writer.Discarding = .init(&.{});
    for (text) |c| clean(c, &w.writer) catch unreachable;
    return w.count;
}

test cleanLen {
    try std.testing.expectEqual(17, cleanLen("this is some text"));
    try std.testing.expectEqual(25, cleanLen("this isn't some text"));
    try std.testing.expectEqual(21, cleanLen("this is a <tag>"));
    try std.testing.expectEqual(23, cleanLen("this & that != text"));
}

test Html {
    var a = std.testing.allocator;
    const cleaned_text = try std.fmt.allocPrint(a, "{f}", .{Html{ .text = "<tags not allowed>" }});
    defer a.free(cleaned_text);

    try std.testing.expectEqualStrings("&lt;tags not allowed&gt;", cleaned_text);
}

const std = @import("std");
const Abx = @import("../Antibiotic.zig");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
