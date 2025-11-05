//! Instead of a basic Request/Response object; Verse provides a `*Frame`.
//! The `*Frame` object is wrapper around the Request from the client, the
//! response expected to be generated from a given build function, and also
//! exposes a number of other functions. e.g. Page/Template generation,
//! Authentication and session management, a websocket connection API, etc.

/// The Allocator provided by `alloc` is a per request Array Allocator that can
/// be used by endpoints, where allocated memory will exist until after the
/// build function returns to the server handling the request.
alloc: Allocator,
///
io: Io,
/// Base Request object from the client.
request: *const Request,
/// Connection to the downstream client/request
downstream: Downstream,
/// Request URI as received by Verse
uri: Uri.Iterator,

// TODO fix this unstable API
auth_provider: Auth.Provider,

/// user is set to exactly what is provided directly by the active
/// Auth.Provider. It's possible for an Auth.Provider to return a User that is
/// invalid. Depending on the need for any given use, users should always verify
/// the validity in addition to the existence of this user field.
/// e.g. it's possible to identify a banned, or other user that should have less
/// than public access.
user: ?Auth.User = null,

/// The ResponseData API is currently unstable, and may change in the future.
/// response_data saving any type to be fetched at any time later in the
/// request. An example use case is when it makes more sense to generate some
/// page data at a different phase, e.g. when constructing the route, and then
/// reading it later. Use with caution, as may leak if misused.
response_data: ResponseData,

/// Response Headers
headers: Headers,
/// Response Cookies
cookie_jar: Cookies.Jar,
// TODO document content_type
content_type: ?ContentType = ContentType.default,

status: ?std.http.Status = null,

headers_done: bool = false,

/// Unstable API; may be altered or removed in the future
server: *const anyopaque,

const Frame = @This();

pub const Downstream = struct {
    gateway: Gateway,
    reader: *Reader,
    writer: *Writer,

    pub const Gateway = union(enum) {
        zwsgi: *zWSGIRequest,
        http: *std.http.Server,
    };

    pub const Error = error{WriteFailed};
    // Largest single IP packet size
    pub const ONESHOT_SIZE = 14720;
};

/// sendPage is the default way to respond in verse using the Template system.
/// sendPage will flush headers to the client before sending Page data
pub fn sendPage(frame: *Frame, page: anytype) NetworkError!void {
    frame.status = frame.status orelse .ok;

    try frame.sendHeaders(.close);
    try frame.downstream.writer.print("{f}", .{page});
    return;

    //var vec_buffer: [2048]IOVec = @splat(undefined);
    //var varr: IOVArray = .initBuffer(&vec_buffer);
    //const required = page.iovecCountAll();
    //if (required > varr.capacity) {
    //    varr = IOVArray.initCapacity(frame.alloc, required) catch @panic("OOM");
    //}
    //defer if (varr.capacity > vec_buffer.len) varr.deinit(frame.alloc);

    //var stkfb = std.heap.stackFallback(0xffff, frame.alloc);
    //const stkalloc = stkfb.get();

    //page.ioVec(&varr, stkalloc) catch |iovec_err| {
    //log.err("Error building iovec ({}) fallback to writer", .{iovec_err});
    //};
    //frame.dowstream.writer.writevAll(@ptrCast(varr.items)) catch |err| switch (err) {
    //    else => log.err("iovec write error Error {} len {}", .{ err, varr.items.len }),
    //};
}

/// Takes a any object, that can be represented by json, converts it into a
/// json string, and sends to the client.
pub fn sendJSON(f: *Frame, comptime code: std.http.Status, json: anytype) NetworkError!void {
    if (code == .no_content) {
        @compileError("Sending JSON is not supported with status code no content");
    }

    f.status = code;
    f.content_type = .json;

    try f.sendHeaders(.close);
    try f.downstream.writer.print("{f}", .{std.json.fmt(
        json,
        .{ .emit_null_optional_fields = false },
    )});
}

