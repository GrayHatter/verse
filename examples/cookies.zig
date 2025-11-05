//! Setting and reading a cookie.

fn index(frame: *Frame) Router.Error!void {
    var buffer: [2048]u8 = undefined;
    const found = try print(
        &buffer,
        "{} cookies found by the server\n",
        .{frame.request.cookie_jar.cookies.items.len},
    );

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
    try frame.sendHTML(.ok, found);
}

const routes = Router.Routes(&[_]Router.Match{
    Router.GET("", index),
});

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var server = try verse.Server.init(&routes, .{
        .mode = .{ .http = .localPort(8081) },
        .auth = .disabled,
    });

    server.serve(alloc) catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

const std = @import("std");
const verse = @import("verse");
const Frame = verse.Frame;
const Router = verse.Router;
const Cookie = verse.Cookie;
const print = std.fmt.bufPrint;

var Random = std.Random.DefaultPrng.init(1337);
var random = Random.random();
