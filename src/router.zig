/// Route Functions are allowed to return errors for select cases where
/// backtracking through the routing system might be useful. This in an
/// exercise left to the caller, as eventually a sever default server error page
/// will need to be returned.
route: RouteFn,

/// Similar to RouteFn and FallbackRouter: Verse allows endpoint pages to return
/// errors, but the final result must finish cleanly (ideally returning page
/// data to the client, but this isn't enforced). A default is provided, which
/// can handle most of the common cases,  but it's recommended that users
/// provide a custom builder function to handle errors, for complex cases, or
/// when errors are expected.
builder: Builder = defaultBuilder,

/// The router must eventually return an endpoint, if it returns an error
/// instead, the fallbackRouter will be called to route to internal pages.
fallback: FallbackRouter = fallbackRouter,

/// TODO document
const Router = @This();

/// The default page generator, this is the function that will be called once a
/// route is completed, and this function should write the page data back to the
/// client.
pub const BuildFn = *const fn (*Frame) Error!void;

pub const Builder = *const fn (*Frame, BuildFn) void;

pub const RouteFn = *const fn (*Frame) RoutingError!BuildFn;

pub const FallbackRouter = *const fn (*Frame, RouteFn) BuildFn;

pub const Errors = @import("errors.zig");
pub const Error = Errors.ServerError || Errors.ClientError || Errors.NetworkError;

/// The Verse router will scan through an array of Match structs looking for a
/// given name. Verse doesn't assert that the given name will match a director
/// or endpoint/page specifically. e.g. `/uri/page` and `/uri/page/` will both
/// match to the first identical name, regardless if the matched type is a build
/// function, or a route function.
///
/// A name containing any non alphanumeric char is undefined.
pub const Match = struct {
    /// The name for this resource. Names with length of 0 is valid for
    /// directories.
    name: []const u8,
    /// target build or route function
    target: Target,
    /// maps target to supported http methods.
    methods: Methods,

    /// Separate from the http interface as this is 'internal' to the routing
    /// subsystem, where a single endpoint may respond to multiple http methods.
    pub const Methods = packed struct(u9) {
        CONNECT: bool = false,
        DELETE: bool = false,
        GET: bool = false,
        HEAD: bool = false,
        OPTIONS: bool = false,
        POST: bool = false,
        PUT: bool = false,
        TRACE: bool = false,
        WEBSOCKET: bool = false,

        pub fn supports(m: Methods, req: Request.Methods) bool {
            return switch (req) {
                .CONNECT => m.CONNECT,
                .DELETE => m.DELETE,
                .GET => m.GET,
                .HEAD => m.HEAD,
                .OPTIONS => m.OPTIONS,
                .POST => m.POST,
                .PUT => m.PUT,
                .TRACE => m.TRACE,
                .WEBSOCKET => m.WEBSOCKET,
            };
        }

        pub const all: Methods = .{
            .CONNECT = true,
            .DELETE = true,
            .GET = true,
            .HEAD = true,
            .OPTIONS = true,
            .POST = true,
            .PUT = true,
            .TRACE = true,
            .WEBSOCKET = true,
        };

        pub const none: Methods = .{};
        pub const delete: Methods = .{ .DELETE = true };
        pub const get: Methods = .{ .GET = true };
        pub const post: Methods = .{ .POST = true };
        pub const websocket: Methods = .{ .WEBSOCKET = true };
    };
};

pub const Target = union(enum) {
    /// An endpoint function that's expected to return the requested page
    /// data.
    build: BuildFn,
    /// A router function that will either
    /// 1) consume the next URI token, and itself call the next routing
    /// function/handler, or
    /// 2) return the build function pointer that will be called directly to
    /// generate the page.
    route: RouteFn,
    /// A Match array for a sub directory, that can be handled by the same
    /// routing function. Provided for convenience.
    simple: []const Match,
};

/// Builds a default router given an array of matches.
pub fn Routes(comptime routes: []const Match) Router {
    const routefn = struct {
        const local: [routes.len]Match = routes;
        pub fn r(f: *Frame) RoutingError!BuildFn {
            return defaultRouter(f, routes);
        }
    };
    return .{
        .route = routefn.r,
    };
}

/// Default route building helper.
pub fn ROUTE(comptime name: []const u8, comptime match: anytype) Match {
    const target = buildTarget(match);
    return switch (target) {
        .build => |b| ALL(name, b),
        .route, .simple => .{ // TODO only populate if sub target handles method
            .name = name,
            .target = target,
            .methods = .all,
        },
    };
}

