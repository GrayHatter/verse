//! The default object for the life time of the request and response.
//!
//! The `*Frame` object is created after the original client request for a
//! single page, that wraps all the Request and response helpers, and exposes
//! the direct `Downstream` connection to the client response nerated from a
//! given build function, and also exposes a number of other functions. e.g.
//! Page/Template generation, Authentication and session management, a websocket
//! connection API, etc.

/// `Frame.alloc` is a per request Allocator, the exact implementation backing
/// this Allocator isn't part of the public API (currently backed by
/// `std.heap.ArenaAllocator`), but does make limited guarantees.
///   * Allocations are tracked internally, and will be cleaned up after the
///     responding endpoint returns to verse.
///
/// see also: `Server.gpa`
alloc: Allocator,
/// Io (not guaranteed to be the same Io provided to `Server`).
io: Io,
/// Connection to the downstream client/request.
downstream: Downstream,
/// Request object received from client.
request: *const Request,
/// Target URI May be different from the Request.URI
/// (i.e. canonization, e.g. `//route/` -> `/route/q
uri: Uri,
/// user is set to exactly what is provided directly by the active
/// Auth.Provider. It's possible for an Auth.Provider to return a User that is
/// invalid. Depending on the need for any given use, users should always verify
/// the validity in addition to the existence of this user field. e.g. it's
/// possible to identify a banned, or other user that should have less than
/// public access.
user: ?Auth.User = null,
/// Response Headers: `frame.response_headers.addCustom("Name", "Value");`
response_headers: Headers,
/// Response Cookies
cookie_jar: cookies.Jar,
// TODO document content_type
content_type: ?ContentType = ContentType.default,
/// Status returned as the response code to the client. IFF null, `.ok` will be
/// sent instead.
status: ?Status = null,

/// Mark data within frame as 'sensitive', which can help inform verse some of
/// the data should not flow in to some companion APIs
sensitive: bool = false,

/// The StackedData API is currently unstable, and may change in the future.
/// template_data saving any type to be fetched at any time later in the
/// request. An example use case is when it makes more sense to generate some
/// page data at a different phase, e.g. when constructing the route, and then
/// reading it later.
template_data: template.StackedData,

/// Experimental API (may be removed or changed, open an issue/feature request
/// if you find it useful)
session: Session = undefined,

/// Unstable API; may be altered or removed in the future
server: *const Server,

const Frame = @This();

pub const Uri = @import("Uri.zig");
pub const Downstream = @import("Downstream.zig");

pub const Phase = union(enum) {
    /// Processing the incoming request
    request: Phase.Request,
    /// Incoming request is completed; verse-internal checks and features
    prerouting: PreRouting,
    /// PreRouting complete, and control has moved from verse into client code
    routing: Routing,
    /// Request has found and endpoint, and the endpoint is generating the page
    responding: Responding,
    err: Err,

    pub const new: Phase = .{ .request = .new };
    pub const routed: Phase = .{ .routing = .routed };
    pub const done: Phase = .{ .responding = .closed };
    pub const routing_err: Phase = .{ .err = .routing };

    pub const Request = enum {
        new,
        /// Partial request sent, may be waiting for a Continue response.
        headers,
        /// Headers complete, client sent body not yet read into verse.
        waiting,
        body,
        complete,
    };

    pub const PreRouting = enum {
        /// Prerouting phase, various internal routes and security steps
        prerouting,
    };

    pub const Routing = enum {
        new,
        /// Routing phase has passed from Verse into a client router.
        routing,
        /// Routing has returned a callable fn.
        routed,
    };

    pub const Responding = enum {
        /// Request & Routing to target fn was successful. Endpoint ready to be called.
        new,
        /// Any data has been written towards downstream.
        started,
        /// Response headers (and closing "\r\n") has been written.
        headers_done,
        /// Response body has been written.
        body_done,
        waiting,
        /// Response is considered closed, and to more data is expected. (Sending additional
        /// data may be supported or undefined)
        closed,
        /// Setting `phase == .raw` disables any Phase progression within verse.
        /// The caller/setter becomes responsible for any remaining housekeeping.
        raw,
    };

    pub const Err = enum {
        nos,
        client,
        routing,
        server,
    };
};

