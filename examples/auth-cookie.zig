//! This cookie authentication example provides the simplest minimum pieces
//! needed to set up cookie based authentication.

/// To use Cookie auth provider in verse, you only need to supply it a Provider
/// that can do user lookups.
const UserFinder = struct {
    pub fn provider(self: *UserFinder) verse.auth.Provider {
        return .{
            .ctx = self,
            .vtable = .{
                .authenticate = null,
                .valid = null,
                .createSession = null,
                .getCookie = null,
                .lookupUser = lookupUser,
            },
        };
    }

    /// The unique user identifier is named `username` here. But if usernames
    /// are mutable, it may be better to use an identifier that doesn't change
    /// for the entire life of the user. A database unique primary key is
    /// another common option for the user identifier.
    pub fn lookupUser(_: *anyopaque, username: []const u8) !verse.auth.User {
        // Extra care should be taken to ensure a user lookup function doesn't
        // leak any information about acceptable users. In this case because
        // Cookie auth validates the token is valid before calling user lookup
        // it's safe to simply compare the user names
        if (std.mem.eql(u8, "example_user", username)) {
            return .{
                .unique_id = "example_user",
                .username = "example_user",
            };
        }
        return error.UnknownUser;
    }
};

pub fn main() !void {
    // Set up cookie user auth
    // Step 0: Create a user lookup object. This example is stateless, but you
    // could also have your user lookup provider connect to an external
    // authentication server here as well.
    var finder = UserFinder{};
    // Step 1: Set up the Cookie auth provider.
    var cookie_auth = verse.auth.Cookie.init(.{
        // This is the key used to generate and verify user tokens. Anyone who
        // is able to learn or guess this secret key could generate tokens that
        // could impersonate any user. It must be kept secure. Consider storing
        // it outside of the source code.
        .server_secret_key = "You must provide your own strong secret key here",
        // The base auth provider. This one only does user lookups, but a more
        // complicated version may replace the other default steps, e.g. a
        // custom authentication function, or generate a different cookie.
        .base = finder.provider(),
    });

    // Step 2: Start a normal Verse Server with an authentication Provider
    var server = try verse.Server.init(std.heap.page_allocator, routes, .{
        .mode = .{ .http = .{ .port = 8089 } },
        .auth = cookie_auth.provider(),
    });

    server.serve() catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

/// The index page will provide some details about the cookie & auth state
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

    const page = try print(&buffer, html, .{
        frame.request.cookie_jar.cookies.items.len,
        user_str,
        username,
    });

    try frame.sendHTML(.ok, page);
}

/// Sample "login" page. Just visiting `/create` will generate and give a valid
/// user token back to the client. An redirect them back to `/`.
///
/// Generally, you'd want to authenticate the user before giving them a token.
/// Validating a submitted username and password is the most common option.
fn create(frame: *Frame) Router.Error!void {
    var user = verse.auth.User{
        .unique_id = "example_user",
        .username = "example_user",
    };

    frame.auth_provider.createSession(&user, frame.request.now.toSeconds()) catch return error.Unknown;
    if (frame.auth_provider.getCookie(user) catch null) |cookie| {
        try frame.cookie_jar.add(cookie);
    }
    try frame.redirect("/", .found);
}

const routes = Router.Routes(&[_]Router.Match{
    Router.GET("", index),
    Router.GET("create", create),
});

const std = @import("std");
const verse = @import("verse");
const Router = verse.Router;
const Frame = verse.Frame;
const BuildFn = Router.BuildFn;
const Cookie = verse.Cookie;
const print = std.fmt.bufPrint;
