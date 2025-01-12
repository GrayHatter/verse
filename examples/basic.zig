//! The quickest way to start a verse server
//!

const routes = Router.Routes(&[_]Router.Match{
    Router.GET("", index),
});

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

fn index(frame: *verse.Frame) Router.Error!void {
    try frame.sendHTML(.ok, "hello world");
}

const std = @import("std");
const verse = @import("verse");
const Router = verse.Router;
const BuildFn = Router.BuildFn;
