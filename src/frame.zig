alloc: Allocator,
request: *const Request,
downstream: union(Downstream) {
    buffer: std.io.BufferedWriter(ONESHOT_SIZE, Stream.Writer),
    zwsgi: Stream,
    http: Stream,
},
uri: Router.UriIterator,

// TODO fix this unstable API
auth_provider: Auth.Provider,
/// user is set to exactly what is provided directly by the active Auth.Provider.
/// It's possible for an Auth.Provider to return a User that is invalid.
/// Depending on the need for any given use, users should always verify the
/// validity in addition to the existence of this user field.
user: ?Auth.User = null,
/// The RouteData API is currently unstable, use with caution
route_data: RouteData,

// Raw move from response.zig
headers: Headers,
content_type: ?ContentType = ContentType.default,
cookie_jar: Cookies.Jar,
status: ?std.http.Status = null,

const Frame = @This();

const SendError = error{
    WrongPhase,
    HeadersFinished,
    ResponseClosed,
    UnknownStatus,
} || NetworkError;

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

/// Warning leaks like a sieve while I ponder the API
pub const RouteData = struct {
    items: std.ArrayList(Pair),

    pub const Pair = struct {
        name: []const u8,
        data: *const anyopaque,
    };

    pub fn add(self: *RouteData, comptime name: []const u8, data: *const anyopaque) !void {
        for (self.items.items) |each| {
            if (eql(u8, each.name, name)) return error.Exists;
        }

        try self.items.append(.{ .name = name, .data = data });
    }

    pub fn get(self: RouteData, comptime name: []const u8, T: type) !T {
        for (self.items.items) |each| {
            if (eql(u8, each.name, name)) return @as(T, @ptrCast(@alignCast(each.data)));
        } else return error.NotFound;
    }
};

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
        .cookie_jar = try Cookies.Jar.init(a),
        .route_data = .{ .items = std.ArrayList(RouteData.Pair).init(a) },
    };
}

pub fn headersAdd(vrs: *Frame, comptime name: []const u8, value: []const u8) !void {
    try vrs.headers.add(name, value);
}

fn writeChunk(vrs: Frame, data: []const u8) !void {
    comptime unreachable;
    var size: [19]u8 = undefined;
    const chunk = try bufPrint(&size, "{x}\r\n", .{data.len});
    try vrs.writeAll(chunk);
    try vrs.writeAll(data);
    try vrs.writeAll("\r\n");
}

fn writeAll(vrs: Frame, data: []const u8) !void {
    var index: usize = 0;
    while (index < data.len) {
        index += try write(vrs, data[index..]);
    }
}

fn writevAll(vrs: Frame, vect: []iovec_c) !void {
    switch (vrs.downstream) {
        .zwsgi, .http => |stream| try stream.writevAll(vect),
        else => unreachable,
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
        else => {},
    }
}

fn HTTPHeader(vrs: *Frame) ![:0]const u8 {
    if (vrs.status == null) vrs.status = .ok;
    return switch (vrs.status.?) {
        .ok => "HTTP/1.1 200 OK\r\n",
        .created => "HTTP/1.1 201 Created\r\n",
        .no_content => "HTTP/1.1 204 No Content\r\n",
        .found => "HTTP/1.1 302 Found\r\n",
        .bad_request => "HTTP/1.1 400 Bad Request\r\n",
        .unauthorized => "HTTP/1.1 401 Unauthorized\r\n",
        .forbidden => "HTTP/1.1 403 Forbidden\r\n",
        .not_found => "HTTP/1.1 404 Not Found\r\n",
        .method_not_allowed => "HTTP/1.1 405 Method Not Allowed\r\n",
        .conflict => "HTTP/1.1 409 Conflict\r\n",
        .payload_too_large => "HTTP/1.1 413 Content Too Large\r\n",
        .internal_server_error => "HTTP/1.1 500 Internal Server Error\r\n",
        else => return SendError.UnknownStatus,
    };
}

