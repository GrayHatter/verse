const Template = @import("Template.zig");
const compiled = @import("comptime_templates");

pub const builtin: []const Template = constructTemplates();

pub fn findTemplate(comptime name: []const u8) Template {
    inline for (builtin) |bi| {
        if (comptime eql(u8, bi.name, name)) {
            return bi;
        }
    }

    var errstr: [:0]const u8 = "Template " ++ name ++ " not found!";
    inline for (builtin) |bi| {
        if (comptime endsWith(u8, bi.name, name)) {
            errstr = errstr ++ "\nDid you mean" ++ " " ++ bi.name ++ "?";
        }
    }
    // If you're reading this, it's probably because your template.html is
    // either missing, not included in the build.zig search dirs, or typo'd.
    // But it's important for you to know... I hope you have a good day :)
    @compileError(errstr);
}

fn constructTemplates() []const Template {
    var t: []const Template = &[0]Template{};
    for (compiled.data) |filedata| {
        t = t ++ [_]Template{.{
            .name = tailPath(filedata.path),
            .blob = filedata.blob,
        }};
    }
    return t;
}

fn tailPath(path: []const u8) []const u8 {
    if (indexOfScalar(u8, path, '/')) |i| {
        return path[i + 1 ..];
    }
    return path[0..0];
}

fn intToWord(in: u8) []const u8 {
    return switch (in) {
        '4' => "Four",
        '5' => "Five",
        else => unreachable,
    };
}

pub fn makeStructName(comptime in: []const u8, comptime out: []u8) usize {
    var ltail = in;
    if (comptime std.mem.lastIndexOf(u8, in, "/")) |i| {
        ltail = ltail[i..];
    }

    var i = 0;
    var next_upper = true;
    inline for (ltail) |chr| {
        switch (chr) {
            'a'...'z', 'A'...'Z' => {
                if (next_upper) {
                    out[i] = std.ascii.toUpper(chr);
                } else {
                    out[i] = chr;
                }
                next_upper = false;
                i += 1;
            },
            '0'...'9' => {
                for (intToWord(chr)) |cchr| {
                    out[i] = cchr;
                    i += 1;
                }
            },
            '-', '_', '.' => {
                next_upper = true;
            },
            else => {},
        }
    }

    return i;
}

pub fn makeFieldName(in: []const u8, out: []u8) usize {
    var i: usize = 0;
    for (in) |chr| {
        switch (chr) {
            'a'...'z' => {
                out[i] = chr;
                i += 1;
            },
            'A'...'Z' => {
                if (i != 0) {
                    out[i] = '_';
                    i += 1;
                }
                out[i] = std.ascii.toLower(chr);
                i += 1;
            },
            '0'...'9' => {
                for (intToWord(chr)) |cchr| {
                    out[i] = cchr;
                    i += 1;
                }
            },
            '-', '_', '.' => {
                out[i] = '_';
                i += 1;
            },
            else => {},
        }
    }

    return i;
}
pub var dynamic: []const Template = undefined;

const MAX_BYTES = 2 <<| 15;

fn loadDynamicTemplates(a: Allocator, path: []const u8) !void {
    var cwd = std.fs.cwd();
    var idir = cwd.openDir(path, .{ .iterate = true }) catch |err| {
        log.warn("Unable to build dynamic templates ({})", .{err});
        return;
    };
    defer idir.close();
    var itr = idir.iterate();
    var list = std.ArrayList(Template).init(a);
    errdefer list.clearAndFree();
    while (try itr.next()) |file| {
        if (file.kind != .file) continue;
        const name = try std.mem.join(a, "/", &[2][]const u8{
            path,
            file.name,
        });
        defer a.free(name);
        const tail = tailPath(file.name);
        const name_ = try a.dupe(u8, tail);
        try list.append(.{
            //.path = path,
            .name = name_,
            .blob = try cwd.readFileAlloc(a, name, MAX_BYTES),
        });
    }
    dynamic = try list.toOwnedSlice();
}

pub fn initDynamic(a: Allocator, path: []const u8) void {
    loadDynamicTemplates(a, path) catch unreachable;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const endsWith = std.mem.endsWith;
const eql = std.mem.eql;
const indexOfScalar = std.mem.indexOfScalar;
const log = std.log.scoped(.Verse);
