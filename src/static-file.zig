pub fn fileOnDisk(f: *Frame) Route.Error!void {
    _ = f.uri.next(); // clear /static
    const fname = f.uri.next() orelse return error.NotFound;
    if (fname.len == 0) return error.NotFound;

    for (fname) |c| switch (c) {
        'A'...'Z', 'a'...'z', '-', '_', '.' => continue,
        else => return error.Abuse,
    };
    if (find(u8, fname, "/../")) |_| return error.Abuse;

    const period_index = find(u8, fname, ".");
    const content_type: ContentType =
        if (period_index) |index|
            ContentType.fromFileExtension(fname[index..]) catch .@"text/plain"
        else
            .@"text/plain";

    const static = std.Io.Dir.cwd().openDir(f.io, "static", .{}) catch return error.NotFound;
    defer static.close(f.io);
    const file = static.openFile(f.io, fname, .{}) catch return error.NotFound;
    defer file.close(f.io);
    var r_b: [0x4000]u8 = undefined;
    var reader = file.reader(f.io, &r_b);
    f.status = .ok;
    f.content_type = content_type;
    try f.sendHeaders(.done);
    while (reader.interface.stream(&f.downstream.writer.interface, .limited(0xFFFFFF))) |num| {
        log.debug("streaming ({s}) {}", .{ fname, num });
    } else |err| switch (err) {
        error.EndOfStream => return,
        error.ReadFailed => return error.ServerFault,
        error.WriteFailed => return error.WriteFailed,
    }
}

const std = @import("std");
const log = std.log.scoped(.verse_staticfile);
const find = std.mem.find;
const Frame = @import("Frame.zig");
const Route = @import("Router.zig");
const ContentType = @import("content-type.zig");
