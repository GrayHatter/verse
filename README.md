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

const routes = []Match{
    GET("index.html", index),
};

pub fn main() !void {
    var srv = Server.init(default_allocator, .{ .mode = .{ .zwsgi = .{} });
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
