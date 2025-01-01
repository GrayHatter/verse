//! Quick start example using Verse Endpoints.

/// `Endpoints` here is a constructed type that will do some validation, and
/// statically and recursively construct the routes supplied.
const Endpoints = verse.Endpoints(.{
    // Note index.zig sets `verse_name = .root;` which will cause the routes it
    // lists to be flattened out
    @import("endpoint/index.zig"),
    // The rest (only random.zig here) are declared normally, and will use
    // verse_name as the route name
    @import("endpoint/random.zig"),
});

pub fn main() !void {
    var endpoints = Endpoints.init(std.heap.page_allocator);
    endpoints.serve(.{
        .mode = .{ .http = .{ .port = 8084 } },
    }) catch |err| {
        std.log.err("Unable to serve endpoints! err: [{}]", .{err});
        @panic("endpoint error");
    };
}

const std = @import("std");
const verse = @import("verse");
