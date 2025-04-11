//! Instead of a basic Request/Response object; Verse provides a `*Frame`.
//! The `*Frame` object is wrapper around the Request from the client, the
//! response expected to be generated from a given build function, and also
//! exposes a number of other functions. e.g. Page/Template generation,
//! Authentication and session management, a websocket connection API, etc.

/// The Allocator provided by `alloc` is a per request Array Allocator that can
/// be used by endpoints, where allocated memory will exist until after the
/// build function returns to the server handling the request.
alloc: Allocator,
/// Base Request object from the client.
request: *const Request,
/// downsteam writer based on which ever server accepted the client request and
/// created this Frame
downstream: union(Downstream) {
    buffer: std.io.BufferedWriter(ONESHOT_SIZE, Stream.Writer),
    zwsgi: Stream,
    http: Stream,
},
/// Request URI as received by Verse
uri: Router.UriIterator,

// TODO fix this unstable API
auth_provider: Auth.Provider,
/// user is set to exactly what is provided directly by the active
/// Auth.Provider. It's possible for an Auth.Provider to return a User that is
/// invalid. Depending on the need for any given use, users should always verify
/// the validity in addition to the existence of this user field.
user: ?Auth.User = null,

/// The ResponseData API is currently unstable, and may change in the future.
/// response_data saving any type to be fetched at any time later in the
/// request. An example use case is when it makes more sense to generate some
/// page data at a different phase, e.g. when constructing the route, and then
/// reading it later. Use with caution, as may leak if misused.
response_data: ResponseData,

// Raw move from response.zig

/// Response headers; instead of modifying these headers directly prefer calling
/// `headersAdd`
headers: Headers,
cookie_jar: Cookies.Jar,
// TODO document content_type
content_type: ?ContentType = ContentType.default,
status: ?std.http.Status = null,

wrote_headers: bool = false,

const Frame = @This();

pub const SendError = error{
    HeadersFinished,
} || NetworkError;

/// sendPage is the default way to respond in verse using the Template system.
/// sendPage will flush headers to the client before sending Page data
pub fn sendPage(vrs: *Frame, page: anytype) NetworkError!void {
    vrs.status = .ok;

    vrs.sendHeaders() catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => return error.IOWriteFailure,
    };

    try vrs.sendRawSlice("\r\n");

    switch (vrs.downstream) {
        .http, .zwsgi => |stream| {
            var vec_s = [_]std.posix.iovec_const{undefined} ** 2048;
            var vecs: []std.posix.iovec_const = vec_s[0..];
            const required = page.iovecCountAll();
            if (required > 2048) {
                vecs = vrs.alloc.alloc(std.posix.iovec_const, required) catch @panic("OOM");
            }
            const vec = page.ioVec(vecs, vrs.alloc) catch |iovec_err| {
                log.err("Error building iovec ({}) fallback to writer", .{iovec_err});
                const w = stream.writer();
                page.format("{}", .{}, w) catch |err| switch (err) {
                    else => log.err("Page Build Error {}", .{err}),
                };
                return;
            };
            stream.writevAll(vec) catch |err| switch (err) {
                else => log.err("iovec write error Error {} len {}", .{ err, vec.len }),
            };
            if (required > 2048) vrs.alloc.free(vecs);
        },
        .buffer => @panic("not implemented"),
    }
}

/// sendRawSlice will allow you to send data directly to the client. It will not
/// verify the current state, and will allow you to inject data into the HTTP
/// headers. If you only want to send response body data, use sendHTML instead.
pub fn sendRawSlice(vrs: *Frame, slice: []const u8) NetworkError!void {
    vrs.writeAll(slice) catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => return error.IOWriteFailure,
    };
}

pub const NetworkJsonError = NetworkError || error{OutOfMemory};

