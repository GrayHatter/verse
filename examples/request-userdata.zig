const Root = struct {
    pub const verse_name = .root;

    pub const verse_routes = .{
        // Using verse.Endpoints will include index() for you
        verse.Router.POST("post", post),
        // The verse router will drop GET requests.
        // Uncommenting the following `GET` line will allow the page to resolve,
        // but the Request data demonstrated is method specific.
        // verse.Router.GET("post", post),
    };

    /// This struct matches the example form below. But many other types are
    /// supported. With other examples demonstrating more complex uses.
    const RequiredData = struct {
        username: []const u8,
        email: []const u8,
    };

    fn post(frame: *verse.Frame) verse.Router.Error!void {
        var buffer: [0xffffff]u8 = undefined;
        var page = try print(&buffer, page_html, .{"page never generated"});

        if (frame.request.data.post) |post_data| {
            const required_data = post_data.validate(RequiredData) catch {
                // If post_data.validate is unable to translate the received
                // user data into the given type, it will return an error.
                page = try print(&buffer, page_html, .{"Invalid data submitted!"});
                return try frame.sendHTML(.ok, page);
            };

            // Because neither fields in RequiredData is optional; they
            // both are required. Most browsers will include empty input
            // fields as an empty string. So normal input validation is
            // still required.
            if (required_data.username.len == 0) {
                page = try print(&buffer, page_html, .{"Username must not be empty!"});
                return try frame.sendHTML(.ok, page);
            } else if (required_data.email.len == 0) {
                page = try print(&buffer, page_html, .{"email must not be empty!"});
                return try frame.sendHTML(.ok, page);
            }

            // As with all user data, you must be **extremely** careful using
            // unsanitized user input! This example has both a buffer overflow,
            // (try submitting a very long username, or email), as well as a
            // script injection bug, (try injecting some html or another example
            // script e.g. `<script>alert("hi mom");</script>`.)
            //
            // Preventing script injection can be complicated and is covered
            // more completely in the bleach.zig example.
            //
            // Fortunately the buffer overflow is prevented multiple ways here.
            // First using Zig's runtime safety, even an egregious example like
            // `@memcpy(userbuffer[0..request_data.username.len], request_data.username);`
            // Would be caught and prevented. But also using safe stdlib
            // functions. If you uncomment the above @memcpy and notice the
            // panic(), but with or without memory safety enabled
            // std.fmt.bufPrint will still refuse to overrun the given buffer.
            // Uncomment the next line to disable runtime memory safety, and
            // notice Verse will still catch the error safely.
            // @setRuntimeSafety(false);
            var userbuffer: [0x80]u8 = undefined;
            page = try print(&buffer, page_html, .{
                try print(
                    &userbuffer,
                    "Your username is {s}<br/>Your email is {s}",
                    .{ required_data.username, required_data.email },
                ),
            });
        } else {
            page = try print(&buffer, page_html, .{
                "No POST data received! Did you use a GET request by mistake?",
            });
        }

        try frame.sendHTML(.ok, page);
    }

    pub fn index(frame: *verse.Frame) !void {
        var buffer: [0xffffff]u8 = undefined;
        const form =
            \\<form action="/post" method="POST">
            \\  <label for="username">Username: </label><input id="username" name="username" />
            \\  <label for="email">Email: </label><input id="email" name="email" />
            \\  <input type="submit" value="Via GET" formmethod="GET" />
            \\  <input type="submit" value="Via POST" formmethod="POST" />
            \\</form>
        ;

        const page = try print(&buffer, page_html, .{form});

        try frame.sendHTML(.ok, page);
    }

    const page_html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Verse User Data Example</title>
        \\  <style>
        \\    html {{ color-scheme: light dark; }}
        \\    body {{ width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }}
        \\  </style>
        \\</head>
        \\<body>
        \\<h1>Sometimes it's useful to accept user data.</h1>
        \\<p>
        \\{s}
        \\</p>
        \\</body>
        \\</html>
        \\
    ;
};

const Endpoints = verse.Endpoints(.{
    Root,
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
const print = std.fmt.bufPrint;
