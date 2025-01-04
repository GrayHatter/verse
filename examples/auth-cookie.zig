const routes = [_]Router.Match{
    Router.GET("", index),
    Router.GET("create", create),
};

pub fn main() !void {
    var cookie_auth = verse.auth.CookieAuth.init(.{
        .server_secret_key = "You must provide your own strong key here",
    });
    const provider = cookie_auth.provider();

    var server = try verse.Server.init(std.heap.page_allocator, .{
        .mode = .{ .http = .{ .port = 8089 } },
        .router = .{ .routefn = route },
        .auth = provider,
    });

    server.serve() catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

fn route(frame: *verse.Frame) !BuildFn {
    return Router.router(frame, &routes);
}

fn create(frame: *Frame) Router.Error!void {
    var user = verse.auth.User{
        .username = "example_user",
    };

    frame.auth_provider.createSession(&user) catch return error.Unknown;
    if (frame.auth_provider.getCookie(user) catch null) |cookie| {
        try frame.cookie_jar.add(cookie);
    }
    try frame.redirect("/", .found);
}

fn index(frame: *Frame) Router.Error!void {
    var buffer: [2048]u8 = undefined;
    const found = try print(&buffer, "{} cookies found by the server\n", .{frame.request.cookie_jar.cookies.items.len});

    try frame.quickStart();
    try frame.sendRawSlice(found);
}

const std = @import("std");
const verse = @import("verse");
const Router = verse.Router;
const Frame = verse.Frame;
const BuildFn = Router.BuildFn;
const Cookie = verse.Cookie;
const print = std.fmt.bufPrint;