/// Takes a any object, that can be represented by json, converts it into a
/// json string, and sends to the client.
pub fn sendJSON(vrs: *Frame, comptime code: std.http.Status, json: anytype) NetworkJsonError!void {
    if (code == .no_content) {
        @compileError("Sending JSON is not supported with status code no content");
    }

    vrs.status = code;
    vrs.content_type = .{
        .base = .{ .application = .json },
        .parameter = .@"utf-8",
    };

    vrs.sendHeaders() catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => return error.IOWriteFailure,
    };

    try vrs.sendRawSlice("\r\n");

    const data = std.json.stringifyAlloc(vrs.alloc, json, .{
        .emit_null_optional_fields = false,
    }) catch |err| {
        log.err("Error trying to print json {}", .{err});
        return error.OutOfMemory;
    };
    vrs.writeAll(data) catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => return error.IOWriteFailure,
    };
}

pub fn sendHTML(frame: *Frame, comptime code: std.http.Status, html: []const u8) NetworkError!void {
    frame.status = code;
    frame.content_type = .{
        .base = .{ .text = .html },
        .parameter = .@"utf-8",
    };

    frame.sendHeaders() catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => return error.IOWriteFailure,
    };

    try frame.sendRawSlice("\r\n");
    try frame.sendRawSlice(html);
}

pub fn redirect(vrs: *Frame, loc: []const u8, comptime scode: std.http.Status) NetworkError!void {
    vrs.status = switch (scode) {
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

    vrs.sendHeaders() catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => return error.IOWriteFailure,
    };

    var vect = [3]iovec_c{
        .{ .base = "Location: ".ptr, .len = 10 },
        .{ .base = loc.ptr, .len = loc.len },
        .{ .base = "\r\n\r\n".ptr, .len = 4 },
    };
    vrs.writevAll(vect[0..]) catch |err| switch (err) {
        error.BrokenPipe => return error.BrokenPipe,
        else => return error.IOWriteFailure,
    };
}

pub fn acceptWebsocket(frame: *Frame) !Websocket {
    return Websocket.accept(frame);
}

pub fn init(a: Allocator, req: *const Request, auth: Auth.Provider) !Frame {
    return .{
        .alloc = a,
        .request = req,
        .downstream = switch (req.raw) {
            .zwsgi => |z| .{ .zwsgi = z.*.conn.stream },
            .http => .{ .http = req.raw.http.server.connection.stream },
        },
        .uri = try splitUri(req.uri),
        .auth_provider = auth,
        .headers = Headers.init(a),
        .user = auth.authenticate(&req.headers) catch null,
        .cookie_jar = try Cookies.Jar.init(a),
        .response_data = ResponseData.init(a),
    };
}

fn VecList(comptime SIZE: usize) type {
    return struct {
        pub const capacity = SIZE;
        vect: [SIZE]iovec_c = undefined,
        length: usize = 0,

        pub fn init() @This() {
            return .{};
        }

        pub fn append(self: *@This(), str: []const u8) !void {
            if (self.length >= capacity) return error.NoSpaceLeft;
            self.vect[self.length] = .{
                .base = str.ptr,
                .len = str.len,
            };
            self.length += 1;
        }
    };
}

pub fn sendHeaders(vrs: *Frame) SendError!void {
    if (vrs.wrote_headers) {
        return SendError.HeadersFinished;
    }

    switch (vrs.downstream) {
        .http, .zwsgi => |stream| {
            var vect = VecList(HEADER_VEC_COUNT).init();

            const h_resp = vrs.HttpHeader("HTTP/1.1");
            try vect.append(h_resp);

            // Default headers
            const s_name = "Server: verse/" ++ build_version ++ "\r\n";
            try vect.append(s_name);

            if (vrs.content_type) |ct| {
                try vect.append("Content-Type: ");
                switch (ct.base) {
                    inline else => |tag, name| {
                        try vect.append(@tagName(name));
                        try vect.append("/");
                        try vect.append(@tagName(tag));
                    },
                }
                if (ct.parameter) |param| {
                    const pre = "; charset=";
                    try vect.append(pre);
                    const tag = @tagName(param);
                    try vect.append(tag);
                }
                try vect.append("\r\n");
                //"text/html; charset=utf-8"); // Firefox is trash
            }

            var itr = vrs.headers.iterator();
            while (itr.next()) |header| {
                try vect.append(header.name);
                try vect.append(": ");
                try vect.append(header.value);
                try vect.append("\r\n");
            }

            for (vrs.cookie_jar.cookies.items) |cookie| {
                const used = try cookie.writeVec(vect.vect[vect.length..]);
                vect.length += used;
                try vect.append("\r\n");
            }

            stream.writevAll(vect.vect[0..vect.length]) catch return error.IOWriteFailure;
        },
        .buffer => @panic("not implemented"),
    }

    vrs.wrote_headers = true;
}

