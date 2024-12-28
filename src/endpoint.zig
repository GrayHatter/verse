pub const Endpoint = @This();

targets: []Target,

pub const Target = struct {
    name: []const u8,
};

pub const Options = struct {
    mode: Verse.Server.RunMode = .{ .http = .{} },
    auth: Verse.Auth.AnyAuth = .{ .ctx = undefined, .vtable = Verse.Auth.VTable.DefaultEmpty },
};

pub fn Endpoints(endpoints: anytype) type {
    if (@typeInfo(@TypeOf(endpoints)).Struct.is_tuple == false) return error.InvalidEndpointTypes;
    inline for (endpoints) |ep| {
        validateEndpoint(ep);
    }
    return struct {
        pub const Self = @This();
        pub const Endpoints = endpoints;

        pub const routes = buildRoutes(endpoints[0]);

        pub fn init() Self {
            return .{};
        }

        pub fn serve(_: *Self, a: Allocator, options: Options) !void {
            var server = try Verse.Server.init(a, .{
                .mode = options.mode,
                .router = .{ .routefn = route },
            });
            try server.serve();
        }

        pub fn route(v: *Verse) !Verse.Router.BuildFn {
            return Verse.Router.router(v, &routes);
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
        if (std.mem.eql(u8, "index", decl.name)) count += 1;
    }
    return count;
}

fn buildRoutes(EP: anytype) [routeCount(EP)]Verse.Router.Match {
    var match: [routeCount(EP)]Verse.Router.Match = undefined;
    var idx: usize = 0;
    for (@typeInfo(EP).Struct.decls) |decl| {
        if (std.mem.eql(u8, "index", decl.name)) {
            match[idx] = Verse.Router.ANY("", EP.index);
            idx += 1;
        }
    }

    return match;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Verse = @import("verse.zig");
