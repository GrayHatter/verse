const Endpoints = verse.Endpoints(.{
    @import("endpoint/example.zig"),
});

pub fn main() !void {
    var endpoints = Endpoints.init();
    endpoints.serve(std.heap.page_allocator, .{
        .mode = .{ .http = .{ .port = 8084 } },
    }) catch |err| {
        std.log.err("Unable to serve endpoints! err: [{}]", .{err});
        @panic("endpoint error");
    };
}

fn index(vrs: *verse.Verse) verse.Router.Error!void {
    try vrs.quickStart();
    try vrs.sendRawSlice("hello world");
}

const std = @import("std");
const verse = @import("verse");
