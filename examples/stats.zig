//! Quick start example using Verse Endpoints.
const Endpoints = verse.Endpoints(.{
    //
    verse.stats.Endpoint,
});

pub fn main() !void {
    Endpoints.serve(
        std.heap.page_allocator,
        .{
            .mode = .{ .http = .{ .port = 8088 } },
            .stats = true,
        },
    ) catch |err| {
        std.log.err("Unable to serve stats err: [{}]", .{err});
        @panic("endpoint error");
    };
}

const std = @import("std");
const verse = @import("verse");
