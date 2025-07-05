//! `verse_name = .root` is a special case name to enable resolve at "/", and only
//! valid as a top level endpoint definition. Otherwise for any endpoint
//! hierarchy depth > 0 `verse_name = .root` will resolve to "/root".

pub const verse_name = .root;

pub const verse_routes = [_]Router.Match{
    Router.ANY("hi", hi),
};

/// verse_endpoint_enabled is an option decl that defaults to true if omitted
pub const verse_endpoint_enabled: bool = true;

/// This is commented out here, as it's included within the root endpoint,
/// but because this endpoint will be flattened out into root directory;
/// declaring it here, or there are equivalent options.
pub const verse_endpoints = verse.Endpoints(.{
    //    @import("random.zig"),
});

pub fn index(frame: *Frame) !void {
    try frame.sendHTML(.ok, "hello world");
}

fn hi(frame: *Frame) !void {
    try frame.sendHTML(.ok, "hi, mom!");
}

const verse = @import("verse");
const Frame = verse.Frame;
const Router = verse.Router;
