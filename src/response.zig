const std = @import("std");
const bufPrint = std.fmt.bufPrint;
const Allocator = std.mem.Allocator;
const AnyWriter = std.io.AnyWriter;
const Stream = std.net.Stream;

const Request = @import("request.zig");
const Headers = @import("headers.zig");
const Cookies = @import("cookies.zig");

const Response = @This();

const ONESHOT_SIZE = 14720;

const Pair = struct {
    name: []const u8,
    val: []const u8,
};

pub const TransferMode = enum {
    static,
    streaming,
    proxy,
    proxy_streaming,
};

const Downstream = enum {
    buffer,
    zwsgi,
    http,
};

const Error = error{
    WrongPhase,
    HeadersFinished,
    ResponseClosed,
    UnknownStatus,
};

pub const Writer = std.io.Writer(*Response, Error, write);

alloc: Allocator,
headers: Headers,
tranfer_mode: TransferMode = .static,
// This is just bad code, but I need to give the sane implementation more thought
stdhttp: struct {
    request: ?*std.http.Server.Request = null,
    response: ?std.http.Server.Response = null,
} = .{},
downstream: union(Downstream) {
    buffer: std.io.BufferedWriter(ONESHOT_SIZE, Stream.Writer),
    zwsgi: Stream.Writer,
    http: std.io.AnyWriter,
},
cookie_jar: Cookies.Jar,
status: ?std.http.Status = null,

pub fn init(a: Allocator, req: *const Request) !Response {
    var self = Response{
        .alloc = a,
        .headers = Headers.init(a),
        .downstream = switch (req.raw) {
            .zwsgi => |z| .{ .zwsgi = z.*.acpt.stream.writer() },
            .http => .{ .http = undefined },
        },
        .cookie_jar = try Cookies.Jar.init(a),
    };
    switch (req.raw) {
        .http => |h| {
            self.stdhttp.request = h;
        },
        else => {},
    }
    self.headersInit() catch @panic("unable to create Response obj");
    return self;
}

fn headersInit(res: *Response) !void {
    try res.headersAdd("Server", "zwsgi/0.0.0");
    try res.headersAdd("Content-Type", "text/html; charset=utf-8"); // Firefox is trash
}

pub fn headersAdd(res: *Response, comptime name: []const u8, value: []const u8) !void {
    try res.headers.add(name, value);
}

pub fn start(res: *Response) !void {
    if (res.status == null) res.status = .ok;

    switch (res.downstream) {
        .http => {
            res.stdhttp.response = res.stdhttp.request.?.*.respondStreaming(.{
                .send_buffer = try res.alloc.alloc(u8, 0xffffff),
                .respond_options = .{
                    .transfer_encoding = .chunked,
                    .keep_alive = false,
                    .extra_headers = @ptrCast(try res.cookie_jar.toHeaderSlice(res.alloc)),
                },
            });
            // I don't know why/where the writer goes invalid, but I'll probably
            // fix it later?
            if (res.stdhttp.response) |*h| res.downstream.http = h.writer();
            try res.sendHeaders();
        },
        else => {
            try res.sendHeaders();
            for (res.cookie_jar.cookies.items) |cookie| {
                var buffer: [1024]u8 = undefined;
                const cookie_str = try bufPrint(&buffer, "{header}\r\n", .{cookie});
                _ = try res.write(cookie_str);
            }

            _ = try res.write("\r\n");
        },
    }
}

fn sendHTTPHeader(res: *Response) !void {
    if (res.status == null) res.status = .ok;
    switch (res.status.?) {
        .ok => try res.writeAll("HTTP/1.1 200 OK\r\n"),
        .found => try res.writeAll("HTTP/1.1 302 Found\r\n"),
        .forbidden => try res.writeAll("HTTP/1.1 403 Forbidden\r\n"),
        .not_found => try res.writeAll("HTTP/1.1 404 Not Found\r\n"),
        .internal_server_error => try res.writeAll("HTTP/1.1 500 Internal Server Error\r\n"),
        else => return Error.UnknownStatus,
    }
}

pub fn sendHeaders(res: *Response) !void {
    switch (res.downstream) {
        .http => try res.stdhttp.response.?.flush(),
        .zwsgi, .buffer => {
            try res.sendHTTPHeader();
            var itr = res.headers.headers.iterator();
            while (itr.next()) |header| {
                var buf: [512]u8 = undefined;
                const b = try std.fmt.bufPrint(&buf, "{s}: {s}\r\n", .{
                    header.key_ptr.*,
                    header.value_ptr.*.value,
                });
                _ = try res.write(b);
            }
            _ = try res.write("Transfer-Encoding: chunked\r\n");
        },
    }
}

pub fn redirect(res: *Response, loc: []const u8, see_other: bool) !void {
    try res.writeAll("HTTP/1.1 ");
    if (see_other) {
        try res.writeAll("303 See Other\r\n");
    } else {
        try res.writeAll("302 Found\r\n");
    }

    try res.writeAll("Location: ");
    try res.writeAll(loc);
    try res.writeAll("\r\n\r\n");
}

pub fn writer(res: *const Response) AnyWriter {
    return .{
        .writeFn = typeErasedWrite,
        .context = @ptrCast(&res),
    };
}

pub fn writeChunk(res: Response, data: []const u8) !void {
    comptime unreachable;
    var size: [19]u8 = undefined;
    const chunk = try bufPrint(&size, "{x}\r\n", .{data.len});
    try res.writeAll(chunk);
    try res.writeAll(data);
    try res.writeAll("\r\n");
}

pub fn writeAll(res: Response, data: []const u8) !void {
    var index: usize = 0;
    while (index < data.len) {
        index += try write(res, data[index..]);
    }
}

pub fn typeErasedWrite(opq: *const anyopaque, data: []const u8) anyerror!usize {
    const ptr: *const Response = @alignCast(@ptrCast(opq));
    return try write(ptr.*, data);
}

/// Raw writer, use with caution! To use phase checking, use send();
pub fn write(res: Response, data: []const u8) !usize {
    return switch (res.downstream) {
        .zwsgi => |*w| try w.write(data),
        .http => |*w| return try w.write(data),
        .buffer => return try res.write(data),
    };
}

fn flush(res: Response) !void {
    switch (res.downstream) {
        .buffer => |*w| try w.flush(),
        .http => |*h| h.flush(),
        else => {},
    }
}

pub fn finish(res: *Response) !void {
    switch (res.downstream) {
        .http => {
            if (res.stdhttp.response) |*h| try h.endChunked(.{});
        },
        else => {},
    }
}
