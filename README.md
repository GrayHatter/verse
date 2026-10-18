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

Because your code deserves to look as good as your site does.

## Features
  * Zero dependency ( forever )
  * Typed HTML Templates ( verified at comptime )
  * Ergonomic Endpoint API
  * Testing and Mock framework
  * uWSGI Protocol Support
  * Standalone HTTP server
  * Web Application API  ( supports any custom `Type` )
  * Antibiotic ( data/html sanitation, optional, and enforced )
  * Input Data Validation
  * User Authentication
    * mTLS
    * Session based
    * Cookie based
  * Bot Detection ( detects and classifies friendly and hostile bots )
  * Websocket Support
  * Single Binary for the entire site ( all assets optionally embedded )
  * Server Stats builtin
  * Robots.txt helper
  * Works with `std.Io.Reader` and `std.Io.Writer` ( obviously )

## Design Philosophy

Verse borrows heavily from the standards set by ZigLang itself. Primarily

  * Works with the compiler, never against.
  * Compile errors are better than malformed pages.
  * No hidden control flow.
  * Ergonomics matter.
  * Users matter.

### Comptime

The power of the zig compiler is what inspired the typed template system. Verse
encourages template reuse. Templates, and page render functions are generated at
comptime. Meaning changing the HTML template, will result in a compile error at
every call site. Did you fix every use? The compiler will tell you. Removed a
HTML variable? Compilation will fail until you remove that now unused parameter.
Just like your zig code deserves to be. (Comptime verified templates have
already saved hours of time, and prevented all those bugs in srctree alone!)

### Simple Control Flow

Zig takes pride in never hiding the control flow of your application. Verse
agrees! The life cycle of a request will ever only flow in a single direction,
through the 5 defined phases within verse. Starting from the client, request
setup, pre-routing, routing to the endpoint, page build phase, finally response
and clean-up. Auto-magic defaults are provided for each step in the state
machine, with everything exposed for any custom configuration you might want to
build. The caveat to this is porting an existing site without this restrictions
might prove challenging. Middleware like patterns commonly break sites in
unpredictable ways, and introduce difficult to remedy defects, both catastrophic
(killing the request/response after all the work was done to generate the
endpoint), or even worse, sporadic bugs, that only show up in some endpoints,
making tracking down the actual issue painful.

### Ergonomics

Ergonomics matter, a small change should result in a small diff. Much of the
boilerplate for a site can be auto generated using the `Endpoint`, including
generating option "smoke tests" for every endpoint. And `Request.Data.Validate`
to make user input

### Userspace

Users matter! Responses can fail, but users should never be subjected to a blank
page. Userspace responses can fail (individual endpoints), but these errors must
be captured, and replaced with an error page. This is how the default builder
behaves, but even this can be thwarted if endpoints start communicating directly
to the client before returning. If you want to enforce this, to can advantage of
peak zig, by including `errdefer comptime unreachable` in userspace, and
handling client disconnects (and that resulting `NetworkError`).

## Goals
  * Write Software You Can Love
  * Follow the Zig Zen
  * Respond in *micro*seconds

## Status?

Verse is currently incomplete, but completely useable today. It was created to
back `srctree`, but has become useful enough to stand on it's own. The
development of Verse, currently follows the needs of srctree, but only out of
habit. It's exists to serve it's users, so if you encounter any issues,
difficulties, or bugs. Report them! Even feature requests are welcome and
encouraged! All of the planned features will be implemented only once srctree
needs them, or anyone else! If something isn't working as you expect, that's a
bug that will be fixed! But only after you report it. Bug reports are accepted
both on [srctree](https://srctree.gr.ht/repo/verse), and
[Github](https://github.com/GrayHatter/verse)

## How do I ...
There are a number of [demos/sites in examples/](examples/) that can get you
started quickly. `zig build run-[example name]` If you want to try out the demo.

## TODO Features
  * Allocation Free Requests
  * AfterParty ( post request runner API )
  * Quic
  * SSE API
  * Userspace defined data validation
  * `verse.Frame.unreachable()`
