const Request = @This();

pub const Data = @import("request-data.zig");

/// Unstable API; likely to exist in some form, but might be changed
remote_addr: RemoteAddr,
method: Methods,
uri: []const u8,
host: ?[]const u8,
user_agent: ?UserAgent,
referer: ?[]const u8,
accept: ?Accept,
accept_encoding: Encoding = Encoding.default,
authorization: ?[]const u8,

headers: Headers,
/// Default API, still unstable, but unlike to drastically change
cookie_jar: Cookies.Jar,
/// POST or QUERY data
data: Data,
/// TODO this is unstable and likely to be removed
raw: RawReq,

pub const RawReq = union(enum) {
    zwsgi: *zWSGIRequest,
    http: *std.http.Server.Request,
};

const Pair = struct {
    name: []const u8,
    val: []const u8,
};

pub const Host = []const u8;
pub const RemoteAddr = []const u8;
pub const UserAgent = []const u8;
pub const Accept = []const u8;
pub const Authorization = []const u8;
pub const Referer = []const u8;

pub const Encoding = packed struct(usize) {
    br: bool,
    deflate: bool,
    gzip: bool,
    zstd: bool,

    _padding: u60 = 0,

    pub fn fromStr(str: []const u8) Encoding {
        var e = Encoding.default;
        inline for (@typeInfo(Encoding).Struct.fields) |f| {
            if (indexOf(u8, str, f.name)) |_| {
                @field(e, f.name) = if (f.type == bool) true else 0;
            }
        }
        return e;
    }

    pub const default: Encoding = .{
        .br = false,
        .deflate = false,
        .gzip = false,
        .zstd = false,
    };
};

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

pub fn initZWSGI(a: Allocator, zwsgi: *zWSGIRequest, data: Data) !Request {
    var uri: ?[]const u8 = null;
    var method: Methods = Methods.GET;
    var remote_addr: RemoteAddr = undefined;
    var headers = Headers.init(a);
    var accept: ?Accept = null;
    var host: ?Host = null;
    var uagent: ?UserAgent = null;
    var referer: ?Referer = null;
    var encoding: Encoding = Encoding.default;
    var authorization: ?Authorization = null;
    var cookie_header: ?[]const u8 = null;

    for (zwsgi.vars) |v| {
        try headers.add(v.key, v.val);
        if (eql(u8, v.key, "PATH_INFO")) {
            uri = v.val;
        } else if (eql(u8, v.key, "REQUEST_METHOD")) {
            method = Methods.fromStr(v.val) catch Methods.GET;
        } else if (eql(u8, v.key, "REMOTE_ADDR")) {
            remote_addr = v.val;
        } else if (eqlIgnoreCase("HTTP_ACCEPT", v.key)) {
            accept = v.val;
        } else if (eqlIgnoreCase("HTTP_HOST", v.key)) {
            host = v.val;
        } else if (eqlIgnoreCase("HTTP_USER_AGENT", v.key)) {
            uagent = v.val;
        } else if (eqlIgnoreCase("HTTP_REFERER", v.key)) {
            referer = v.val;
        } else if (eqlIgnoreCase("HTTP_ACCEPT_ENCODING", v.key)) {
            encoding = Encoding.fromStr(v.val);
        } else if (eqlIgnoreCase("HTTP_AUTHORIZATION", v.key)) {
            authorization = v.val;
        } else if (eqlIgnoreCase("HTTP_COOKIE", v.key)) {
            cookie_header = v.val;
        }
    }
    return .{
        .remote_addr = remote_addr,
        .host = host,
        .user_agent = uagent,
        .accept = accept,
        .authorization = authorization,
        .referer = referer,
        .method = method,
        .uri = uri orelse return error.InvalidRequest,
        .headers = headers,
        .cookie_jar = if (cookie_header) |ch| try Cookies.Jar.initFromHeader(a, ch) else try Cookies.Jar.init(a),
        .data = data,
        .raw = .{ .zwsgi = zwsgi },
    };
}

pub fn initHttp(a: Allocator, http: *std.http.Server.Request, data: Data) !Request {
    var itr = http.iterateHeaders();
    var headers = Headers.init(a);

    var accept: ?Accept = null;
    var host: ?Host = null;
    var uagent: ?UserAgent = null;
    var referer: ?Referer = null;
    var encoding: Encoding = Encoding.default;
    var authorization: ?Authorization = null;
    var cookie_header: ?[]const u8 = null;

    while (itr.next()) |head| {
        try headers.add(head.name, head.value);
        if (eqlIgnoreCase("accept", head.name)) {
            accept = head.value;
        } else if (eqlIgnoreCase("host", head.name)) {
            host = head.value;
        } else if (eqlIgnoreCase("user-agent", head.name)) {
            uagent = head.value;
        } else if (eqlIgnoreCase("referer", head.name)) {
            referer = head.value;
        } else if (eqlIgnoreCase("accept-encoding", head.name)) {
            encoding = Encoding.fromStr(head.value);
        } else if (eqlIgnoreCase("authorization", head.name)) {
            authorization = head.value;
        } else if (eqlIgnoreCase("cookie", head.name)) {
            cookie_header = head.value;
        }
    }

    var remote_addr: RemoteAddr = undefined;
    const ipport = try allocPrint(a, "{}", .{http.server.connection.address});
    if (indexOfScalar(u8, ipport, ':')) |i| {
        remote_addr = ipport[0..i];
        try headers.add("REMOTE_ADDR", remote_addr);
        try headers.add("REMOTE_PORT", ipport[i + 1 ..]);
    } else @panic("invalid address from http server");

    return .{
        .remote_addr = remote_addr,
        .host = host,
        .user_agent = uagent,
        .accept = accept,
        .authorization = authorization,
        .referer = referer,
        .method = translateStdHttp(http.head.method),
        .uri = http.head.target,
        .headers = headers,
        .cookie_jar = if (cookie_header) |ch| try Cookies.Jar.initFromHeader(a, ch) else try Cookies.Jar.init(a),
        .data = data,
        .raw = .{ .http = http },
    };
}

fn translateStdHttp(m: std.http.Method) Methods {
    return switch (m) {
        .GET => .GET,
        .POST => .POST,
        .HEAD => .HEAD,
        .PUT => .PUT,
        .DELETE => .DELETE,
        .CONNECT => .CONNECT,
        .OPTIONS => .OPTIONS,
        .TRACE => .TRACE,
        else => @panic("not implemented"),
    };
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

const Headers = @import("headers.zig");
const Cookies = @import("cookies.zig");
const zWSGIRequest = @import("zwsgi.zig").zWSGIRequest;

const std = @import("std");
const Allocator = std.mem.Allocator;
const indexOf = std.mem.indexOf;
const indexOfScalar = std.mem.indexOfScalar;
const eql = std.mem.eql;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
const allocPrint = std.fmt.allocPrint;
