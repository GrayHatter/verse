/// .root is a special cased name to resolve at "/"
pub const verse_name = .root;

pub fn index(frame: *verse.Frame) !void {
    try frame.quickStart();
    try frame.sendRawSlice("hello world");
}

const verse = @import("verse");
