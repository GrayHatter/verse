pub const std = @import("std");
const Allocator = std.mem.Allocator;
const splitScalar = std.mem.splitScalar;
const log = std.log.scoped(.Verse);

pub const Server = @import("server.zig");

pub const Request = @import("request.zig");
pub const Response = @import("response.zig");
pub const RequestData = @import("request_data.zig");
pub const Template = @import("template.zig");
pub const Router = @import("router.zig");
pub const UriIter = Router.UriIter;

pub const Auth = @import("auth.zig");

const Error = @import("errors.zig").Error;

pub const Verse = @This();

alloc: Allocator,
request: *const Request,
response: Response,
reqdata: RequestData,
uri: UriIter,

// TODO fix this unstable API
auth: Auth,
route_ctx: ?*const anyopaque = null,

const VarPair = struct {
    []const u8,
    []const u8,
};

pub fn init(a: Allocator, req: *const Request, res: Response, reqdata: RequestData) !Verse {
    std.debug.assert(req.uri[0] == '/');
    return .{
        .alloc = a,
        .request = req,
        .response = res,
        .reqdata = reqdata,
        .uri = splitScalar(u8, req.uri[1..], '/'),
        .auth = Auth{
            .provider = Auth.InvalidProvider.empty(),
        },
    };
}

pub fn sendPage(vrs: *Verse, page: anytype) Error!void {
    try vrs.quickStart();
    const loggedin = if (vrs.auth.valid()) "<a href=\"#\">Logged In</a>" else "Public";
    const T = @TypeOf(page.*);
    if (@hasField(T, "data") and @hasField(@TypeOf(page.data), "body_header")) {
        page.data.body_header.?.nav.?.nav_auth = loggedin;
    }

    const writer = vrs.response.writer();
    page.format("{}", .{}, writer) catch |err| switch (err) {
        else => log.err("Page Build Error {}", .{err}),
    };
}

///
pub fn sendRawSlice(vrs: *Verse, slice: []const u8) Error!void {
    vrs.response.send(slice) catch return error.Unknown;
}

pub fn sendError(vrs: *Verse, comptime code: std.http.Status) Error!void {
    return Router.defaultResponse(code)(vrs);
}

pub fn sendJSON(vrs: *Verse, json: anytype) Error!void {
    try vrs.quickStart();
    const data = std.json.stringifyAlloc(vrs.alloc, json, .{
        .emit_null_optional_fields = false,
    }) catch |err| {
        log.err("Error trying to print json {}", .{err});
        return error.Unknown;
    };
    vrs.response.writeAll(data) catch unreachable;
    vrs.response.finish() catch unreachable;
}

/// This function may be removed in the future
pub fn quickStart(vrs: *Verse) Error!void {
    vrs.response.start() catch |err| switch (err) {
        error.BrokenPipe => return error.NetworkCrash,
        else => unreachable,
    };
}

test "Verse" {
    std.testing.refAllDecls(@This());
}
