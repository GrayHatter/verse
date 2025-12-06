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
secure: bool,

headers: Headers,
/// Default API, still unstable, but unlike to drastically change
cookie_jar: Cookies.Jar,
/// POST or QUERY data
data: Data,

// Tentative API
now: Timestamp,

const Request = @This();

pub const Data = @import("request-data.zig");
pub const UserAgent = @import("user-agent.zig");
const Headers = @import("headers.zig");
const Cookies = @import("cookies.zig");

pub const Host = []const u8;
pub const RemoteAddr = []const u8;
pub const Accept = []const u8;
pub const Authorization = []const u8;
pub const Referer = []const u8;

pub const Encoding = packed struct {
    br: bool,
    deflate: bool,
    gzip: bool,
    zstd: bool,

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

    pub fn fromStdHttp(m: std.http.Method) Methods {
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

    pub fn readOnly(m: Methods) bool {
        return switch (m) {
            .GET, .HEAD, .OPTIONS => true,
            .POST, .PUT, .DELETE, .CONNECT, .TRACE, .WEBSOCKET => false,
        };
    }
};

pub const Protocol = union(enum) {
    // TODO split name and version
    http: Http,
    malformed: []const u8,

    pub fn parse(str: []const u8) Protocol {
        if (startsWith(u8, str, "HTTP/")) {
            inline for (Http.fields) |f| {
                if (eql(u8, str[5..], f.name)) return .{ .http = @as(Http, @enumFromInt(f.value)) };
            }
        }
        return .{ .malformed = str };
    }

    pub const Http = enum {
        @"1.0",
        @"1.1",
        @"2.0",

        pub const fields = @typeInfo(Http).@"enum".fields;
    };

    pub const default: Protocol = .{ .http = .@"1.1" };
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
    secure: bool,
    now: Timestamp,
) !Request {
    var method = _method;
    if (headers.getCustomValue("Upgrade")) |val| {
        log.info("Upgrade Header: {s}", .{val});
        method = Methods.WEBSOCKET;
    } else |_| {}

    return .{
        .accept = accept,
        .accept_encoding = accept_encoding,
        .authorization = authorization,
        .cookie_jar = if (cookies) |ch| try .initFromHeader(a, ch) else .init(a),
        .data = data,
        .headers = headers,
        .host = host,
        .method = method,
        .referer = referer,
        .remote_addr = remote_addr,
        .uri = uri,
        .user_agent = if (ua) |u| .init(u) else null,
        .protocol = .parse(proto),
        .secure = secure,
        .now = now,
    };
}

pub fn initZWSGI(a: Allocator, zwsgi: *zWSGIRequest, data: Data, now: Timestamp) !Request {
    const zk = &zwsgi.known;
    const uri: ?[]const u8 = zk.get(.REQUEST_PATH);
    const method = Methods.fromStr(zk.get(.REQUEST_METHOD) orelse "GET") catch {
        log.err("Unsupported Method seen '{any}'", .{zk.get(.REQUEST_METHOD)});
        return error.InvalidRequest;
    };
    const remote_addr: ?RemoteAddr = zk.get(.REMOTE_ADDR);
    const accept: ?Accept = zk.get(.HTTP_ACCEPT);
    const host: ?Host = zk.get(.HTTP_HOST);
    const ua_slice: ?[]const u8 = zk.get(.HTTP_USER_AGENT);
    const referer: ?Referer = zk.get(.HTTP_REFERER);
    const encoding: Encoding = if (zk.get(.HTTP_ACCEPT_ENCODING)) |ae| .fromStr(ae) else .default;
    const authorization: ?Authorization = zk.get(.HTTP_AUTHORIZATION);
    const cookie_header: ?[]const u8 = zk.get(.HTTP_COOKIE);
    const proto: []const u8 = zk.get(.SERVER_PROTOCOL) orelse "ERROR";
    const secure: bool = if (zk.get(.HTTPS)) |sec| eql(u8, sec, "on") else false;

    var headers: Headers = .empty;
    for (zwsgi.vars.items) |v| {
        try headers.addCustom(a, v.key, v.val);
    }
    // TODO replace this hack with better header support
    for ([_]zWSGIParam{ .MTLS_ENABLED, .MTLS_FINGERPRINT }) |key| {
        try headers.addCustom(a, @tagName(key), zwsgi.known.get(key) orelse continue);
    }

    return initCommon(
        a,
        remote_addr orelse return error.InvalidRequest,
        method,
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
        secure,
        now,
    );
}

pub fn initHttp(
    a: Allocator,
    http: *std.http.Server.Request,
    stream: *const Stream,
    data: Data,
    now: Timestamp,
) !Request {
    var headers: Headers = .empty;

    var accept: ?Accept = null;
    var host: ?Host = null;
    var ua_string: ?[]const u8 = null;
    var referer: ?Referer = null;
    var encoding: Encoding = Encoding.default;
    var authorization: ?Authorization = null;
    var cookie_header: ?[]const u8 = null;
    const proto: []const u8 = @tagName(http.head.version);

    var itr = http.iterateHeaders();
    while (itr.next()) |head| {
        try headers.addCustom(a, head.name, head.value);
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
    const ipport = try bufPrint(&ipbuf, "{f}", .{stream.socket.address});
    if (lastIndexOfScalar(u8, ipport, ':')) |i| {
        // TODO lower this to remove the a.dupe
        remote_addr = try a.dupe(u8, ipport[0..i]);
    } else @panic("invalid address from http server");

    return initCommon(
        a,
        remote_addr,
        .fromStdHttp(http.head.method),
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
        false, // https isn't currently supported using verse internal http
        now,
    );
}

test Request {
    std.testing.refAllDecls(Request);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Stream = std.Io.net.Stream;
const Timestamp = std.Io.Timestamp;
const log = std.log.scoped(.verse);
const indexOf = std.mem.indexOf;
const startsWith = std.mem.startsWith;
const lastIndexOfScalar = std.mem.lastIndexOfScalar;
const eql = std.mem.eql;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
const allocPrint = std.fmt.allocPrint;
const bufPrint = std.fmt.bufPrint;

const IOVec = @import("iovec.zig").IOVec;
const zWSGIParam = @import("zwsgi.zig").zWSGIParam;
const zWSGIRequest = @import("zwsgi.zig").zWSGIRequest;
