const std = @import("std");
const verse = @import("verse");
const Router = verse.Router;
const BuildFn = Router.BuildFn;

const routes = [_]Router.Match{
    Router.GET("", index),
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var server = try verse.Server.init(alloc, .{
        .mode = .{ .http = .{ .port = 8080 } },
        .router = .{ .routefn = route },
    });

    server.serve() catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

fn route(vrs: *verse.Verse) !BuildFn {
    return Router.router(vrs, &routes);
}

fn index(vrs: *verse.Verse) Router.Error!void {
    try vrs.quickStart();
    try vrs.sendRawSlice("hello world");
}
