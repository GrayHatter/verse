//! Antibiotic: some basic input sanitation helpers.
//! It won't cure every condition, but it can help treat many diseases

const abx = @This();

pub const Error = error{
    NoSpaceLeft,
    OutOfMemory,
};

pub const Rule = enum {
    filename,
    html,
    path,
    title,

    pub fn func(r: Rule) RuleFn {
        return switch (r) {
            .filename => cleanFilename,
            .html => cleanHtml,
            .path => cleanPath,
            .title => cleanHtml,
        };
    }
};

pub const RuleFn = *const fn (u8, ?[]u8) Error!usize;

/// If an error is returned, the contents of `out` is unspecified.
pub fn clean(comptime rule: Rule, in: []const u8, out: []u8) Error![]u8 {
    const func = rule.func();

    var pos: usize = 0;
    for (in) |src| {
        pos += try func(src, out[pos..]);
    }
    return out[0..pos];
}

/// Same semantics of clean, only will count, and allocate for you.
pub fn cleanAlloc(comptime rule: Rule, a: Allocator, in: []const u8) Error![]u8 {
    const func = rule.func();

    var out_size: usize = 0;
    for (in) |c| out_size +|= try func(c, null);
    const out = try a.alloc(u8, out_size);
    return try clean(rule, in, out);
}

pub const Html = struct {
    text: []const u8,

    pub fn cleanAlloc(a: Allocator, in: []const u8) Error![]u8 {
        return try abx.cleanAlloc(.html, a, in);
    }

    pub fn format(self: Html, comptime _: []const u8, _: FmtOpt, out: anytype) !void {
        var buf: [6]u8 = undefined;
        for (self.text) |c| {
            try out.writeAll(buf[0 .. cleanHtml(c, &buf) catch unreachable]);
        }
    }

    pub fn clean(src: u8) ?[]const u8 {
        return switch (src) {
            '<' => "&lt;",
            '&' => "&amp;",
            '>' => "&gt;",
            '"' => "&quot;",
            '\'' => "&apos;",
            else => null,
        };
    }
};

/// Basic html sanitizer. Will replace all chars, even when it may be
/// unnecessary to do so.
pub fn cleanHtml(in: u8, out: ?[]u8) Error!usize {
    var same = [1:0]u8{in};
    const replace = switch (in) {
        '<' => "&lt;",
        '&' => "&amp;",
        '>' => "&gt;",
        '"' => "&quot;",
        '\'' => "&apos;",
        else => &same,
    };

    // I would like the null check to be comptime, but happy to defer that for now
    if (out) |o| {
        if (replace.len > o.len) return error.NoSpaceLeft;
        @memcpy(o[0..replace.len], replace);
    }
    return replace.len;
}

test Html {
    var a = std.testing.allocator;
    const cleaned = try std.fmt.allocPrint(a, "{}", .{Html{ .text = "<tags not allowed>" }});
    defer a.free(cleaned);

    try std.testing.expectEqualStrings("&lt;tags not allowed&gt;", cleaned);
}

pub const Filename = struct {
    text: []const u8,
    permit_directories: bool = false,

    pub fn cleanAlloc(a: Allocator, in: []const u8) Error![]u8 {
        return try abx.cleanAlloc(.filename, a, in);
    }

    pub fn format(self: Filename, comptime _: []const u8, _: FmtOpt, out: anytype) !void {
        const clean_fn = if (self.permit_directories) cleanPath else cleanFilename;
        var buf: [2]u8 = undefined;
        for (self.text) |txt| {
            try out.writeAll(buf[0..clean_fn(txt, &buf)]);
        }
    }
};

/// Allows subdirectories but not parents.
pub fn cleanPath(in: u8, out: ?[]u8) Error!usize {
    var same = [1:0]u8{in};
    const replace = switch (in) {
        'a'...'z', 'A'...'Z', '0'...'9', '-', '_' => &same,
        ' ', '.' => "-",
        '\n', '\t', '\\' => "",
        else => "",
    };

    // I would like the null check to be comptime, but happy to defer that for now
    if (out) |o| {
        if (replace.len > o.len) return error.NoSpaceLeft;
        @memcpy(o[0..replace.len], replace);
    }
    return replace.len;
}

/// Filters out anything that doesn't look like very boring standard ascii.
/// Intended to be safe and mangle filenames, over allowing all correct/valid
/// names. Patches to improve allowed filenames encouraged!
pub fn cleanFilename(in: u8, out: ?[]u8) Error!usize {
    const replace = switch (in) {
        '/' => "-",
        else => return cleanPath(in, out),
    };

    // I would like the null check to be comptime, but happy to defer that for now
    if (out) |o| {
        if (replace.len > o.len) return error.NoSpaceLeft;
        @memcpy(o[0..replace.len], replace);
    }
    return replace.len;
}

test cleanFilename {
    var a = std.testing.allocator;

    const allowed = "this-filename-is-allowed";
    const not_allowed = "this-file\nname is !really! me$$ed up?";

    var output = try cleanAlloc(.filename, a, allowed);
    try std.testing.expectEqualStrings(allowed, output);
    a.free(output);

    output = try cleanAlloc(.filename, a, not_allowed);
    try std.testing.expectEqualStrings("this-filename-is-really-meed-up", output);
    a.free(output);
}

pub fn streamCleaner(comptime rule: Rule, src: anytype) StreamCleaner(rule, @TypeOf(src)) {
    return StreamCleaner(rule, @TypeOf(src)).init(src);
}

pub fn StreamCleaner(comptime rule: Rule, comptime Source: type) type {
    return struct {
        const Self = @This();

        index: usize,
        src: Source,
        sanitizer: RuleFn,

        fn init(src: Source) Self {
            return Self{
                .index = 0,
                .src = src,
                .sanitizer = rule.func(),
            };
        }

        pub fn any(self: *const Self) std.io.AnyReader {
            return .{
                .context = @ptrCast(*self.context),
                .readFn = typeErasedReadFn,
            };
        }

        pub fn typeErasedReadFn(context: *const anyopaque, buffer: []u8) anyerror!usize {
            const ptr: *const Source = @alignCast(@ptrCast(context));
            return read(ptr.*, buffer);
        }

        pub fn read(self: *Self, buffer: []u8) Error!usize {
            const count = try self.sanitizer(self.src[self.index..], buffer);
            self.index += count;
            return count;
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const FmtOpt = std.fmt.FormatOptions;
