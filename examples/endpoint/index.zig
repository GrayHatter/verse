//! `verse_name = .root` is a special case name to enable resolve at "/", and only
//! valid as a top level endpoint definition. Otherwise for any endpoint
//! hierarchy depth > 0 `verse_name = .root` will resolve to "/root".

pub const verse_name = .root;

pub const verse_routes = [_]Router.Match{
    Router.ANY("hi", hi),
};

/// This is commented out here, as it's included within the root endpoint,
/// but because this endpoint will be flattened out into root directory;
/// declaring it here, or there are equivalent options.
pub const verse_endpoints = verse.Endpoints(.{
    //    @import("random.zig"),
});

pub fn index(frame: *Frame) !void {
    try frame.sendHTML("hello world", .ok);
}

fn hi(frame: *Frame) !void {
    try frame.sendHTML("hi, mom!", .ok);
}

const verse = @import("verse");
const Frame = verse.Frame;
const Router = verse.Router;
