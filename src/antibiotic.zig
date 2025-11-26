//! Antibiotic: some basic input sanitation helpers.
//! It won't cure every condition, but it can help treat many diseases
const abx = @This();
pub const Html = @import("antibiotic/Html.zig");
pub const Path = @import("antibiotic/Path.zig");

pub const Error = error{
    ReadFailed,
    WriteFailed,
};

pub const Rule = enum {
    html,
    path,
    title,
    word,

    pub fn func(r: Rule) RuleFn {
        return switch (r) {
            .html => .{ .chr = Html.clean },
            .path => .{ .str = Path.clean },
            .title => .{ .chr = Html.clean },
            .word => .{ .chr = Path.cleanWord },
        };
    }
    const RuleFn = union(enum) {
        chr: *const fn (u8, *Writer) Error!void,
        str: *const fn (*Reader, *Writer) Error!void,
    };
};

pub fn clean(comptime rule: Rule, in: *Reader, out: *Writer) Error!void {
    switch (comptime rule.func()) {
        .chr => |func| {
            while (in.takeByte()) |c| {
                try func(c, out);
            } else |err| if (err != error.EndOfStream) return err;
        },
        .str => |func| return try func(in, out),
    }
}

test {
    _ = &Html;
    _ = &Path;
}

const std = @import("std");
const eql = std.mem.eql;
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
