const Request = @This();

pub const Data = @import("request-data.zig");
pub const UserAgent = @import("user-agent.zig");

/// Unstable API; likely to exist in some form, but might be changed
remote_addr: RemoteAddr,
method: Methods,
uri: []const u8,
host: ?Host,
user_agent: ?UserAgent,
referer: ?Referer,
accept: ?Accept,
accept_encoding: Encoding = .default,
authorization: ?Authorization,
protocol: Protocol,

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
        inline for (@typeInfo(Encoding).@"struct".fields) |f| {
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

pub const Methods = enum(u9) {
    GET = 1,
    HEAD = 2,
    POST = 4,
    PUT = 8,
    DELETE = 16,
    CONNECT = 32,
    OPTIONS = 64,
    TRACE = 128,
    WEBSOCKET = 256,

    pub fn fromStr(s: []const u8) !Methods {
        inline for (std.meta.fields(Methods)) |field| {
            if (std.mem.startsWith(u8, s, field.name)) {
                return @enumFromInt(field.value);
            }
        }
        return error.UnknownMethod;
    }

    pub fn format(m: Methods, comptime _: []const u8, _: std.fmt.FormatOptions, w: anytype) !void {
        switch (m) {
            inline else => |e| try w.writeAll(@tagName(e)),
        }
    }
};

pub const Protocol = struct {
    // TODO split name and version
    str: []const u8,
};

fn initCommon(
    a: Allocator,
    remote_addr: RemoteAddr,
    _method: Methods,
    uri: []const u8,
    host: ?Host,
    ua: ?[]const u8,
    referer: ?Referer,
    accept: ?Accept,
    accept_encoding: Encoding,
    authorization: ?Authorization,
    headers: Headers,
    cookies: ?[]const u8,
    proto: []const u8,
    data: Data,
    raw: RawReq,
) !Request {
    var method = _method;
    if (headers.getCustom("Upgrade")) |val| {
        std.debug.print("Upgrade: {s}\n", .{val.value_list.value});
        method = Methods.WEBSOCKET;
    }

    return .{
        .accept = accept,
        .accept_encoding = accept_encoding,
        .authorization = authorization,
        .cookie_jar = if (cookies) |ch| try Cookies.Jar.initFromHeader(a, ch) else try Cookies.Jar.init(a),
        .data = data,
        .headers = headers,
        .host = host,
        .method = method,
        .raw = raw,
        .referer = referer,
        .remote_addr = remote_addr,
        .uri = uri,
        .user_agent = if (ua) |u| .init(u) else null,
        .protocol = .{ .str = proto },
    };
}

pub fn initZWSGI(a: Allocator, zwsgi: *zWSGIRequest, data: Data) !Request {
    var uri: ?[]const u8 = null;
    var method: ?Methods = null;
    var remote_addr: ?RemoteAddr = null;
    var headers = Headers.init(a);
    var accept: ?Accept = null;
    var host: ?Host = null;
    var ua_slice: ?[]const u8 = null;
    var referer: ?Referer = null;
    var encoding: Encoding = Encoding.default;
    var authorization: ?Authorization = null;
    var cookie_header: ?[]const u8 = null;
    var proto: []const u8 = "ERROR";

    for (zwsgi.vars) |v| {
        try headers.addCustom(v.key, v.val);
        if (eql(u8, v.key, "PATH_INFO")) {
            uri = v.val;
        } else if (eql(u8, v.key, "REQUEST_METHOD")) {
            method = Methods.fromStr(v.val) catch {
                std.debug.print("Unsupported Method seen '{any}'", .{v.val});
                return error.InvalidRequest;
            };
        } else if (eql(u8, v.key, "REMOTE_ADDR")) {
            remote_addr = v.val;
        } else if (eqlIgnoreCase("HTTP_ACCEPT", v.key)) {
            accept = v.val;
        } else if (eqlIgnoreCase("HTTP_HOST", v.key)) {
            host = v.val;
        } else if (eqlIgnoreCase("HTTP_USER_AGENT", v.key)) {
            ua_slice = v.val;
        } else if (eqlIgnoreCase("HTTP_REFERER", v.key)) {
            referer = v.val;
        } else if (eqlIgnoreCase("HTTP_ACCEPT_ENCODING", v.key)) {
            encoding = Encoding.fromStr(v.val);
        } else if (eqlIgnoreCase("HTTP_AUTHORIZATION", v.key)) {
            authorization = v.val;
        } else if (eqlIgnoreCase("HTTP_COOKIE", v.key)) {
            cookie_header = v.val;
        } else if (eqlIgnoreCase("SERVER_PROTOCOL", v.key)) {
            proto = v.val;
        }
    }

    return initCommon(
        a,
        remote_addr orelse return error.InvalidRequest,
        method orelse return error.InvalidRequest,
        uri orelse return error.InvalidRequest,
        host,
        ua_slice,
        referer,
        accept,
        encoding,
        authorization,
        headers,
        cookie_header,
        proto,
        data,
        .{ .zwsgi = zwsgi },
    );
}

pub fn initHttp(a: Allocator, http: *std.http.Server.Request, data: Data) !Request {
    var itr = http.iterateHeaders();
    var headers = Headers.init(a);

    var accept: ?Accept = null;
    var host: ?Host = null;
    var ua_string: ?[]const u8 = null;
    var referer: ?Referer = null;
    var encoding: Encoding = Encoding.default;
    var authorization: ?Authorization = null;
    var cookie_header: ?[]const u8 = null;
    const proto: []const u8 = @tagName(http.head.version);

    while (itr.next()) |head| {
        try headers.addCustom(head.name, head.value);
        if (eqlIgnoreCase("accept", head.name)) {
            accept = head.value;
        } else if (eqlIgnoreCase("host", head.name)) {
            host = head.value;
        } else if (eqlIgnoreCase("user-agent", head.name)) {
            ua_string = head.value;
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
    var ipbuf: [48]u8 = undefined;
    const ipport = try bufPrint(&ipbuf, "{}", .{http.server.connection.address});
    if (lastIndexOfScalar(u8, ipport, ':')) |i| {
        // TODO lower this to remove the a.dupe
        remote_addr = try a.dupe(u8, ipport[0..i]);
    } else @panic("invalid address from http server");

    return initCommon(
        a,
        remote_addr,
        translateStdHttp(http.head.method),
        http.head.target,
        host,
        ua_string,
        referer,
        accept,
        encoding,
        authorization,
        headers,
        cookie_header,
        proto,
        data,
        .{ .http = http },
    );
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

const Headers = @import("headers.zig");
const Cookies = @import("cookies.zig");
const zWSGIRequest = @import("zwsgi.zig").zWSGIRequest;

test "req" {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const indexOf = std.mem.indexOf;
const lastIndexOfScalar = std.mem.lastIndexOfScalar;
const eql = std.mem.eql;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
const allocPrint = std.fmt.allocPrint;
const bufPrint = std.fmt.bufPrint;
