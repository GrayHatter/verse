const Endpoint = @This();

pub const Target = struct {
    name: []const u8,
};

pub const Options = Server.Options;

/// `endpoints` can be a tuple of any number of supported containers. The only
/// supported container is a struct that includes the minimum set of definitions
/// for verse to construct a valid server route.
/// TODO enumerate minimal example
pub fn Endpoints(endpoints: anytype) type {
    if (@typeInfo(@TypeOf(endpoints)).@"struct".is_tuple == false) return error.InvalidEndpointTypes;
    inline for (endpoints) |ep| {
        validateEndpoint(ep);
    }

    return struct {
        pub const Self = @This();
        pub const Endpoints = endpoints;

        pub const routes = collectRoutes(endpoints);
        pub const router = brk: {
            var rtr = Router.Routes(&routes);
            // TODO expand route constructor to find the correct builder for
            // every route
            // TODO weakly tested
            if (@hasDecl(endpoints[0], "verse_builder")) {
                rtr.builder = endpoints[0].verse_builder;
            }
            break :brk rtr;
        };

        pub fn serve(a: Allocator, options: Options) !void {
            var server = try Server.init(a, router, options);
            try server.serve();
        }

        pub fn smokeTest(a: Allocator, comptime opts: testing.SmokeTestOptions) !void {
            try testing.smokeTest(a, &Self.routes, opts, "");
        }
    };
}

pub fn validateEndpoint(EP: anytype) void {
    if (!@hasDecl(EP, "verse_name")) {
        @compileError("Verse: provided endpoint is missing name decl.\n" ++
            "Expected `pub const verse_name = .endpoint_name;` from: " ++ @typeName(EP));
    }

    if (@hasDecl(EP, "verse_endpoints")) {
        if (!@hasDecl(EP.verse_endpoints, "Endpoints")) {
            @compileError("the `verse_endpoints` decl is reserved for verse, and must " ++
                "be a constructed \"Endpoint\" type");
        }
    }

    if (@hasDecl(EP, "verse_router")) {
        if (@TypeOf(EP.verse_router) != Router.RouteFn) {
            // TODO support `fn ...` in addition to `*const fn ...`
            @compileError("The `verse_router` decl must be a Router.RouteFn. Instead it was " ++
                @typeName(@TypeOf(EP.verse_router)));
        }
    }

    // TODO figure out why this causes a dependency loop and reenable
    if (@hasDecl(EP, "verse_routes")) {
        //if (@TypeOf(EP.verse_routes) != []Router.Match) {
        //    @compileError("the `verse_routes` decl is reserved for a list of pre-constructed " ++
        //        "`Match` targets. expected []Router.Match but found " ++ @typeName(@TypeOf(EP.verse_routes)) ++ ".");
        //}
        inline for (EP.verse_routes, 0..) |route, i| {
            if (@TypeOf(route) != Router.Match) {
                @compileError("the `verse_routes` decl is reserved for a list of pre-constructed " ++
                    "`Match` targets. " ++ @typeName(route) ++ " at position " ++ i ++ " is invalid.");
            }
        }
    }

    if (@hasDecl(EP, "verse_builder")) {
        if (@TypeOf(EP.verse_builder) != Router.Builder) {
            // TODO support `fn ...` in addition to `*const fn ...`
            @compileError("The `verse_builder` decl must be a Router.BuilderFn. Instead it was " ++
                @typeName(@TypeOf(EP.verse_builder)));
        }
    }

    if (@hasDecl(EP, "verse_alias")) {
        // TODO write validation code for alias
    }
}

fn routeCount(endpoints: anytype) usize {
    var count: usize = 0;
    if (endpoints.len == 0) @compileError("Zero is not a countable number");
    for (endpoints, 0..) |ep, i| {
        if (@hasDecl(ep, "verse_router")) {
            count += 1;
        } else {
            if (@hasDecl(ep, "index") and @typeInfo(@TypeOf(ep.index)) == .@"fn") {
                count += 1;
            }

            if (@hasDecl(ep, "verse_routes")) for (ep.verse_routes) |route| {
                if (route.name.len == 0) {
                    @compileError("Empty route name for: " ++ @typeName(ep) ++ ". To support a directory URI, define an index() instead");
                }
                count += 1;
            };

            if (@hasDecl(ep, "verse_endpoints")) {
                count += ep.verse_endpoints.Endpoints.len;
            }
        }
        if (i == 0 and ep.verse_name == .root) {
            // .root is a special case endpoint that gets automagically
            // flattened out
            var alias_count: usize = 0;
            if (endpoints.len > 1) {
                for (endpoints) |ep_alias| if (@hasDecl(ep_alias, "verse_alias")) {
                    alias_count += ep_alias.verse_alias.len;
                };
            }
            return count + endpoints.len - 1 + alias_count;
        }
    }
    return count;
}

