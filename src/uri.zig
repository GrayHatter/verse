/// Note UriIterator is a simple split iterator an not a token iterator. If
/// you're using a custom routing implementation; this may not be the behavior
/// you expect. e.g. for a uri = `////word/end` the first 3 calls to next() will
/// return "". Typically this isn't the expected behavior for a directory
/// structure and `////word/end` should be equivalent to `/word/end`. Verse
/// doesn't enforce this behavior to enable cases where the expected value of
/// `/missing/expected/prefix/word/end` has 3 omitted/empty values.
pub const Iterator = std.mem.SplitIterator(u8, .scalar);

/// splitUri will take any uri, do the most basic of input validation and then
/// return UriIterator.
///
/// Note: UriIterator does not behave like a normal token iterator.
pub fn split(uri: []const u8) !Iterator {
    if (uri.len == 0 or uri[0] != '/') return error.InvalidUri;
    return .{
        .index = 0,
        .buffer = uri[1..],
        .delimiter = '/',
    };
}

test "uri" {
    const uri_file = "/root/first/second/third";
    const uri_dir = "/root/first/second/";
    const uri_broken = "/root/first/////sixth/";
    const uri_dots = "/root/first/../../../fifth";

    var itr = try split(uri_file);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("second", itr.next().?);
    try std.testing.expectEqualStrings("third", itr.next().?);
    try std.testing.expectEqual(null, itr.next());

    itr = try split(uri_dir);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("second", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqual(null, itr.next());

    itr = try split(uri_broken);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("sixth", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqual(null, itr.next());

    itr = try split(uri_dots);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("..", itr.next().?);
    try std.testing.expectEqualStrings("..", itr.next().?);
    try std.testing.expectEqualStrings("..", itr.next().?);
    try std.testing.expectEqualStrings("fifth", itr.next().?);
    try std.testing.expectEqual(null, itr.next());
}

const std = @import("std");
