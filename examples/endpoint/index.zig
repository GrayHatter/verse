//! `verse_name = .root` is a special case name to enable resolve at "/", and only
//! valid as a top level endpoint definition. Otherwise for any endpoint
//! hierarchy depth > 0 `verse_name = .root` will resolve to "/root".

pub const verse_name = .root;

pub const verse_routes = [_]Router.Match{
    Router.ANY("hi", hi),
};

pub const verse_endpoints = verse.Endpoints(.{
    @import("random.zig"),
});

pub fn index(frame: *Frame) !void {
    try frame.quickStart();
    try frame.sendRawSlice("hello world");
}

fn hi(frame: *Frame) !void {
    try frame.quickStart();
    try frame.sendRawSlice("hi, mom!");
}

const verse = @import("verse");
const Frame = verse.Frame;
const Router = verse.Router;