pub fn sendHTML(f: *Frame, comptime code: std.http.Status, html: []const u8) NetworkError!void {
    f.status = code;
    f.content_type = .html;
    try f.sendHeaders(.close);
    try f.downstream.writer.writeAll(html);
}

pub fn redirect(f: *Frame, loc: []const u8, comptime scode: std.http.Status) NetworkError!void {
    f.status = switch (scode) {
        .multiple_choice,
        .moved_permanently,
        .found,
        .see_other,
        .not_modified,
        .use_proxy,
        .temporary_redirect,
        .permanent_redirect,
        => scode,
        else => @compileError("redirect() can only be called with a 3xx redirection code"),
    };

    try f.sendHeaders(.more);
    try f.downstream.writer.print("Location: {s}\r\n\r\n", .{loc});
}

pub fn acceptWebsocket(frame: *Frame) !Websocket {
    return Websocket.accept(frame);
}

pub fn init(
    a: Allocator,
    io: Io,
    srv: *const Server,
    req: *const Request,
    downstream: Downstream,
    auth: Auth.Provider,
) !Frame {
    return .{
        .alloc = a,
        .io = io,
        .request = req,
        .downstream = downstream,
        .uri = try Uri.split(req.uri),
        .auth_provider = auth,
        .headers = Headers.init(),
        .user = auth.authenticate(&req.headers, req.now.toSeconds()) catch null,
        // Request.now is used to validate the session from the time the request was received by the server
        .cookie_jar = .init(a),
        .response_data = .{},
        .server = @ptrCast(srv),
    };
}

pub const SendHeadersEnd = enum {
    close,
    more,
};

pub fn sendHeaders(f: *Frame, comptime end: SendHeadersEnd) NetworkError!void {
    std.debug.assert(!f.headers_done);
    // Verse headers
    try f.downstream.writer.writeAll(f.HttpHeader("HTTP/1.1"));
    const s_name = "Server: verse/" ++ build_version ++ "\r\n";
    try f.downstream.writer.writeAll(s_name);

    if (f.content_type) |ct| {
        try f.downstream.writer.writeAll("Content-Type: ");
        switch (ct.base) {
            inline else => |tag, name| {
                try f.downstream.writer.print("{s}/{s}", .{ @tagName(name), @tagName(tag) });
            },
        }
        if (ct.parameter) |param|
            try f.downstream.writer.print("; charset={s}", .{@tagName(param)});
        try f.downstream.writer.writeAll("\r\n");
    }
    // Custom Headers
    try f.downstream.writer.print("{f}", .{std.fmt.alt(f.headers, .fmt)});
    for (f.cookie_jar.cookies.items) |cookie| {
        try f.downstream.writer.print("{f}\r\n", .{std.fmt.alt(cookie, .header)});
    }
    switch (end) {
        .close => try f.downstream.writer.writeAll("\r\n"),
        .more => return,
    }
    f.headers_done = true;
}

/// Helper function to return a default error page for a given http status code.
pub fn sendDefaultErrorPage(f: *Frame, comptime code: std.http.Status) void {
    return Router.defaultResponse(code)(f) catch |err| {
        log.err("Unable to generate default error page! {}", .{err});
        @panic("internal verse error");
    };
}

const HEADER_VEC_COUNT = 64; // 64 ought to be enough for anyone!