fn buildTarget(comptime match: anytype) Target {
    return switch (@typeInfo(@TypeOf(match))) {
        .pointer => |ptr| switch (@typeInfo(ptr.child)) {
            .@"fn" => |fnc| switch (fnc.return_type orelse null) {
                Error!void => .{ .build = match },
                RoutingError!BuildFn => .{ .route = match },
                else => @compileError("unknown function return type" ++ @typeName(ptr.child)),
            },
            else => .{ .simple = match },
        },
        .@"fn" => |fnc| switch (fnc.return_type orelse null) {
            Error!void => .{ .build = match },
            RoutingError!BuildFn => .{ .route = match },
            else => @compileError("unknown function return type"),
        },
        else => |el| @compileError("match type not supported, for provided type [" ++
            @typeName(@TypeOf(el)) ++
            "]"),
    };
}

/// Defaults to build only for GET, POST, and HEAD, and OPTIONS. Use ALL if your
/// endpoint actually supports every known method.
pub fn ANY(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .target = buildTarget(match),
        .methods = .{
            .GET = true,
            .POST = true,
            .HEAD = true,
            .OPTIONS = true,
        },
    };
}

pub fn ALL(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .target = buildTarget(match),
        .methods = .all,
    };
}

/// Match build helper for GET requests.
pub fn GET(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .target = buildTarget(match),
        .methods = .get,
    };
}

/// Match build helper for POST requests.
pub fn POST(comptime name: []const u8, comptime match: BuildFn) Match {
    var methods: Match.Methods = .none;
    methods.POST = true;
    return .{
        .name = name,
        .target = buildTarget(match),
        .methods = .post,
    };
}

/// Match build helper for DELETE requests.
pub fn DELETE(comptime name: []const u8, comptime match: BuildFn) Match {
    var methods: Match.Methods = .none;
    methods.GET = true;
    return .{
        .name = name,
        .target = buildTarget(match),
        .methods = .delete,
    };
}

pub fn WEBSOCKET(comptime name: []const u8, comptime match: BuildFn) Match {
    var methods: Match.Methods = .none;
    methods.GET = true;
    return .{
        .name = name,
        .target = buildTarget(match),
        .methods = .websocket,
    };
}

/// Static file helper that will auto route to the provided directory.
/// Verse normally expects to sit behind an rproxy, that can route requests for
/// static resources without calling Verse. But Verse does have some support for
/// returning simple static resources.
pub fn STATIC(comptime name: []const u8) Match {
    return .{
        .name = name,
        .target = buildTarget(StaticFile.fileOnDisk),
        .methods = .get,
    };
}

/// Convenience build function that will return a default page, normally during
/// an error.
pub fn defaultResponse(comptime code: std.http.Status) BuildFn {
    return switch (code) {
        .bad_request => badRequest,
        .unauthorized => unauthorized,
        .forbidden => forbidden,
        .not_found => notFound,
        .method_not_allowed => methodNotAllowed,
        .internal_server_error => internalServerError,
        else => default,
    };
}

fn badRequest(frame: *Frame) Error!void {
    return frame.sendHTML(.bad_request, @embedFile("builtin-html/400.html"));
}

fn unauthorized(frame: *Frame) Error!void {
    return frame.sendHTML(.unauthorized, @embedFile("builtin-html/401.html"));
}

fn forbidden(frame: *Frame) Error!void {
    return frame.sendHTML(.forbidden, @embedFile("builtin-html/403.html"));
}

fn notFound(frame: *Frame) Error!void {
    return frame.sendHTML(.not_found, @embedFile("builtin-html/404.html"));
}

fn methodNotAllowed(frame: *Frame) Error!void {
    return frame.sendHTML(.method_not_allowed, @embedFile("builtin-html/405.html"));
}

fn internalServerError(vrs: *Frame) Error!void {
    return vrs.sendHTML(.internal_server_error, @embedFile("builtin-html/500.html"));
}

fn default(frame: *Frame) Error!void {
    return frame.sendHTML(.ok, @embedFile("builtin-html/index.html"));
}

pub const RoutingError = error{
    Unrouteable,
    MethodNotAllowed,
    NotFound,
};

pub fn targetRouter(frame: *Frame, comptime dest: []const u8, comptime routes: []const Match) RoutingError!BuildFn {
    var r_err: RoutingError = error.Unrouteable;
    inline for (routes) |ep| {
        if (comptime eql(u8, dest, ep.name)) {
            if (ep.methods.supports(frame.request.method)) {
                switch (ep.target) {
                    .build => |call| return call,
                    .route => |route| return route(frame) catch |err| switch (err) {
                        error.Unrouteable => return notFound,
                        else => return err,
                    },
                    inline .simple => |simple| {
                        _ = frame.uri.next();
                        return defaultRouter(frame, simple);
                    },
                }
            } else r_err = error.MethodNotAllowed;
        }
    }
    return r_err;
}

test targetRouter {
    try std.testing.expectError(error.Unrouteable, targetRouter(undefined, "users", &.{}));
}

