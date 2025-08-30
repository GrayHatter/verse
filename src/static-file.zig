const std = @import("std");
const Frame = @import("frame.zig");
const Route = @import("router.zig");
const ContentType = @import("content-type.zig");

pub fn fileOnDisk(frame: *Frame) Route.Error!void {
    _ = frame.uri.next(); // clear /static
    const fname = frame.uri.next() orelse return error.Unrouteable;
    if (fname.len == 0) return error.Unrouteable;
    for (fname) |c| switch (c) {
        'A'...'Z', 'a'...'z', '-', '_', '.' => continue,
        else => return error.Abuse,
    };
    if (std.mem.indexOf(u8, fname, "/../")) |_| return error.Abuse;

    const static = std.fs.cwd().openDir("static", .{}) catch return error.Unrouteable;
    const fdata = static.readFileAlloc(frame.alloc, fname, 0xFFFFFF) catch return error.Unknown;

    var content_type: ContentType = .@"text/plain";
    const period_index = std.mem.indexOf(u8, fname, ".");
    if (period_index) |index| {
        content_type = ContentType.fromFileExtension(fname[index..]) catch .@"text/plain";
    }

    frame.status = .ok;
    frame.content_type = content_type;

    frame.sendHeaders() catch |err| switch (err) {
        error.WriteFailed => |e| return e,
        else => unreachable,
    };
    try frame.sendRawSlice("\r\n");
    try frame.sendRawSlice(fdata);
}
