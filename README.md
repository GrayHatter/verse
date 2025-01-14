# Verse

A comfortable and powerful web framework, where your Zig code looks like Zig

```zig
const IndexHtml = Page("index.html");

fn index(frame: *Frame) !void {
    const greeting = try allocPrint(frame.alloc, "Hi, {s}!", .{"Mom"});
    defer frame.alloc.free(greeting);

    var page = IndexHtml.init(.{
        // .main_title = "TODO add better title!",
        .message = greeting,
        .features = &[_].{
          .{ .feature = "good" },
          .{ .feature = "fast" },
          .{ .feature = "simple" },
        },
        .reason = .{ .inner_text = "Template generated at comptime" },
    });
    try frame.sendPage(&page);
}

const routes = Routes(&[_]Match{
    GET("index.html", index),
});

pub fn main() !void {
    var srv = Server.init(default_allocator, routes, .{ .mode = .{ .zwsgi = .{} });
    srv.serve() catch |err| switch (err) {
        else => std.debug.print("Server Error: {}\n", .{err});
    };
}
```

and your HTML, looks like HTML

```html
<!DOCTYPE html>
<html>
  <head>
    <title>
      <MainTitle default="Verse Template" />
    </title>
  </head>
  <body>
    <p><Message /></p>
    <ul>
    <For Features>
      <li><Feature /></li>
    </For>
    <With Reason>
      <p><InnerText /></p>
    </With>
  </body>
</html>
```

## Features
  * uWSGI Protocol
  * HTTP
  * Compiles complete site to a completely self contained binary
  * Built in comptime Template library
  * Zero dependencies


## Goals
  * Write Software You Can Love
  * Follow the Zig Zen

## How do I ...
There are a number of [demos/sites in examples/](examples/) that can get you
started quickly. But there are a number of intentionally omitted features. Most
notably is any middleware API. Verse follows Zig Zen and has no hidden control
flow. All middleware patterns break this rule. Even without it, Verse still
**does** support all the important "pre-flight" or request setup steps. If your
application needs a more complex request setup step, you can use a custom
response builder. That builder has full control over both the request frame, and
the call to the endpoint. If you absolutely need to inspect, or alter the
response before it's returned to the client, and understand the downsides of
doing so, You could implement your own middleware by replacing the `Frame`
downstream writer with a local buffer, The called endpoint would write to that
buffer.


