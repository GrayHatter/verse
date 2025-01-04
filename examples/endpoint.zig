//! Quick start example using Verse Endpoints.

/// `Endpoints` here is a constructed type that will do some validation, and
/// statically and recursively construct the routes supplied.
const Endpoints = verse.routing.Endpoints(.{
    // Note index.zig sets `verse_name = .root;` which will cause the routes it
    // lists to be flattened out. `/` will resolve to the function within
    // `index.zig` with the name `index`.
    @import("endpoint/index.zig"),
    // The remaining endpoints (only random.zig here) are declared normally, and
    // will use verse_name as the route name. The file name is not semantic,
    // the routing will constructed only on the verse_name variable within the
    // given type.
    @import("endpoint/random.zig"),
    // Endpoints don't have to be files, you can define a struct inline with the
    // minimum verse variables and handler functions and Verse will include them
    // as a route.
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