test routeCount {
    comptime {
        const Frame = @import("frame.zig");
        try std.testing.expectEqual(0, routeCount(.{
            struct {
                const verse_name = .testing;
            },
        }));
        try std.testing.expectEqual(1, routeCount(.{
            struct {
                const verse_name = .testing;
                pub fn index() void {}
            },
        }));
        try std.testing.expectEqual(2, routeCount(.{
            struct {
                const verse_name = .testing;
                const verse_endpoints = Endpoints(.{
                    struct {
                        pub const verse_name = .sub_testing;
                        pub fn index() void {}
                    },
                });
                pub fn index() void {}
            },
        }));
        try std.testing.expectEqual(3, routeCount(.{
            struct {
                const verse_name = .testing;
                const verse_routes = .{
                    Router.ROUTE("first", empty),
                    Router.ROUTE("second", empty),
                    Router.ROUTE("third", empty),
                };
                pub fn empty(_: *Frame) Router.Error!void {}
            },
        }));
        try std.testing.expectEqual(1, routeCount(.{
            struct {
                const verse_name = .testing;
                const verse_router = &router;
                pub fn router(_: *Frame) Router.RoutingError!Router.BuildFn {}
            },
        }));
        try std.testing.expectEqual(1, routeCount(.{
            struct {
                const verse_name = .testing;
                const verse_router = &router;
                pub fn router(_: *Frame) Router.RoutingError!Router.BuildFn {}
                pub fn index() void {}
            },
        }));
        // TODO test verse_router doesn't include verse_endpoints
        try std.testing.expectEqual(1, routeCount(.{
            // TODO expand this test in include a root struct
            struct {
                const verse_name = .testing;
                const verse_alias = .{
                    // everyone has testing infra, we're not lucky enough to
                    // have dedicated infra reserved for prod
                    .prod,
                };
                pub fn index() void {}
            },
        }));
    }
}

fn collectRoutes(EPS: anytype) [routeCount(EPS)]Router.Match {
    var match: [routeCount(EPS)]Router.Match = undefined;
    var idx: usize = 0;
    for (EPS) |EP| {
        // Only flatten when the endpoint name is root
        if (EP.verse_name == .root) {
            for (buildRoutes(EP)) |r| {
                match[idx] = r;
                idx += 1;
            }
        } else if (@hasDecl(EP, "verse_router")) {
            match[idx] = Router.ROUTE(@tagName(EP.verse_name), EP.verse_router);
            idx += 1;
            if (@hasDecl(EP, "verse_alias")) for (EP.verse_alias) |alias| {
                match[idx] = Router.ROUTE(@tagName(alias), EP.verse_router);
                idx += 1;
            };
        } else {
            const routes = buildRoutes(EP);
            match[idx] = Router.ROUTE(@tagName(EP.verse_name), &routes);
            idx += 1;
            if (@hasDecl(EP, "verse_alias")) for (EP.verse_alias) |alias| {
                match[idx] = Router.ROUTE(@tagName(alias), &routes);
                idx += 1;
            };
        }
    }
    return match;
}

fn buildRoutes(EP: type) [routeCount(.{EP})]Router.Match {
    var match: [routeCount(.{EP})]Router.Match = undefined;
    var idx: usize = 0;
    if (@hasDecl(EP, "verse_router")) {
        match[idx] = Router.ROUTE(@tagName(EP.verse_name), EP.verse_router);
        idx += 1;
    } else {
        if (@hasDecl(EP, "index")) {
            match[idx] = Router.ALL("", EP.index);
            idx += 1;
        }

        if (@hasDecl(EP, "verse_routes")) for (EP.verse_routes) |route| {
            match[idx] = route;
            idx += 1;
        };

        if (@hasDecl(EP, "verse_endpoints")) for (EP.verse_endpoints.Endpoints) |endpoint| {
            match[idx] = Router.ROUTE(@tagName(endpoint.verse_name), &EP.verse_endpoints.routes);
            idx += 1;
        };
    }

    if (idx == 0) @compileError("Unable to build routes for " ++ @typeName(EP) ++ " No valid routes found");
    return match;
}

test Endpoints {
    const Example = struct {
        const Frame = @import("frame.zig");
        pub fn nopEndpoint(_: *Frame) Router.Error!void {}
    };

    _ = Endpoints(.{
        struct {
            pub const verse_name = .root;
            pub const verse_routes = [_]Router.Match{
                Router.GET("nop", Example.nopEndpoint),
                Router.ROUTE("routes", Example.nopEndpoint),
                Router.STATIC("static"),
            };
            pub const verse_builder = &Router.defaultBuilder;
            pub const index = Example.nopEndpoint;
        },
    });
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const Auth = @import("auth.zig");
const Server = @import("server.zig");
const Router = @import("router.zig");
const testing = @import("testing.zig");
