const Endpoint = @This();

pub const Target = struct {
    name: []const u8,
};

pub const Options = struct {
    mode: Server.RunMode = .{ .http = .{} },
    auth: Auth.Provider = Auth.InvalidAuth.provider(),
};

/// `endpoints` can be a tuple of any number of supported containers. The only
/// supported container is a struct that includes the minimum set of definitions
/// for verse to construct a valid server route.
/// TODO enumerate minimal example
pub fn Endpoints(endpoints: anytype) type {
    if (@typeInfo(@TypeOf(endpoints)).Struct.is_tuple == false) return error.InvalidEndpointTypes;
    inline for (endpoints) |ep| {
        validateEndpoint(ep);
    }

    return struct {
        alloc: Allocator,

        pub const Self = @This();
        pub const Endpoints = endpoints;

        pub const routes = buildRoutes(endpoints[0]);

        pub fn init(a: Allocator) Self {
            return .{
                .alloc = a,
            };
        }

        pub fn serve(self: *Self, options: Options) !void {
            var server = try Server.init(self.alloc, .{
                .mode = options.mode,
                .router = .{ .routefn = route },
            });
            try server.serve();
        }

        pub fn route(frame: *Frame) Router.RoutingError!Router.BuildFn {
            return Router.router(frame, &routes);
        }
    };
}

fn validateEndpoint(EP: anytype) void {
    if (!@hasDecl(EP, "verse_name")) @compileError("Verse: provided endpoint is missing name decl.\n" ++
        "Expected `pub const verse_name = .endpoint_name;` from: " ++ @typeName(EP));
}

fn routeCount(EP: type) usize {
    var count: usize = 0;
    for (@typeInfo(EP).Struct.decls) |decl| {
        if (eql(u8, "index", decl.name)) count += 1;
    }

    if (@hasDecl(EP, "verse_routes")) for (EP.verse_routes) |route| {
        if (route.name.len == 0) {
            @compileError("route name omitted for: " ++ @typeName(EP) ++ ". To support a directory URI, define an index() instead");
        }
        count += 1;
    };

    if (@hasDecl(EP, "verse_endpoints")) {
        count += EP.verse_endpoints.Endpoints.len;
    }

    return count;
}

fn buildRoutes(EP: anytype) [routeCount(EP)]Router.Match {
    var match: [routeCount(EP)]Router.Match = undefined;
    var idx: usize = 0;
    for (@typeInfo(EP).Struct.decls) |decl| {
        if (eql(u8, "index", decl.name)) {
            match[idx] = Router.ANY("", EP.index);
            idx += 1;
        }
    }

    if (@hasDecl(EP, "verse_routes")) for (EP.verse_routes) |route| {
        match[idx] = route;
        idx += 1;
    };

    if (@hasDecl(EP, "verse_endpoints")) for (EP.verse_endpoints.Endpoints) |endpoint| {
        match[idx] = Router.ROUTE(@tagName(endpoint.verse_name), &EP.verse_endpoints.routes);
        idx += 1;
    };

    return match;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const Frame = @import("frame.zig");
const Auth = @import("auth.zig");
const Server = @import("server.zig");
const Router = @import("router.zig");
