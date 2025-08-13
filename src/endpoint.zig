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
            @compileError(
                "The `verse_router` decl must be a Router.RouteFn. Instead it was " ++
                    @typeName(@TypeOf(EP.verse_router)) ++
                    " (you may need to add an explicit type to the decl.)",
            );
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

            if (route.name.len == 0) {
                @compileError("Empty route name for: " ++ @typeName(EP) ++ ". To support a directory URI, define an index() instead");
            }
        }
    }

    if (@hasDecl(EP, "verse_router") and @hasDecl(EP, "verse_endpoints")) {
        @compileError(
            \\Unable to compile endpoints because both `verse_router` and `verse_endpoints` were provided, by
        ++ @typeName(EP) ++
            \\ one of these will become unreachable.
            \\ `Endpoints.routes` can be appended to an existing route array.
        );
    }

    if (@hasDecl(EP, "verse_router") and @hasDecl(EP, "verse_routes")) {
        @compileError(
            \\Unable to compile endpoints because both `verse_router` and `verse_routes` were provided, by
        ++ @typeName(EP) ++
            \\ one of these will become unreachable.
        );
    }

    if (@hasDecl(EP, "verse_builder")) {
        if (@TypeOf(EP.verse_builder) != Router.Builder) {
            // TODO support `fn ...` in addition to `*const fn ...`
            @compileError("The `verse_builder` decl must be a Router.BuilderFn. Instead it was " ++
                @typeName(@TypeOf(EP.verse_builder)));
        }
    }

    if (@hasDecl(EP, "verse_aliases")) {
        if (@typeInfo(@TypeOf(EP.verse_aliases)) != .@"struct") {
            @compileError("ha");
        }
        if (!@typeInfo(@TypeOf(EP.verse_aliases)).@"struct".is_tuple) {
            @compileError("Expected verse_aliases to be a tuple of .enum_literals");
        }
        for (EP.verse_aliases, 0..) |alias, i| {
            if (@TypeOf(alias) != @TypeOf(.enum_literal)) {
                @compileError("Expected verse_aliases in position " ++ i ++ " to be an .enum_literal.\n" ++
                    "Instead it was: " ++ @typeName(alias));
            }
        }
    }

    if (@hasDecl(EP, "verse_endpoint_disabled")) {
        if (@TypeOf(EP.verse_endpoint_disabled) != bool) {
            @compileError("The type of `verse_endpoint_disabled` decl must be bool. Instead it was " ++
                @typeName(@TypeOf(EP.verse_builder)));
        }
    }
}

