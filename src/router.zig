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
    /// Map http method to target endpoint.
    methods: Methods,

    /// Separate from the http interface as this is 'internal' to the routing
    /// subsystem, where a single endpoint may respond to multiple http methods.
    pub const Methods = struct {
        CONNECT: ?Target = null,
        DELETE: ?Target = null,
        GET: ?Target = null,
        HEAD: ?Target = null,
        OPTIONS: ?Target = null,
        POST: ?Target = null,
        PUT: ?Target = null,
        TRACE: ?Target = null,
        WEBSOCKET: ?Target = null,
    };

    pub fn target(comptime self: Match, comptime req: Request.Methods) ?Target {
        return switch (req) {
            .CONNECT => self.methods.CONNECT,
            .DELETE => self.methods.DELETE,
            .GET => self.methods.GET,
            .HEAD => self.methods.HEAD,
            .OPTIONS => self.methods.OPTIONS,
            .POST => self.methods.POST,
            .PUT => self.methods.PUT,
            .TRACE => self.methods.TRACE,
            .WEBSOCKET => self.methods.WEBSOCKET,
        };
    }
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
            .methods = .{
                .CONNECT = target,
                .DELETE = target,
                .GET = target,
                .HEAD = target,
                .OPTIONS = target,
                .POST = target,
                .PUT = target,
                .TRACE = target,
                .WEBSOCKET = target,
            },
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
    const target = buildTarget(match);
    return .{
        .name = name,
        .methods = .{
            .GET = target,
            .POST = target,
            .HEAD = target,
            .OPTIONS = target,
        },
    };
}

pub fn ALL(comptime name: []const u8, comptime match: BuildFn) Match {
    const target = buildTarget(match);
    return .{
        .name = name,
        .methods = .{
            .CONNECT = target,
            .DELETE = target,
            .GET = target,
            .HEAD = target,
            .OPTIONS = target,
            .POST = target,
            .PUT = target,
            .TRACE = target,
        },
    };
}

/// Match build helper for GET requests.
pub fn GET(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .methods = .{
            .GET = buildTarget(match),
        },
    };
}

/// Match build helper for POST requests.
pub fn POST(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .methods = .{
            .POST = buildTarget(match),
        },
    };
}

/// Match build helper for DELETE requests.
pub fn DELETE(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .methods = .{
            .DELETE = buildTarget(match),
        },
    };
}

pub fn WEBSOCKET(comptime name: []const u8, comptime match: BuildFn) Match {
    return .{
        .name = name,
        .methods = .{
            // TODO .GET?
            .WEBSOCKET = buildTarget(match),
        },
    };
}

/// Static file helper that will auto route to the provided directory.
/// Verse normally expects to sit behind an rproxy, that can route requests for
/// static resources without calling Verse. But Verse does have some support for
/// returning simple static resources.
pub fn STATIC(comptime name: []const u8) Match {
    return .{
        .name = name,
        .methods = .{
            .GET = buildTarget(StaticFile.fileOnDisk),
        },
    };
}

/// Convenience build function that will return a default page, normally during
/// an error.
pub fn defaultResponse(comptime code: std.http.Status) BuildFn {
    return switch (code) {
        .not_found => notFound,
        .internal_server_error => internalServerError,
        else => default,
    };
}

fn notFound(frame: *Frame) Error!void {
    const E404 = @embedFile("fallback_html/404.html");
    return frame.sendHTML(.not_found, E404);
}

fn internalServerError(vrs: *Frame) Error!void {
    const E500 = @embedFile("fallback_html/500.html");
    return vrs.sendHTML(.internal_server_error, E500);
}

fn methodNotAllowed(frame: *Frame) Error!void {
    const E405 = @embedFile("fallback_html/405.html");
    return frame.sendHTML(.method_not_allowed, E405);
}

fn default(frame: *Frame) Error!void {
    const index = @embedFile("fallback_html/index.html");
    return frame.sendHTML(.ok, index);
}

pub const RoutingError = error{
    Unrouteable,
    MethodNotAllowed,
    NotFound,
};

