text: []const u8,
text_cleaned: []const u8 = &.{},

const Html = @This();

pub fn abx(str: []const u8) Html {
    return .{ .text = str };
}

pub fn safe(str: []const u8) Html {
    return .{ .text_cleaned = str, .text = &.{} };
}

pub fn format(html: Html, w: *Writer) error{WriteFailed}!void {
    if (html.text_cleaned.len >= html.text.len) {
        return w.writeAll(html.text_cleaned);
    } else for (html.text) |c| {
        try clean(c, w);
    }
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

test Html {
    var a = std.testing.allocator;
    const cleaned_text = try std.fmt.allocPrint(a, "{f}", .{Html{ .text = "<tags not allowed>" }});
    defer a.free(cleaned_text);

    try std.testing.expectEqualStrings("&lt;tags not allowed&gt;", cleaned_text);
}

const std = @import("std");
const Writer = std.Io.Writer;