fn routeCount(endpoints: anytype) usize {
    if (endpoints.len == 0) @compileError("Zero is not a countable number");

    var count: usize = 0;
    var flatten_root: bool = true;
    for (endpoints, 0..) |ep, i| {
        if (@hasDecl(ep, "verse_endpoint_disabled")) {
            if (ep.verse_endpoint_disabled) continue;
        }

        const root_endpoint: bool = ep.verse_name == .root and i == 0 or endpoints.len == 1;
        if (@hasDecl(ep, "verse_flatten_routes") and ep.verse_flatten_routes == false) {
            flatten_root = false;
        }

        if (@hasDecl(ep, "verse_router")) {
            count += 1;
            if (@hasDecl(ep, "verse_aliases")) count += ep.verse_aliases.len;
        } else if (root_endpoint and flatten_root) {
            if (@hasDecl(ep, "index") and @typeInfo(@TypeOf(ep.index)) == .@"fn") count += 1;
            if (@hasDecl(ep, "verse_aliases")) count += ep.verse_aliases.len;
            if (@hasDecl(ep, "verse_routes")) count += ep.verse_routes.len;
            if (@hasDecl(ep, "verse_endpoints")) count += @min(ep.verse_endpoints.Endpoints.len, 1);
        } else {
            if (@hasDecl(ep, "verse_aliases") and endpoints.len > 1) count += ep.verse_aliases.len;

            if (@hasDecl(ep, "index") and @typeInfo(@TypeOf(ep.index)) == .@"fn") {
                count += 1;
            } else if (@hasDecl(ep, "verse_routes")) {
                count += @min(ep.verse_routes.len, 1);
            } else if (@hasDecl(ep, "verse_endpoints")) {
                count += @min(ep.verse_endpoints.Endpoints.len, 1);
            }
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
        try std.testing.expectEqual(1, routeCount(.{
            struct {
                const verse_name = .testing;
                const verse_endpoints = Endpoints(.{
                    struct {
                        pub const verse_name = .sub_testing;
                        pub fn index() void {}
                    },
                });
            },
        }));
        try std.testing.expectEqual(5, routeCount(.{
            struct {
                const verse_name = .root;
                pub fn index(_: *Frame) Router.Error!void {}
                const verse_routes = .{
                    Router.ROUTE("first", index),
                    Router.ROUTE("second", index),
                    Router.ROUTE("third", index),
                };
            },
            struct {
                pub const verse_name = .sub_root;
                pub fn empty(_: *Frame) Router.Error!void {}
                const verse_routes = .{
                    Router.ROUTE("first", empty),
                    Router.ROUTE("second", empty),
                };
                const verse_endpoints = Endpoints(.{
                    struct {
                        pub const verse_name = .sub_sub_root;
                        pub fn index(_: *Frame) Router.Error!void {}
                    },
                });
            },
        }));
        try std.testing.expectEqual(3, routeCount(.{
            struct {
                const verse_name = .root;
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
                const verse_routes = .{
                    Router.ROUTE("first", empty),
                    Router.ROUTE("second", empty),
                    Router.ROUTE("third", empty),
                };
                pub fn empty(_: *Frame) Router.Error!void {}
            },
            struct {
                const verse_name = .dummy;
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
        try std.testing.expectEqual(2, routeCount(.{
            // TODO expand this test in include a root struct
            struct {
                const verse_name = .testing;
                const verse_aliases = .{
                    // everyone has testing infra, we're not lucky enough to
                    // have dedicated infra reserved for prod
                    .prod,
                };
                pub fn index() void {}
            },
        }));
        // disabled
        try std.testing.expectEqual(3, routeCount(.{
            // TODO expand this test in include a root struct
            struct {
                const verse_name = .first;
                pub fn index() void {}
            },
            struct {
                const verse_name = .second;
                const verse_aliases = .{.prod};
                pub fn index() void {}
            },
        }));
        try std.testing.expectEqual(1, routeCount(.{
            // TODO expand this test in include a root struct
            struct {
                const verse_name = .first;
                pub fn index() void {}
            },
            struct {
                const verse_name = .second;
                const verse_aliases = .{.prod};
                const verse_endpoint_disabled: bool = true;
                pub fn index() void {}
            },
        }));
        try std.testing.expectEqual(3, routeCount(.{
            struct {
                const verse_name = .first;
                pub fn index() void {}
            },
            struct {
                const verse_name = .second;
                const verse_aliases = .{.prod};
                const verse_endpoint_disabled: bool = false;
                pub fn index() void {}
            },
        }));
        try std.testing.expectEqual(10, routeCount(.{
            struct {
                const verse_name = .first;
                pub fn index() void {}
            },
            struct {
                const verse_name = .second;
                const verse_aliases = .{
                    .prod,     .devel,   .devel2, .not_devel,
                    .not_prod, .testing, .admin,  .secret,
                };
                const verse_endpoint_disabled: bool = false;
                pub fn index() void {}
            },
        }));
    }
}

fn collectRoutes(EPS: anytype) [routeCount(EPS)]Router.Match {
    var match: [routeCount(EPS)]Router.Match = undefined;
    var idx: usize = 0;
    var flatten_root: bool = true;
    for (EPS, 0..) |EP, i| {
        if (@hasDecl(EP, "verse_endpoint_disabled")) {
            if (EP.verse_endpoint_disabled) continue;
        }

        const root_endpoint: bool = EP.verse_name == .root and i == 0 or EPS.len == 1;
        if (@hasDecl(EP, "verse_flatten_routes") and EP.verse_flatten_routes == false) {
            flatten_root = false;
        }

        if (root_endpoint) {
            for (buildRoutes(EP)) |r| {
                match[idx] = r;
                idx += 1;
            }
        } else if (@hasDecl(EP, "verse_router")) {
            match[idx] = Router.ROUTE(@tagName(EP.verse_name), EP.verse_router);
            idx += 1;
            if (@hasDecl(EP, "verse_aliases")) for (EP.verse_aliases) |alias| {
                match[idx] = Router.ROUTE(@tagName(alias), EP.verse_router);
                idx += 1;
            };
        } else if (!@hasDecl(EP, "verse_flatten_routes") or EP.verse_flatten_routes) {
            const routes = buildRoutes(EP);
            match[idx] = Router.ROUTE(@tagName(EP.verse_name), &routes);
            idx += 1;

            if (@hasDecl(EP, "verse_aliases")) for (EP.verse_aliases) |alias| {
                match[idx] = Router.ROUTE(@tagName(alias), &routes);
                idx += 1;
            };
        } else {
            //const routes = buildRoutes(EP);
            if (@hasDecl(EP, "verse_routes")) {
                match[idx] = Router.ROUTE(@tagName(EP.verse_name), &EP.verse_routes);
                idx += 1;
                if (@hasDecl(EP, "verse_aliases")) for (EP.verse_aliases) |alias| {
                    match[idx] = Router.ROUTE(@tagName(alias), &EP.verse_routes);
                    idx += 1;
                };
            }
            if (@hasDecl(EP, "verse_endpoints")) {
                match[idx] = Router.ROUTE(@tagName(EP.verse_name), &EP.verse_endpoints);
                idx += 1;
            }
        }
    }
    if (idx != match.len) {
        @compileError("Unable to collect all expected endpoints");
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
            // This hack in wrong, and yes, I feel bad :<
            if (@hasDecl(EP, "verse_aliases")) for (EP.verse_aliases) |_| {
                match[idx] = Router.ALL("", EP.index);
                idx += 1;
            };
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
    if (idx != match.len) {
        @compileError("Unable to build all expected routes");
    }
    return match;
}

test Endpoints {
    const Example = struct {
        const Frame = @import("frame.zig");
        pub fn nopEndpoint(_: *Frame) Router.Error!void {}
    };

    const first = Endpoints(.{
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
    try std.testing.expectEqual(@as(usize, 4), first.routes.len);

    const second = Endpoints(.{
        struct {
            pub const verse_name = .root;
            //pub const verse_flatten_routes = false;
            pub const index = Example.nopEndpoint;
            pub const verse_routes = [_]Router.Match{
                Router.GET("nop", Example.nopEndpoint),
                Router.ROUTE("routes", Example.nopEndpoint),
                Router.STATIC("static"),
            };
            pub const verse_builder = &Router.defaultBuilder;
        },
        struct {
            pub const verse_name = .flattened;
            pub const verse_routes = [_]Router.Match{
                Router.ANY("flat0", Example.nopEndpoint),
                Router.ANY("flat1", Example.nopEndpoint),
            };
            pub const verse_endpoints = Endpoints(.{
                struct {
                    pub const verse_name = .sub_tree;
                    pub const verse_routes = [_]Router.Match{
                        Router.ANY("nop0", Example.nopEndpoint),
                        Router.ANY("nop1", Example.nopEndpoint),
                        Router.ANY("nop2", Example.nopEndpoint),
                        Router.ANY("nop3", Example.nopEndpoint),
                    };
                },
            });
        },
    });
    try std.testing.expectEqual(@as(usize, 5), second.routes.len);
    try std.testing.expectEqualStrings("", second.routes[0].name);
    try std.testing.expectEqualStrings("nop", second.routes[1].name);
    try std.testing.expectEqualStrings("routes", second.routes[2].name);
    try std.testing.expectEqualStrings("static", second.routes[3].name);
    try std.testing.expectEqualStrings("flattened", second.routes[4].name);
    try std.testing.expectEqual(@as(usize, 3), second.routes[4].target.simple.len);
    try std.testing.expectEqualStrings("flat0", second.routes[4].target.simple[0].name);
    try std.testing.expectEqualStrings("flat1", second.routes[4].target.simple[1].name);
    try std.testing.expectEqualStrings("sub_tree", second.routes[4].target.simple[2].name);
    try std.testing.expectEqual(@as(usize, 4), second.routes[4].target.simple[2].target.simple.len);
    try std.testing.expectEqualStrings("nop0", second.routes[4].target.simple[2].target.simple[0].name);
    try std.testing.expectEqualStrings("nop1", second.routes[4].target.simple[2].target.simple[1].name);
    try std.testing.expectEqualStrings("nop2", second.routes[4].target.simple[2].target.simple[2].name);
    try std.testing.expectEqualStrings("nop3", second.routes[4].target.simple[2].target.simple[3].name);

    //const aliased = Endpoints(.{
    //    struct {
    //        pub const verse_name = .root;
    //        pub const verse_flatten_routes = false;
    //        pub const index = Example.nopEndpoint;
    //        pub const verse_routes = [_]Router.Match{
    //            Router.GET("nop", Example.nopEndpoint),
    //            Router.ROUTE("routes", Example.nopEndpoint),
    //            Router.STATIC("static"),
    //        };
    //        pub const verse_builder = &Router.defaultBuilder;
    //    },
    //    struct {
    //        pub const verse_name = .flattened;
    //        pub const verse_routes = [_]Router.Match{
    //            Router.ANY("flat0", Example.nopEndpoint),
    //            Router.ANY("flat1", Example.nopEndpoint),
    //        };
    //        pub const verse_endpoints = Endpoints(.{
    //            struct {
    //                pub const verse_name = .sub_tree;
    //                pub const verse_routes = [_]Router.Match{
    //                    Router.ANY("nop", Example.nopEndpoint),
    //                    Router.ANY("nop2", Example.nopEndpoint),
    //                    Router.ANY("nop3", Example.nopEndpoint),
    //                };
    //            },
    //        });
    //    },
    //});
    //try std.testing.expectEqual(@as(usize, 5), aliased.routes.len);
    //try std.testing.expectEqualStrings("", aliased.routes[0].name);
    //try std.testing.expectEqualStrings("nop", aliased.routes[1].name);
    //try std.testing.expectEqualStrings("routes", aliased.routes[2].name);
    //try std.testing.expectEqualStrings("static", aliased.routes[3].name);
    //try std.testing.expectEqualStrings("flattened", aliased.routes[4].name);
    //try std.testing.expectEqual(@as(usize, 3), aliased.routes[4].target.simple.len);
    //try std.testing.expectEqualStrings("flat0", aliased.routes[4].target.simple[0].name);
    //try std.testing.expectEqualStrings("flat1", aliased.routes[4].target.simple[1].name);
    //try std.testing.expectEqualStrings("sub_tree", aliased.routes[4].target.simple[2].name);
    //try std.testing.expectEqual(@as(usize, 3), aliased.routes[4].target.simple[2].target.simple.len);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const Auth = @import("auth.zig");
const Server = @import("server.zig");
const Router = @import("router.zig");
const testing = @import("testing.zig");
