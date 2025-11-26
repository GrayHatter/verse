text: []const u8,

const Html = @This();

pub fn format(self: Html, out: *Writer) error{WriteFailed}!void {
    for (self.text) |c| {
        try clean(c, out);
    }
}

/// Basic html sanitizer. Will replace all chars, even when it may be
/// unnecessary to do so in context.
pub fn clean(in: u8, out: *Writer) error{WriteFailed}!void {
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

const std = @import("std");
const Writer = std.Io.Writer;
