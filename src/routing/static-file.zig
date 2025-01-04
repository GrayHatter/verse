const std = @import("std");
const Frame = @import("../frame.zig");
const Router = @import("router.zig");

pub fn fileOnDisk(frame: *Frame) Router.Error!void {
    _ = frame.uri.next(); // clear /static
    const fname = frame.uri.next() orelse return error.Unrouteable;
    if (fname.len == 0) return error.Unrouteable;
    for (fname) |c| switch (c) {
        'A'...'Z', 'a'...'z', '-', '_', '.' => continue,
        else => return error.Abusive,
    };
    if (std.mem.indexOf(u8, fname, "/../")) |_| return error.Abusive;

    const static = std.fs.cwd().openDir("static", .{}) catch return error.Unrouteable;
    const fdata = static.readFileAlloc(frame.alloc, fname, 0xFFFFFF) catch return error.Unknown;

    try frame.quickStart();
    try frame.sendRawSlice(fdata);
}