/// Helper function to return a default error page for a given http status code.
pub fn sendError(vrs: *Frame, comptime code: std.http.Status) !void {
    return Router.defaultResponse(code)(vrs);
}

pub fn headersAdd(vrs: *Frame, comptime name: []const u8, value: []const u8) !void {
    try vrs.headers.addCustom(name, value);
}

const ONESHOT_SIZE = 14720;
const HEADER_VEC_COUNT = 64; // 64 ought to be enough for anyone!

const Downstream = enum {
    buffer,
    zwsgi,
    http,
};

const VarPair = struct {
    []const u8,
    []const u8,
};

// The remaining functions are internal

fn writeAll(vrs: Frame, data: []const u8) !void {
    var index: usize = 0;
    while (index < data.len) {
        index += try write(vrs, data[index..]);
    }
}

fn writevAll(vrs: Frame, vect: []iovec_c) !void {
    switch (vrs.downstream) {
        .zwsgi, .http => |stream| try stream.writevAll(vect),
        .buffer => @panic("not implemented"),
    }
}

/// Raw writer, use with caution!
fn write(vrs: Frame, data: []const u8) !usize {
    return switch (vrs.downstream) {
        .zwsgi => |*w| try w.write(data),
        .http => |*w| return try w.write(data),
        .buffer => return try vrs.write(data),
    };
}

fn flush(vrs: Frame) !void {
    switch (vrs.downstream) {
        .buffer => |*w| try w.flush(),
        .http => |*h| h.flush(),
        .zwsgi => {},
    }
}

fn HttpHeader(vrs: *Frame, comptime ver: []const u8) [:0]const u8 {
    if (vrs.status == null) vrs.status = .ok;
    return switch (vrs.status.?) {
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
            log.err("Status code not implemented {}", .{vrs.status.?});
            break :b ver ++ " 500 Internal Server Error\r\n";
        },
    };
}

pub fn dumpDebugData(frame: *const Frame) void {
    switch (frame.request.raw) {
        .zwsgi => |zw| {
            for (zw.vars) |varr| {
                std.debug.print("DumpDebug '{s}' => '''{s}'''\n", .{ varr.key, varr.val });
            }
        },
        .http => |http| {
            var itr_headers = http.iterateHeaders();
            while (itr_headers.next()) |header| {
                std.debug.print("DumpDebug request header => {s} -> {s}\n", .{ header.name, header.value });
            }
        },
    }
    if (frame.request.data.post) |post_data| {
        std.debug.print("post data => '''{s}'''\n", .{post_data.rawpost});
    }
}

test "Verse" {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const Stream = std.net.Stream;
const AnyWriter = std.io.AnyWriter;
const bufPrint = std.fmt.bufPrint;
const allocPrint = std.fmt.allocPrint;
const splitScalar = std.mem.splitScalar;
const log = std.log.scoped(.Verse);
const iovec = std.posix.iovec;
const iovec_c = std.posix.iovec_const;

const Server = @import("server.zig");
const Request = @import("request.zig");
const RequestData = @import("request-data.zig");
const Template = @import("template.zig");
const Router = @import("router.zig");
const splitUri = Router.splitUri;

const Headers = @import("headers.zig");
const Auth = @import("auth.zig");
const Cookies = @import("cookies.zig");
const ContentType = @import("content-type.zig");
const ResponseData = @import("response-data.zig");
const Websocket = @import("websocket.zig");

const Error = @import("errors.zig").Error;
const NetworkError = @import("errors.zig").NetworkError;

const verse_buildopts = @import("verse_buildopts");
const build_version = verse_buildopts.version;
