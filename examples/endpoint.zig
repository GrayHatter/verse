const Endpoints = Endpoint.Endpoints(.{
    @import("endpoint/example.zig"),
});

pub fn main() !void {
    var endpoints = Endpoints.init();
    endpoints.serve(
        std.heap.page_allocator,
        .{ .http = .{ .port = 8084 } },
    ) catch |err| {
        std.log.err("Unable to serve endpoints! err: [{}]", .{err});
        @panic("endpoint error");
    };
}

fn index(verse: *Verse) Verse.Router.Error!void {
    try verse.quickStart();
    try verse.sendRawSlice("hello world");
}

const std = @import("std");
const Verse = @import("verse");
const Endpoint = Verse.Endpoint;