/// Default routing function. This is likely the routing function you want to
/// provide to verse with the Match array for your site. It can also be used
/// internally within custom routing functions, that provide additional page,
/// data or routing support/validation, before continuing to build the route.
pub fn defaultRouter(frame: *Frame, comptime routes: []const Match) RoutingError!BuildFn {
    const search = frame.uri.peek() orelse {
        if (routes.len > 0 and routes[0].name.len == 0) {
            return if (routes[0].methods.supports(frame.request.method)) switch (routes[0].target) {
                .build => |b| b,
                .route, .simple => error.Unrouteable,
            } else error.MethodNotAllowed;
        }

        log.warn("No endpoint found: URI is empty.", .{});
        return error.Unrouteable;
    };
    var r_err: RoutingError = error.Unrouteable;
    inline for (routes) |ep| {
        if (eql(u8, search, ep.name)) {
            if (ep.methods.supports(frame.request.method)) {
                switch (ep.target) {
                    .build => |call| {
                        return call;
                    },
                    .route => |route| {
                        return route(frame) catch |err| switch (err) {
                            error.Unrouteable => return notFound,
                            else => return err,
                        };
                    },
                    inline .simple => |simple| {
                        _ = frame.uri.next();
                        return defaultRouter(frame, simple);
                    },
                }
            } else r_err = error.MethodNotAllowed;
        }
    }
    return r_err;
}

/// This default builder is provided and handles an abbreviated set of errors.
/// This builder is unlikely to be able to handle all possible server error
/// states generated from all endpoints. More complicated uses may require a
/// custom builder.
///
/// Pages are permitted to return an error, but the page builder is required to
/// handle all errors, (and make a final decision where required). Ideally it
/// should also be able to return a response to the user, but that
/// implementation decision is left to the final builder.
pub fn defaultBuilder(vrs: *Frame, build: BuildFn) void {
    build(vrs) catch |err| {
        switch (err) {
            error.NoSpaceLeft,
            error.OutOfMemory,
            => @panic("Verse default builder: Page hit unhandled OOM error."),
            error.WriteFailed => log.err("generic write error", .{}),
            error.Unrouteable => {
                // Reaching an Unrouteable error here should be impossible as
                // the router has decided the target endpoint is correct.
                // However it's a vaild error in somecases. A non-default buildfn
                // could provide a replacement default. But this does not.
                log.err("Unrouteable", .{});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace);
                }
                @panic("Unroutable");
            },
            // This is an implementation error by the page. So we crash. If
            // you've reached this, something is wrong with your site.
            error.NotImplemented => @panic("Verse Default Router Error: NotImplemented (unreachable)"),
            error.Unknown => @panic("Verse Default Router Error: Unknown (unreachable)"),
            error.ServerFault => @panic("Verse Default Router Error: ServerFault (unreachable)"),
            error.InvalidURI => log.err("Unexpected error '{}'\n", .{err}),
            error.Abuse,
            error.Unauthenticated,
            error.Unauthorized,
            error.DataInvalid,
            error.DataMissing,
            => {
                // DataInvalid and DataMissing are unlikely to be abuse, but
                // dumping the information is likely to help with debugging the
                // error.
                log.err("Abuse {} because {}\n", .{ vrs.request, err });
                // TODO fix me
                //var itr = vrs.request.raw.http.iterateHeaders();
                //while (itr.next()) |vars| {
                //    log.err("Abusive var '{s}' => '''{s}'''\n", .{ vars.name, vars.value });
                //}
            },
        }
    };
}

const root = [_]Match{
    ROUTE("", default),
};

fn fallbackRouter(frame: *Frame, routefn: RouteFn) BuildFn {
    return routefn(frame) catch |err| switch (err) {
        error.MethodNotAllowed => methodNotAllowed,
        error.NotFound => notFound,
        error.Unrouteable => notFound,
    };
}

const root_with_static = root ++ [_]Match{
    ROUTE("static", StaticFile.fileOnDisk),
};

fn defaultRouterHtml(frame: *Frame, routefn: RouteFn) Error!void {
    if (frame.uri.peek()) |first| {
        if (first.len > 0)
            return routefn(frame) catch defaultRouter(frame, &root_with_static) catch notFound;
    }
    return internalServerError;
}

pub const TestingRouter: Router = Routes(&root);

test "smoke" {
    const a = std.testing.allocator;
    try testing.smokeTest(a, &root, .default, "");
    try testing.smokeTest(a, &root_with_static, .default, "");
}

const std = @import("std");
const log = std.log.scoped(.Verse);
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;

const Frame = @import("frame.zig");
const Request = @import("Request.zig");
const StaticFile = @import("static-file.zig");
const testing = @import("testing.zig");
