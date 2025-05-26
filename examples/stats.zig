//! Quick start example using Verse Endpoints.
const Endpoints = verse.Endpoints(.{
    //
    verse.stats.Endpoint,
});

pub fn main() !void {
    var endpoints = Endpoints.init(std.heap.page_allocator);
    endpoints.serve(.{
        .mode = .{ .http = .{ .port = 8088 } },
        .stats = true,
    }) catch |err| {
        std.log.err("Unable to serve stats err: [{}]", .{err});
        @panic("endpoint error");
    };
}

const std = @import("std");
const verse = @import("verse");
