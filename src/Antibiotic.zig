//! Antibiotic: some basic input sanitation helpers.
//! It won't cure every condition, but it can help treat many diseases

bytes: Bytes,

const Antibiotic = @This();
/// Abx is the suggested alias.
const Abx = Antibiotic;

pub const Html = @import("Antibiotic/Html.zig");
pub const Path = @import("Antibiotic/Path.zig");

pub const Error = error{
    ReadFailed,
    WriteFailed,
};

pub const Bytes = union(enum) {
    dirty: []const u8,
    safe: []const u8,
    stream: *Reader,
    /// Owned is always cleaned text.
    owned: []const u8,

    pub fn raze(b: *const Bytes, a: Allocator) void {
        switch (b) {
            .dirty, .clean => {},
            .owned => |o| a.free(o),
            // TODO
            .stream => unreachable,
        }
    }
};

pub fn abx(text: []const u8) Antibiotic {
    return .{ .bytes = .{ .dirty = text } };
}

pub fn safe(text: []const u8) Antibiotic {
    return .{ .bytes = .{ .safe = text } };
}

pub fn abxAlloc(text: []const u8, a: Allocator) error{OutOfMemory}!Antibiotic {
    return .{ .bytes = .{ .owned = try std.fmt.allocPrint(a, "{s}", .{text}) } };
}

pub fn safeDupe(text: []const u8, a: Allocator) error{OutOfMemory}!Antibiotic {
    return .{ .bytes = .{ .owned = try a.dupe(u8, text) } };
}

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

    pub fn clean(comptime rule: Rule, in: *Reader, out: *Writer) Error!void {
        switch (comptime rule.func()) {
            .chr => |fnc| while (in.takeByte()) |c| {
                try fnc(c, out);
            } else |err| if (err != error.EndOfStream) return err,
            .str => |fnc| return try fnc(in, out),
        }
    }
};

pub fn format(abiot: *const Antibiotic, w: *Writer) error{WriteFailed}!void {
    switch (abiot.bytes) {
        .dirty => |dirt| for (dirt) |d| try Html.clean(d, w),
        .safe => |s| try w.writeAll(s),
        .owned => |o| try w.writeAll(o),
        // TODO
        .stream => unreachable,
    }
}

test {
    _ = &std.testing.refAllDecls(@This());
    _ = &Html;
    _ = &Path;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Reader = std.Io.Reader;
const Writer = std.Io.Writer;
