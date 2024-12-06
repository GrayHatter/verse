pub const Verse = @This();
pub const Server = @import("server.zig");
pub const Request = @import("request.zig");
pub const RequestData = @import("request_data.zig");
pub const Template = @import("template.zig");
pub const Router = @import("router.zig");
pub const UriIter = Router.UriIter;

pub const Headers = @import("headers.zig");
pub const Auth = @import("auth.zig");
pub const Cookies = @import("cookies.zig");

const Error = @import("errors.zig").Error;
const NetworkError = @import("errors.zig").NetworkError;

alloc: Allocator,
request: *const Request,
reqdata: RequestData,
downstream: union(Downstream) {
    buffer: std.io.BufferedWriter(ONESHOT_SIZE, Stream.Writer),
    zwsgi: Stream,
    http: Stream,
},
uri: UriIter,

// TODO fix this unstable API
auth: Auth,
route_ctx: ?*const anyopaque = null,

// Raw move from response.zig

headers: Headers,
cookie_jar: Cookies.Jar,
status: ?std.http.Status = null,

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

pub fn init(a: Allocator, req: *const Request, reqdata: RequestData) !Verse {
    std.debug.assert(req.uri[0] == '/');
    var self = Verse{
        .alloc = a,
        .request = req,
        .reqdata = reqdata,
        .downstream = switch (req.raw) {
            .zwsgi => |z| .{ .zwsgi = z.*.acpt.stream },
            .http => .{ .http = req.raw.http.server.connection.stream },
        },
        .uri = splitScalar(u8, req.uri[1..], '/'),
        .auth = Auth{
            .provider = Auth.InvalidProvider.empty(),
        },
        .headers = Headers.init(a),
        .cookie_jar = try Cookies.Jar.init(a),
    };
    try self.headersAdd("Server", "zwsgi/0.0.0");
    try self.headersAdd("Content-Type", "text/html; charset=utf-8"); // Firefox is trash
    return self;
}

pub fn headersAdd(vrs: *Verse, comptime name: []const u8, value: []const u8) !void {
    try vrs.headers.add(name, value);
}

fn writeChunk(vrs: Verse, data: []const u8) !void {
    comptime unreachable;
    var size: [19]u8 = undefined;
    const chunk = try bufPrint(&size, "{x}\r\n", .{data.len});
    try vrs.writeAll(chunk);
    try vrs.writeAll(data);
    try vrs.writeAll("\r\n");
}

fn writeAll(vrs: Verse, data: []const u8) !void {
    var index: usize = 0;
    while (index < data.len) {
        index += try write(vrs, data[index..]);
    }
}

fn writevAll(vrs: Verse, vect: []iovec_c) !void {
    switch (vrs.downstream) {
        .zwsgi, .http => |stream| try stream.writevAll(vect),
        else => unreachable,
    }
}

/// Raw writer, use with caution!
fn write(vrs: Verse, data: []const u8) !usize {
    return switch (vrs.downstream) {
        .zwsgi => |*w| try w.write(data),
        .http => |*w| return try w.write(data),
        .buffer => return try vrs.write(data),
    };
}

fn flush(vrs: Verse) !void {
    switch (vrs.downstream) {
        .buffer => |*w| try w.flush(),
        .http => |*h| h.flush(),
        else => {},
    }
}

fn HTTPHeader(vrs: *Verse) ![:0]const u8 {
    if (vrs.status == null) vrs.status = .ok;
    return switch (vrs.status.?) {
        .ok => "HTTP/1.1 200 OK\r\n",
        .found => "HTTP/1.1 302 Found\r\n",
        .forbidden => "HTTP/1.1 403 Forbidden\r\n",
        .not_found => "HTTP/1.1 404 Not Found\r\n",
        .internal_server_error => "HTTP/1.1 500 Internal Server Error\r\n",
        else => return SendError.UnknownStatus,
    };
}

pub fn sendHeaders(vrs: *Verse) !void {
    switch (vrs.downstream) {
        .http, .zwsgi => |stream| {
            var vect: [HEADER_VEC_COUNT]iovec_c = undefined;
            var count: usize = 0;

            const h_resp = try vrs.HTTPHeader();
            vect[count] = .{ .base = h_resp.ptr, .len = h_resp.len };
            count += 1;

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

pub fn redirect(vrs: *Verse, loc: []const u8, see_other: bool) !void {
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
pub fn sendPage(vrs: *Verse, page: anytype) NetworkError!void {
    try vrs.quickStart();
    const loggedin = if (vrs.auth.valid()) "<a href=\"#\">Logged In</a>" else "Public";
    const T = @TypeOf(page.*);
    if (@hasField(T, "data") and @hasField(@TypeOf(page.data), "body_header")) {
        page.data.body_header.?.nav.?.nav_auth = loggedin;
    }

    switch (vrs.downstream) {
        .http, .zwsgi => |stream| {
            const w = stream.writer();
            page.format("{}", .{}, w) catch |err| switch (err) {
                else => log.err("Page Build Error {}", .{err}),
            };
        },
        else => unreachable,
    }
}

/// sendRawSlice will allow you to send data directly to the client. It will not
/// verify the current state, and will allow you to inject data into the HTTP
/// headers. If you only want to send response body data, call quickStart() to
/// send all headers to the client
pub fn sendRawSlice(vrs: *Verse, slice: []const u8) NetworkError!void {
    vrs.writeAll(slice) catch |err| switch (err) {
        error.BrokenPipe => |e| return e,
        else => unreachable,
    };
}

/// Helper function to return a default error page for a given http status code.
pub fn sendError(vrs: *Verse, comptime code: std.http.Status) !void {
    return Router.defaultResponse(code)(vrs);
}

/// Takes a any object, that can be represented by json, converts it into a
/// json string, and sends to the client.
pub fn sendJSON(vrs: *Verse, json: anytype) !void {
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
pub fn quickStart(vrs: *Verse) NetworkError!void {
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

pub const std = @import("std");
const Allocator = std.mem.Allocator;
const Stream = std.net.Stream;
const AnyWriter = std.io.AnyWriter;
const bufPrint = std.fmt.bufPrint;
const allocPrint = std.fmt.allocPrint;
const splitScalar = std.mem.splitScalar;
const log = std.log.scoped(.Verse);
const iovec = std.posix.iovec;
const iovec_c = std.posix.iovec_const;
