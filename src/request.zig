const std = @import("std");
const Allocator = std.mem.Allocator;
const indexOf = std.mem.indexOf;
const eql = std.mem.eql;

const zWSGIRequest = @import("zwsgi.zig").zWSGIRequest;

pub const Request = @This();

pub const RawReq = union(enum) {
    zwsgi: *zWSGIRequest,
    http: *std.http.Server.Request,
};

const Pair = struct {
    name: []const u8,
    val: []const u8,
};

pub const HeaderList = std.ArrayList(Pair);

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

/// TODO this is unstable and likely to be removed
raw: RawReq,
headers: HeaderList,
uri: []const u8,
method: Methods,

pub fn init(a: Allocator, raw_req: anytype) !Request {
    switch (@TypeOf(raw_req)) {
        *zWSGIRequest => {
            var req = Request{
                .raw = .{ .zwsgi = raw_req },
                .headers = HeaderList.init(a),
                .uri = undefined,
                .method = Methods.GET,
            };
            for (raw_req.vars) |v| {
                try req.addHeader(v.key, v.val);
                if (std.mem.eql(u8, v.key, "PATH_INFO")) {
                    req.uri = v.val;
                }
                if (std.mem.eql(u8, v.key, "REQUEST_METHOD")) {
                    req.method = Methods.fromStr(v.val) catch Methods.GET;
                }
            }
            return req;
        },
        *std.http.Server.Request => {
            var req = Request{
                .raw = .{ .http = raw_req },
                .headers = HeaderList.init(a),
                .uri = raw_req.head.target,
                .method = switch (raw_req.head.method) {
                    .GET => .GET,
                    .POST => .POST,
                    else => @panic("not implemented"),
                },
            };
            var itr = raw_req.iterateHeaders();
            while (itr.next()) |head| {
                try req.addHeader(head.name, head.value);
            }
            return req;
        },
        else => @compileError("rawish of " ++ @typeName(raw_req) ++ " isn't a support request type"),
    }
    @compileError("unreachable");
}

pub fn addHeader(self: *Request, name: []const u8, val: []const u8) !void {
    try self.headers.append(.{ .name = name, .val = val });
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
