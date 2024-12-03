const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const module = b.addModule("verse", .{
        .root_source_file = b.path("src/verse.zig"),
        .target = target,
        .optimize = optimize,
    });

    const t_compiler = b.addExecutable(.{
        .name = "template-compiler",
        .root_source_file = b.path("src/template-compiler.zig"),
        .target = target,
    });

    const tc_build_run = b.addRunArtifact(t_compiler);
    const tc_build_step = b.step("templates", "Compile templates down into struct");
    tc_build_step.dependOn(&tc_build_run.step);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/verse.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (std.fs.cwd().access("src/fallback_html/index.html", .{})) {
        const comptime_templates = Compiler.buildTemplates(b, "src/fallback_html/") catch unreachable;
        // Zig build time doesn't expose it's state in a way I know how to check...
        // so we yolo it like python :D
        lib_unit_tests.root_module.addImport("comptime_templates", comptime_templates);
    } else |_| {}
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const examples = [_][]const u8{"basic"};
    for (examples) |example| {
        const path = try std.fmt.allocPrint(b.allocator, "examples/{s}.zig", .{example});
        const example_exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path(path),
            .target = target,
            .optimize = optimize,
        });
        // All Examples should compile for tests to pass
        test_step.dependOn(&example_exe.step);

        example_exe.root_module.addImport("verse", module);

        const run_example = b.addRunArtifact(example_exe);
        run_example.step.dependOn(b.getInstallStep());

        if (b.args) |args| {
            run_example.addArgs(args);
        }

        const run_name = try std.fmt.allocPrint(b.allocator, "run-{s}", .{example});
        const run_description = try std.fmt.allocPrint(b.allocator, "Run example: {s}", .{example});
        const run_step = b.step(run_name, run_description);
        run_step.dependOn(&run_example.step);
    }
}

pub const Compiler = struct {
    pub fn buildTemplates(b: *std.Build, srcdir: []const u8) !*std.Build.Module {
        const list = try buildList(b, srcdir);
        const local_dir = std.fs.path.dirname(@src().file) orelse ".";
        const compiled = b.createModule(.{
            .root_source_file = .{
                .cwd_relative = b.pathJoin(&.{ local_dir, "src/template/comptime.zig" }),
            },
        });

        const found = b.addOptions();
        found.addOption([]const []const u8, "names", list.items);
        compiled.addOptions("config", found);

        for (list.items) |file| {
            _ = compiled.addAnonymousImport(file, .{
                .root_source_file = b.path(file),
            });
        }

        return compiled;
    }

    pub fn buildStructs(b: *std.Build, srcdir: []const u8) !*std.Build.Module {
        const local_dir = std.fs.path.dirname(@src().file) orelse ".";
        const t_compiler = b.addExecutable(.{
            .name = "template-compiler",
            .root_source_file = .{
                .cwd_relative = b.pathJoin(&.{ local_dir, "src/template-compiler.zig" }),
            },
            .target = b.host,
        });

        const comptime_templates = try buildTemplates(b, srcdir);
        t_compiler.root_module.addImport("comptime_templates", comptime_templates);
        const tc_build_run = b.addRunArtifact(t_compiler);
        const tc_structs = tc_build_run.addOutputFileArg("compiled-structs.zig");
        const tc_build_step = b.step("templates", "Compile templates down into struct");
        tc_build_step.dependOn(&tc_build_run.step);
        const module = b.createModule(.{
            .root_source_file = tc_structs,
        });

        return module;
    }

    fn buildList(b: *std.Build, srcdir: []const u8) !std.ArrayList([]const u8) {
        var cwd = std.fs.cwd();
        var idir = cwd.openDir(srcdir, .{ .iterate = true }) catch |err| {
            std.debug.print("template build error {} for srcdir {s}\n", .{ err, srcdir });
            return err;
        };
        var list = std.ArrayList([]const u8).init(b.allocator);
        errdefer list.deinit();
        var itr = idir.iterate();
        while (try itr.next()) |file| {
            if (!std.mem.endsWith(u8, file.name, ".html")) continue;
            try list.append(b.pathJoin(&[2][]const u8{ srcdir, file.name }));
        }

        return list;
    }
};
