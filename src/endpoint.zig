pub const Endpoint = @This();

targets: []Target,

pub const Target = struct {
    name: []const u8,
};

pub fn Endpoints(endpoints: anytype) !Endpoint {
    if (@typeInfo(endpoints).Struct.is_tuple == false) return error.InvalidEndpointTypes;

    return error.NotImplemented;
}

const Verse = @import("verse.zig");