/// sendPage is the default way to respond in verse using the Template system.
/// sendPage will flush headers to the client before sending Page data
pub fn sendPage(frame: *Frame, page: anytype) NetworkError!void {
    frame.status = frame.status orelse .ok;
    try frame.sendHeaders(.done);
    try frame.downstream.writer.interface.print("{f}", .{page});
    return;
}

/// Takes a any object, that can be represented by json, converts it into a
/// json string, and sends to the client.
pub fn sendJson(f: *Frame, comptime code: std.http.Status, json_data: anytype) NetworkError!void {
    if (code == .no_content) {
        @compileError("Sending JSON is not supported with status code no content");
    }

    f.status = code;
    f.content_type = .json;

    try f.sendHeaders(.done);
    try f.downstream.writer.interface.print("{f}", .{json.fmt(
        json_data,
        .{ .emit_null_optional_fields = false },
    )});
}

pub fn sendHTML(f: *Frame, comptime code: std.http.Status, html: []const u8) NetworkError!void {
    f.status = code;
    f.content_type = .html;
    try f.sendHeaders(.done);
    try f.downstream.writer.interface.writeAll(html);
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
    try f.downstream.writer.interface.print("Location: {s}\r\n\r\n", .{loc});
}

pub fn acceptWebsocket(frame: *Frame) !Websocket {
    return Websocket.accept(frame);
}

pub fn init(srv: *Server, ds: Downstream, request: *const Request, a: Allocator, io: Io) !Frame {
    return .{
        .alloc = a,
        .io = io,
        .request = request,
        .downstream = ds,
        .uri = try .init(request.target),
        .response_headers = .empty,
        .user = srv.auth.authenticate(&request.headers, request.now) catch null,
        // Request.now is used to validate the session from the time the request was received by the server
        .cookie_jar = .init(a),
        .template_data = .empty,
        .server = srv,
    };
}

pub const HeadersPhase = enum {
    more,
    done,
};

/// Mark data within frame to be possibly 'sensitive', which will prevent verse
/// from logging, or otherwise retaining the data. This API is currently a work
/// in progress and there may still be ways sensitive data may leak into other
/// sources. Extra care should be taken, i.e. do not rely on this feature
/// exclusively with data of a sensitive or private nature.
pub fn markSensitive(f: *Frame) void {
    f.sensitive = true;
}

pub fn sendHeaders(f: *Frame, comptime end: HeadersPhase) NetworkError!void {
    std.debug.assert(f.downstream.phase == .responding and
        (f.downstream.phase.responding == .new or f.downstream.phase.responding == .started));
    const ds: *Writer = &f.downstream.writer.interface;
    // Verse headers
    try ds.writeAll(f.httpHeader("HTTP/1.1"));
    const s_name = "Server: verse/" ++ build_version ++ "\r\n";
    try ds.writeAll(s_name);

    if (f.content_type) |ct| {
        try ds.writeAll("Content-Type: ");
        switch (ct.base) {
            inline else => |tag, name| {
                try ds.print("{s}/{s}", .{ @tagName(name), @tagName(tag) });
            },
        }
        if (ct.parameter) |param| try ds.print("; charset={s}", .{@tagName(param)});
        try ds.writeAll("\r\n");
    }
    // Custom Headers
    try ds.print("{f}", .{std.fmt.alt(f.response_headers, .fmt)});
    for (f.cookie_jar.cookies.items) |cookie| {
        try ds.print("{f}\r\n", .{std.fmt.alt(cookie, .header)});
    }

    if (end == .done) {
        try ds.writeAll("\r\n");
        f.downstream.phase.responding = .headers_done;
    }
}

