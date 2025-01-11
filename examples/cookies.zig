const std = @import("std");
const verse = @import("verse");
const Router = verse.Router;
const BuildFn = Router.BuildFn;
const print = std.fmt.bufPrint;

const Cookie = verse.Cookie;
var Random = std.Random.DefaultPrng.init(1337);
var random = Random.random();

const routes = [_]Router.Match{
    Router.GET("", index),
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var server = try verse.Server.init(alloc, .{
        .mode = .{ .http = .{ .port = 8081 } },
        .router = .{ .routefn = route },
    });

    server.serve() catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

fn route(frame: *verse.Frame) !BuildFn {
    return Router.router(frame, &routes);
}

fn index(frame: *verse.Frame) Router.Error!void {
    var buffer: [2048]u8 = undefined;
    const found = try print(&buffer, "{} cookies found by the server\n", .{frame.request.cookie_jar.cookies.items.len});

    const random_cookie = @tagName(random.enumValue(enum {
        chocolate_chip,
        sugar,
        oatmeal,
        peanut_butter,
        ginger_snap,
    }));

    try frame.cookie_jar.add(Cookie{
        .name = "best-flavor",
        .value = random_cookie,
    });
    try frame.sendHTML(found, .ok);
}
