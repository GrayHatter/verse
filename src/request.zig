const std = @import("std");
const Allocator = std.mem.Allocator;
const indexOf = std.mem.indexOf;
const indexOfScalar = std.mem.indexOfScalar;
const eql = std.mem.eql;
const allocPrint = std.fmt.allocPrint;

const Headers = @import("headers.zig");
const Cookies = @import("cookies.zig");

const zWSGIRequest = @import("zwsgi.zig").zWSGIRequest;

pub const Request = @This();

/// TODO this is unstable and likely to be removed
raw: RawReq,

/// Default API, still unstable, but unlike to drastically change
headers: Headers,
uri: []const u8,
method: Methods,
cookie_jar: Cookies.Jar,

/// Unstable API; likely to exist in some form, but might be changed
remote_addr: RemoteAddr,

pub const RawReq = union(enum) {
    zwsgi: *zWSGIRequest,
    http: *std.http.Server.Request,
};

const Pair = struct {
    name: []const u8,
    val: []const u8,
};

pub const RemoteAddr = []const u8;

pub const Methods = enum(u8) {
    GET = 1,
    HEAD = 2,
    POST = 4,
    PUT = 8,
    DELETE = 16,
    CONNECT = 32,
    OPTIONS = 64,
    TRACE = 128,

    pub fn fromStr(s: []const u8) !Methods {
        inline for (std.meta.fields(Methods)) |field| {
            if (std.mem.startsWith(u8, s, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return error.UnknownMethod;
    }
};

pub fn initZWSGI(a: Allocator, zwsgi: *zWSGIRequest) !Request {
    var req = Request{
        .raw = .{ .zwsgi = zwsgi },
        .headers = Headers.init(a),
        .method = Methods.GET,
        .uri = undefined,
        .cookie_jar = undefined,
        .remote_addr = undefined,
    };
    for (zwsgi.vars) |v| {
        try req.addHeader(v.key, v.val);
        if (eql(u8, v.key, "PATH_INFO")) {
            req.uri = v.val;
        } else if (eql(u8, v.key, "REQUEST_METHOD")) {
            req.method = Methods.fromStr(v.val) catch Methods.GET;
        } else if (eql(u8, v.key, "REMOTE_ADDR")) {
            req.remote_addr = v.val;
        }
    }
    req.cookie_jar = try Cookies.Jar.initFromHeaders(a, &req.headers);
    return req;
}

pub fn initHttp(a: Allocator, http: *std.http.Server.Request) !Request {
    var req = Request{
        .raw = .{ .http = http },
        .headers = Headers.init(a),
        .uri = http.head.target,
        .method = switch (http.head.method) {
            .GET => .GET,
            .POST => .POST,
            .HEAD => .HEAD,
            .PUT => .PUT,
            .DELETE => .DELETE,
            .CONNECT => .CONNECT,
            .OPTIONS => .OPTIONS,
            .TRACE => .TRACE,
            else => @panic("not implemented"),
        },
        .cookie_jar = undefined,
        .remote_addr = undefined,
    };
    var itr = http.iterateHeaders();
    while (itr.next()) |head| {
        try req.addHeader(head.name, head.value);
    }
    req.cookie_jar = try Cookies.Jar.initFromHeaders(a, &req.headers);

    const ipport = try allocPrint(a, "{}", .{http.server.connection.address});
    if (indexOfScalar(u8, ipport, ':')) |i| {
        req.remote_addr = ipport[0..i];
        try req.addHeader("REMOTE_ADDR", req.remote_addr);
        try req.addHeader("REMOTE_PORT", ipport[i + 1 ..]);
    } else @panic("invalid address from http server");

    return req;
}

pub fn addHeader(self: *Request, name: []const u8, val: []const u8) !void {
    try self.headers.add(name, val);
}

pub fn getHeader(self: Request, key: []const u8) ?[]const u8 {
    for (self.headers.items) |itm| {
        if (std.mem.eql(u8, itm.name, key)) {
            return itm.val;
        }
    } else {
        return null;
    }
}