/// Default routing function. This is likely the routing function you want to
/// provide to verse with the Match array for your site. It can also be used
/// internally within custom routing functions, that provide additional page,
/// data or routing support/validation, before continuing to build the route.
pub fn defaultRouter(frame: *Frame, comptime routes: []const Match) RoutingError!BuildFn {
    const search = frame.uri.peek() orelse {
        if (routes.len > 0 and routes[0].name.len == 0) {
            switch (frame.request.method) {
                inline else => |m| if (routes[0].target(m)) |t| return switch (t) {
                    .build => |b| return b,
                    .route, .simple => return error.Unrouteable,
                },
            }
        }

        log.warn("No endpoint found: URI is empty.", .{});
        return error.Unrouteable;
    };
    inline for (routes) |ep| {
        if (eql(u8, search, ep.name)) {
            switch (frame.request.method) {
                inline else => |m| {
                    if (comptime ep.target(m)) |target| {
                        switch (target) {
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
                    } else return error.MethodNotAllowed;
                },
            }
        }
    }
    return error.Unrouteable;
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
            error.BrokenPipe => log.warn("client disconnect", .{}),
            error.IOWriteFailure => log.err("generic write error", .{}),
            error.Unrouteable => {
                // Reaching an Unrouteable error here should be impossible as
                // the router has decided the target endpoint is correct.
                // However it's a vaild error in somecases. A non-default buildfn
                // could provide a replacement default. But this does not.
                log.err("Unrouteable", .{});
                if (@errorReturnTrace()) |trace| {
                    std.debug.dumpStackTrace(trace.*);
                }
                @panic("Unroutable");
            },
            // This is an implementation error by the page. So we crash. If
            // you've reached this, something is wrong with your site.
            error.NotImplemented => @panic("Not Implemented Error"),
            error.Unknown => @panic("Unreachable Error"),
            error.InvalidURI => log.err("Unexpected error '{}'\n", .{err}),
            error.Abusive,
            error.Unauthenticated,
            error.BadData,
            error.DataMissing,
            => {
                // BadData and DataMissing aren't likely to be abusive, but
                // dumping the information is likely to help with debugging the
                // error.
                log.err("Abusive {} because {}\n", .{ vrs.request, err });
                // TODO fix me
                //var itr = vrs.request.raw.http.iterateHeaders();
                //while (itr.next()) |vars| {
                //    log.err("Abusive var '{s}' => '''{s}'''\n", .{ vars.name, vars.value });
                //}
            },
        }
    };
}

/// Note UriIterator is a simple split iterator an not a token iterator. If
/// you're using a custom routing implementation; this may not be the behavior
/// you expect. e.g. for a uri = `////word/end` the first 3 calls to next() will
/// return "". Typically this isn't the expected behavior for a directory
/// structure and `////word/end` should be equivalent to `/word/end`. Verse
/// doesn't enforce this behavior to enable cases where the expected value of
/// `/missing/expected/prefix/word/end` has 3 omitted/empty values.
pub const UriIterator = std.mem.SplitIterator(u8, .scalar);

/// splitUri will take any uri, do the most basic of input validation and then
/// return UriIterator.
///
/// Note: UriIterator does not behave like a normal token iterator.
pub fn splitUri(uri: []const u8) !UriIterator {
    if (uri.len == 0 or uri[0] != '/') return error.InvalidUri;
    return .{
        .index = 0,
        .buffer = uri[1..],
        .delimiter = '/',
    };
}

const root = [_]Match{
    ROUTE("", default),
};

fn fallbackRouter(frame: *Frame, routefn: RouteFn) BuildFn {
    return routefn(frame) catch |err| switch (err) {
        error.MethodNotAllowed => methodNotAllowed,
        error.NotFound => notFound,
        error.Unrouteable => internalServerError,
    };
}

const root_with_static = root ++ [_]Match{
    ROUTE("static", StaticFile.file),
};

fn defaultRouterHtml(frame: *Frame, routefn: RouteFn) Error!void {
    if (frame.uri.peek()) |first| {
        if (first.len > 0)
            return routefn(frame) catch defaultRouter(frame, &root_with_static) catch notFound;
    }
    return internalServerError;
}

pub const TestingRouter: Router = Routes(&root);

test "uri" {
    const uri_file = "/root/first/second/third";
    const uri_dir = "/root/first/second/";
    const uri_broken = "/root/first/////sixth/";
    const uri_dots = "/root/first/../../../fifth";

    var itr = try splitUri(uri_file);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("second", itr.next().?);
    try std.testing.expectEqualStrings("third", itr.next().?);
    try std.testing.expectEqual(null, itr.next());

    itr = try splitUri(uri_dir);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("second", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqual(null, itr.next());

    itr = try splitUri(uri_broken);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqualStrings("sixth", itr.next().?);
    try std.testing.expectEqualStrings("", itr.next().?);
    try std.testing.expectEqual(null, itr.next());

    itr = try splitUri(uri_dots);
    try std.testing.expectEqualStrings("root", itr.next().?);
    try std.testing.expectEqualStrings("first", itr.next().?);
    try std.testing.expectEqualStrings("..", itr.next().?);
    try std.testing.expectEqualStrings("..", itr.next().?);
    try std.testing.expectEqualStrings("..", itr.next().?);
    try std.testing.expectEqualStrings("fifth", itr.next().?);
    try std.testing.expectEqual(null, itr.next());
}

const std = @import("std");
const log = std.log.scoped(.Verse);
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;

const Frame = @import("frame.zig");
const Request = @import("request.zig");
const StaticFile = @import("static-file.zig");
pub const Errors = @import("errors.zig");
pub const Error = Errors.ServerError || Errors.ClientError || Errors.NetworkError;
