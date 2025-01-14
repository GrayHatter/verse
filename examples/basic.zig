//! The quickest way to start a verse server

/// Step 0: Create your endpoint function
fn index(frame: *verse.Frame) Router.Error!void {
    try frame.sendHTML(.ok, "Hello World!");
}

/// Step 1: Add your endpoint as a route
const routes = Router.Routes(&[_]Router.Match{
    // index should to resolve to the root, so use an empty name ""
    Router.GET("", index),
});

/// Step 2: Write main, and start a verse server.
/// That's it! Verse listens on http://localhost:8080 by default.
pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var server = try verse.Server.init(alloc, routes, .{
        .mode = .{ .http = .{} },
    });

    server.serve() catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

const std = @import("std");
const verse = @import("verse");
const Router = verse.Router;
