//! Quick start example using Verse Endpoints.
const Endpoints = verse.Endpoints(.{
    verse.Stats.Endpoint,
});

pub fn main() !void {
    std.debug.print("Starting server on http://127.0.0.1:8088/\n", .{});
    Endpoints.serve(
        std.heap.page_allocator,
        .{
            .mode = .{ .http = .localPort(8088) },
            .auth = .disabled,
            .stats = .{ .auth_mode = .open },
        },
    ) catch |err| {
        std.log.err("Unable to serve stats err: [{}]", .{err});
        @panic("endpoint error");
    };
}

const std = @import("std");
const verse = @import("verse");