fn HttpHeader(f: *Frame, comptime ver: []const u8) [:0]const u8 {
    if (f.status == null) f.status = .ok;
    return switch (f.status.?) {
        .switching_protocols => ver ++ " 101 Switching Protocols\r\n",
        .ok => ver ++ " 200 OK\r\n",
        .created => ver ++ " 201 Created\r\n",
        .no_content => ver ++ " 204 No Content\r\n",
        .multiple_choice => ver ++ " 300 Multiple Choices\r\n",
        .moved_permanently => ver ++ " 301 Moved Permanently\r\n",
        .found => ver ++ " 302 Found\r\n",
        .see_other => ver ++ " 303 See Other\r\n",
        .not_modified => ver ++ " 304 Not Modified\r\n",
        .use_proxy => ver ++ " 305 Use Proxy\r\n",
        .temporary_redirect => ver ++ " 307 Temporary Redirect\r\n",
        .permanent_redirect => ver ++ " 308 Permanent Redirect\r\n",
        .bad_request => ver ++ " 400 Bad Request\r\n",
        .unauthorized => ver ++ " 401 Unauthorized\r\n",
        .forbidden => ver ++ " 403 Forbidden\r\n",
        .not_found => ver ++ " 404 Not Found\r\n",
        .method_not_allowed => ver ++ " 405 Method Not Allowed\r\n",
        .conflict => ver ++ " 409 Conflict\r\n",
        .payload_too_large => ver ++ " 413 Content Too Large\r\n",
        .internal_server_error => ver ++ " 500 Internal Server Error\r\n",
        else => b: {
            log.err("Status code not implemented {}", .{f.status.?});
            break :b ver ++ " 500 Internal Server Error\r\n";
        },
    };
}

pub const DumpDebugOptions = struct {
    print_empty: bool = false,
    print_post_data: bool = true,
};

pub fn dumpDebugData(frame: *const Frame, comptime opt: DumpDebugOptions) void {
    switch (frame.downstream.gateway) {
        .zwsgi => |zw| {
            var itr = zw.known.iterator();
            while (itr.next()) |entry| {
                if (entry.value.*) |value| {
                    std.debug.print("\tDumpDebug '{s}' => '{s}'\n", .{ @tagName(entry.key), value });
                } else if (comptime opt.print_empty) {
                    std.debug.print("\tDumpDebug '{s}' => '[empty]\n", .{@tagName(entry.key)});
                }
            }
            for (zw.vars.items) |varr| {
                std.debug.print("\tDumpDebug '{s}' => '{s}'\n", .{ varr.key, varr.val });
            }
        },
        .http => {
            var itr_headers = @constCast(frame.request).headers.iterator();
            while (itr_headers.next()) |header| {
                std.debug.print("\tDumpDebug request header => {s} -> {s}\n", .{ header.name, header.value });
            }
        },
    }
    if (comptime opt.print_post_data) {
        if (frame.request.data.post) |post_data| {
            std.debug.print("\tpost data => '''{s}'''\n", .{post_data.rawpost});
        }
    }
}

pub fn requireValidUser(frame: *Frame) !void {
    if (frame.user) |user| {
        if (user.valid()) {
            return;
        } else {
            return error.Unauthorized;
        }
    } else {
        return error.Unauthenticated;
    }
    comptime unreachable;
}

pub fn raze(f: *Frame) void {
    f.response_data.raze(f.alloc);
}

test {
    _ = std.testing.refAllDecls(@This());
    _ = &dumpDebugData;
    _ = &ResponseData;
}

const Allocator = std.mem.Allocator;
const Auth = @import("auth.zig");
const ContentType = @import("content-type.zig");
const Cookies = @import("cookies.zig");
const Error = errors.Error;
const Headers = @import("headers.zig");
const IOVArray = iov.IOVArray;
const IOVec = iov.IOVec;
const NetworkError = errors.NetworkError;
const Request = @import("request.zig");
const ResponseData = @import("response-data.zig");
const Uri = @import("uri.zig");
const Router = @import("router.zig");
const Server = @import("server.zig");
const Websocket = @import("websocket.zig");
const errors = @import("errors.zig");
const iov = @import("iovec.zig");
const log = std.log.scoped(.Verse);
const std = @import("std");
const zWSGIParam = @import("zwsgi.zig").zWSGIParam;
const zWSGIRequest = @import("zwsgi.zig").zWSGIRequest;
const Writer = Io.Writer;
const Reader = Io.Reader;
const Io = std.Io;

const verse_buildopts = @import("verse_buildopts");
const build_version = verse_buildopts.version;
