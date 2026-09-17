const Template = @import("Template.zig");
const compiled = @import("comptime_templates");
const zig_builtin = @import("builtin");

pub const builtin: []const Template = constructTemplates();

pub fn findTemplate(comptime name: []const u8) Template {
    inline for (builtin) |bi| {
        if (comptime eql(u8, bi.name, name)) {
            return bi;
        }
    } else {
        if (comptime zig_builtin.is_test) {
            const test_builtins = @import("builtins_tests.zig");
            inline for (test_builtins.extras) |bi| {
                if (comptime eql(u8, bi.name, name)) {
                    return bi;
                }
            }
        }

        comptime {
            var errstr: [:0]const u8 = "Template " ++ name ++ " not found!";
            for (builtin) |bi| {
                if (endsWith(u8, bi.name, name)) {
                    errstr = errstr ++ "\nDid you mean" ++ " " ++ bi.name ++ "?";
                }
            }
            // If you're reading this, it's probably because your template.html is
            // either missing, not included in the build.zig search dirs, or typo'd.
            // But it's important for you to know... I hope you have a good day :)
            @compileError(errstr);
        }
    }
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

pub var dynamic: []const Template = undefined;

const MAX_BYTES = 2 <<| 15;

const std = @import("std");
const Allocator = std.mem.Allocator;
const endsWith = std.mem.endsWith;
const eql = std.mem.eql;
const indexOfScalar = std.mem.indexOfScalar;
const log = std.log.scoped(.Verse);
