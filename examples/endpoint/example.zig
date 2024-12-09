/// .root is a special cased name to resolve at "/"
pub const verse_name = .root;

pub fn index(vrs: *verse.Verse) !void {
    try vrs.quickStart();
    try vrs.sendRawSlice("hello world");
}

const verse = @import("verse");