pub fn sendHeaders(vrs: *Frame) !void {
    switch (vrs.downstream) {
        .http, .zwsgi => |stream| {
            var vect: [HEADER_VEC_COUNT]iovec_c = undefined;
            var count: usize = 0;

            const h_resp = try vrs.HTTPHeader();
            vect[count] = .{ .base = h_resp.ptr, .len = h_resp.len };
            count += 1;

            // Default headers
            const s_name = "Server: verse/0.0.0-dev\r\n";
            vect[count] = .{ .base = s_name.ptr, .len = s_name.len };
            count += 1;

            if (vrs.content_type) |ct| {
                vect[count] = .{ .base = "Content-Type: ".ptr, .len = "Content-Type: ".len };
                count += 1;
                switch (ct.base) {
                    inline else => |tag, name| {
                        vect[count] = .{
                            .base = @tagName(name).ptr,
                            .len = @tagName(name).len,
                        };
                        count += 1;
                        vect[count] = .{ .base = "/".ptr, .len = "/".len };
                        count += 1;
                        vect[count] = .{
                            .base = @tagName(tag).ptr,
                            .len = @tagName(tag).len,
                        };
                        count += 1;
                    },
                }
                if (ct.parameter) |param| {
                    const pre = "; charset=";
                    vect[count] = .{ .base = pre.ptr, .len = pre.len };
                    count += 1;
                    const tag = @tagName(param);
                    vect[count] = .{ .base = tag.ptr, .len = tag.len };
                    count += 1;
                }

                vect[count] = .{ .base = "\r\n".ptr, .len = "\r\n".len };
                count += 1;

                //"text/html; charset=utf-8"); // Firefox is trash
            }

            var itr = vrs.headers.iterator();
            while (itr.next()) |header| {
                vect[count] = .{ .base = header.name.ptr, .len = header.name.len };
                count += 1;
                vect[count] = .{ .base = ": ".ptr, .len = ": ".len };
                count += 1;
                vect[count] = .{ .base = header.value.ptr, .len = header.value.len };
                count += 1;
                vect[count] = .{ .base = "\r\n".ptr, .len = "\r\n".len };
                count += 1;
            }

            for (vrs.cookie_jar.cookies.items) |cookie| {
                vect[count] = .{ .base = "Set-Cookie: ".ptr, .len = "Set-Cookie: ".len };
                count += 1;
                // TODO remove this alloc
                const cookie_str = allocPrint(vrs.alloc, "{}", .{cookie}) catch unreachable;
                vect[count] = .{
                    .base = cookie_str.ptr,
                    .len = cookie_str.len,
                };
                count += 1;
                vect[count] = .{ .base = "\r\n".ptr, .len = "\r\n".len };
                count += 1;
            }

            try stream.writevAll(vect[0..count]);
        },
        .buffer => unreachable,
    }
}

pub fn redirect(vrs: *Frame, loc: []const u8, see_other: bool) !void {
    const code = if (see_other) "303 See Other\r\n" else "302 Found\r\n";
    var vect = [5]iovec_c{
        .{ .base = "HTTP/1.1 ".ptr, .len = 9 },
        .{ .base = code.ptr, .len = code.len },
        .{ .base = "Location: ".ptr, .len = 10 },
        .{ .base = loc.ptr, .len = loc.len },
        .{ .base = "\r\n\r\n".ptr, .len = 4 },
    };
    try vrs.writevAll(vect[0..]);
}

/// sendPage is the default way to respond in verse using the Template system.
/// sendPage will flush headers to the client before sending Page data
pub fn sendPage(vrs: *Frame, page: anytype) NetworkError!void {
    try vrs.quickStart();

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
                else => log.err("iovec write error Error {}", .{err}),
            };
            if (required > 2048) vrs.alloc.free(vecs);
        },
        else => unreachable,
    }
}

/// sendRawSlice will allow you to send data directly to the client. It will not
/// verify the current state, and will allow you to inject data into the HTTP
/// headers. If you only want to send response body data, call quickStart() to
/// send all headers to the client
pub fn sendRawSlice(vrs: *Frame, slice: []const u8) NetworkError!void {
    vrs.writeAll(slice) catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => unreachable,
    };
}

/// Helper function to return a default error page for a given http status code.
pub fn sendError(vrs: *Frame, comptime code: std.http.Status) !void {
    return Router.defaultResponse(code)(vrs);
}

/// Takes a any object, that can be represented by json, converts it into a
/// json string, and sends to the client.
pub fn sendJSON(vrs: *Frame, json: anytype, comptime code: std.http.Status) !void {
    if (code == .no_content) {
        @compileError("Sending JSON is not supported with status code no content");
    }

    vrs.status = code;
    vrs.content_type = .{
        .base = .{ .application = .json },
        .parameter = .@"utf-8",
    };

    try vrs.quickStart();
    const data = std.json.stringifyAlloc(vrs.alloc, json, .{
        .emit_null_optional_fields = false,
    }) catch |err| {
        log.err("Error trying to print json {}", .{err});
        return error.Unknown;
    };
    vrs.writeAll(data) catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => unreachable,
    };
}

/// This function may be removed in the future
pub fn quickStart(vrs: *Frame) NetworkError!void {
    if (vrs.status == null) vrs.status = .ok;
    switch (vrs.downstream) {
        .http, .zwsgi => |_| {
            vrs.sendHeaders() catch |err| switch (err) {
                error.BrokenPipe => |e| return e,
                else => unreachable,
            };

            vrs.writeAll("\r\n") catch |err| switch (err) {
                error.BrokenPipe => |e| return e,
                else => unreachable,
            };
        },
        else => unreachable,
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
const RequestData = @import("request_data.zig");
const Template = @import("template.zig");
const Router = @import("router.zig");
const splitUri = Router.splitUri;

const Headers = @import("headers.zig");
const Auth = @import("auth.zig");
const Cookies = @import("cookies.zig");
const ContentType = @import("content-type.zig");

const Error = @import("errors.zig").Error;
const NetworkError = @import("errors.zig").NetworkError;