/// Helper function to return a default error page for a given http status code.
pub fn sendDefaultErrorPage(f: *Frame, comptime code: std.http.Status) void {
    return Router.defaultResponse(code)(f) catch |err| {
        log.err("Unable to generate default error page! {}", .{err});
        @panic("internal verse error");
    };
}

fn httpHeader(f: *Frame, comptime ver: []const u8) [:0]const u8 {
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
    print_empty: bool,
    print_post_data: bool,

    /// When set to true, this function will print data `Frame` even when marked
    /// as sensitive. The safest option is to set this to false.
    redact_sensitive_frames: bool,

    /// Use with caution, may print secrets.
    pub const verbose: DumpDebugOptions = .{
        .print_empty = true,
        .print_post_data = true,
        .redact_sensitive_frames = true,
    };

    pub const safe: DumpDebugOptions = .{
        .print_empty = false,
        .print_post_data = false,
        .redact_sensitive_frames = false,
    };
};

/// Use with caution, will likely dump sensitive data into log sinks without
/// redacting secrets.
pub fn dumpDebugData(frame: *const Frame, comptime opt: DumpDebugOptions) void {
    const dlog = std.log.scoped(.DumpDebug);
    if (comptime opt.redact_sensitive_frames) if (frame.sensitive) {
        dlog.err("Skipping frame marked sensitive", .{});
    };

    switch (frame.downstream.gateway) {
        .zwsgi => |zw| {
            var knowns = zw.known;
            var itr = knowns.iterator();
            while (itr.next()) |entry| {
                if (entry.value.*) |value| {
                    dlog.err("    '{s}' => '{s}'\n", .{ @tagName(entry.key), value });
                } else if (comptime opt.print_empty) {
                    dlog.err("    '{s}' => [empty]\n", .{@tagName(entry.key)});
                }
            }
            for (zw.vars.items) |varr|
                dlog.err("    '{s}' => '{s}'\n", .{ varr.key, varr.val });
        },
        .http => {
            var itr_headers = @constCast(frame.request).headers.iterator();
            while (itr_headers.next()) |header|
                dlog.err("    request header => {s} -> {s}\n", .{ header.name, header.value });
        },
        .none => {},
    }

    if (comptime opt.print_post_data) {
        if (frame.request.data.post) |post_data| {
            dlog.err("    post data => '''{s}'''\n", .{post_data.source});
        }
    }
}

pub fn requireValidUser(frame: *Frame) error{ Unauthorized, Unauthenticated }!void {
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
    f.session.raze();
    f.template_data.raze(f.alloc);
}

test Frame {
    _ = std.testing.refAllDecls(@This());
    _ = &Auth;
    _ = &ContentType;
    _ = &Headers;
    _ = &Request;
    _ = &Router;
    _ = &Server;
    _ = &Websocket;
    _ = &dumpDebugData;
    _ = &template.StackedData;
    _ = &template;
}

test dumpDebugData {
    var req: Request = undefined;
    req.data.post = null;
    var frame: Frame = undefined;
    frame.downstream.gateway = .none;
    frame.request = &req;

    dumpDebugData(&frame, .verbose);
}

const Auth = @import("Auth.zig");
const ContentType = @import("ContentType.zig");
const Headers = @import("Headers.zig");
const NetworkError = errors.NetworkError;
const Request = @import("Request.zig");
const Router = @import("Router.zig");
const Server = @import("Server.zig");
const Websocket = @import("websocket.zig");
const builtin = @import("builtin");
const cookies = @import("cookies.zig");
const errors = @import("errors.zig");
const json = @import("json.zig");
const template = @import("template.zig");
const verse_buildopts = @import("verse_buildopts");
const build_version = verse_buildopts.version;

// Experimental
const Session = if (verse_buildopts.sessions_enabled or builtin.is_test) @import("Session.zig") else void;

const std = @import("std");
const Allocator = std.mem.Allocator;
const Io = std.Io;
const Status = std.http.Status;
const Writer = Io.Writer;
const log = std.log.scoped(.Verse);
