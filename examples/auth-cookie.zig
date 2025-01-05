const routes = [_]Router.Match{
    Router.GET("", index),
    Router.GET("create", create),
};

const provider = verse.auth.Provider{
    .ctx = undefined,
    .vtable = .{
        .authenticate = null,
        .valid = null,
        .create_session = null,
        .get_cookie = null,
        .lookup_user = lookupUser,
    },
};

pub fn lookupUser(_: *anyopaque, username: []const u8) !verse.auth.User {
    if (std.mem.eql(u8, "example_user", username)) {
        return .{
            .username = "example_user",
        };
    }
    return error.UnknownUser;
}

pub fn main() !void {
    var cookie_auth = verse.auth.CookieAuth.init(.{
        .server_secret_key = "You must provide your own strong secret key here",
        .base = provider,
    });
    const auth_provider = cookie_auth.provider();

    var server = try verse.Server.init(std.heap.page_allocator, .{
        .mode = .{ .http = .{ .port = 8089 } },
        .router = .{ .routefn = route },
        .auth = auth_provider,
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
    var buffer: [0xffffff]u8 = undefined;
    const html =
        \\<!DOCTYPE html>
        \\<head><title>Cookie Auth Example</title>
        \\<style>
        \\html {{ color-scheme: light dark; }}
        \\body {{ width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }}
        \\</style>
        \\</head>
        \\<body>
        \\<h1>Verse Cookie Auth Demo</h1>
        \\<p>{} cookies found by the server.<br/></p>
        \\<p>{s}{s}</p>
        \\</body>
        \\</html>
        \\
    ;

    const user_str = if (frame.user) |_| "Found a valid cookie for user: " else "No User Found!";
    const username = if (frame.user) |u| u.username.? else "";

    const found = try print(&buffer, html, .{
        frame.request.cookie_jar.cookies.items.len,
        user_str,
        username,
    });

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
