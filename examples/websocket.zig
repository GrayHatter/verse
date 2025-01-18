//! Basic Websocket

/// The verse endpoint API is explained in examples/endpoint.zig and a basic
/// understanding of Verse.Endpoint is assumed here.
const Root = struct {
    pub const verse_name = .root;
    pub const verse_routes = .{
        verse.Router.WEBSOCKET("socket", socket),
    };

    pub fn index(frame: *verse.Frame) verse.Router.Error!void {
        var buffer: [0xffffff]u8 = undefined;
        const page = try print(&buffer, page_html, .{"page never generated"});

        try frame.sendHTML(.ok, page);
    }

    fn socket(frame: *verse.Frame) verse.Router.Error!void {
        var ws = frame.acceptWebsocket() catch unreachable;

        for (0..10) |i| {
            var buffer: [0xff]u8 = undefined;
            ws.send(print(&buffer, "Iteration {}\n", .{i}) catch unreachable) catch unreachable;
            std.time.sleep(1_000_000_000);
            var read_buffer: [0x4000]u8 = undefined;
            const msg = ws.recieve(&read_buffer) catch unreachable;
            std.debug.print("msg: {} -- {s}\n", .{ msg.header, msg.msg });
        }
        std.debug.print("Socket Example Done\n", .{});
    }

    const page_html =
        \\<!DOCTYPE html>
        \\<html>
        \\<head>
        \\  <title>Websocket Example</title>
        \\  <style>
        \\    html {{ color-scheme: light dark; }}
        \\    body {{ width: 35em; margin: 0 auto; font-family: Tahoma, Verdana, Arial, sans-serif; }}
        \\  </style>
        \\  <script>
        \\  var socket;
        \\  function retry() {{
        \\    socket =  new WebSocket("ws://localhost:8088/socket");
        \\    socket.onmessage = (event) => {{
        \\      console.log(event.data);
        \\    }};
        \\  }}
        \\  retry();
        \\  function send() {{
        \\    socket.send(document.getElementById("text").value);
        \\  }}
        \\</script>
        \\</head>
        \\<body>
        \\<h1>Title</h1>
        \\<p>
        \\  {s}
        \\  <input type="text" id="text" />
        \\  <button onclick="send()"> Send</button>
        \\  <button onclick="retry()"> Connect</button>
        \\</p>
        \\</body>
        \\</html>
        \\
    ;
};

pub fn main() !void {
    const Endpoints = verse.Endpoints(.{
        Root,
    });
    var endpoints = Endpoints.init(std.heap.page_allocator);

    endpoints.serve(.{
        .mode = .{ .http = .{ .port = 8088 } },
    }) catch |err| {
        std.log.err("Unable to serve endpoints! err: [{}]", .{err});
        @panic("endpoint error");
    };
}

const std = @import("std");
const verse = @import("verse");
const print = std.fmt.bufPrint;
