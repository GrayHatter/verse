const ThisBuild = @This();

const zon: struct {
    name: @TypeOf(.enum_literal),
    version: []const u8,
    fingerprint: usize,
    minimum_zig_version: []const u8,
    dependencies: struct {},
    paths: []const []const u8,
} = @import("build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const use_llvm = true;

    const default_step = b.getInstallStep();

    //if (b.args) |args| for (args) |arg| std.debug.print("arg {s}\n", .{arg});
    //std.debug.print("default: {s}\n", .{b.default_step.name});

    // root build options
    const templates_enabled: bool = b.option(bool, "template-enabled", "enable comptime template generation") orelse true;
    const template_path: ?LazyPath = b.option(LazyPath, "template-path", "path for the templates generated at comptime");
    const ua_validation = b.option(bool, "ua_validation", "[not-implemented] disable user agent validation") orelse
        true;

    const options = b.addOptions();

    const ver = version(b);
    options.addOption([]const u8, "version", ver);
    options.addOption(bool, "ua_validation", ua_validation);

    const verse_lib = b.addModule("verse", .{
        .root_source_file = b.path("src/verse.zig"),
        .target = target,
        .optimize = optimize,
    });
    verse_lib.addOptions("verse_buildopts", options);

    // Set up template compiler
    var compiler = Compiler.init(b);
    if (templates_enabled) {
        if (template_path) |path| {
            compiler.addDir(path);
        } else {
            compiler.addDir(b.path("examples/templates/"));
            compiler.addDir(b.path("src/builtin-html/"));
        }
        compiler.addFile(b.path("src/builtin-html/verse-stats.html"));
        compiler.collect(b.graph.io) catch @panic("unreachable");
    }
    const comptime_templates = compiler.buildTemplates() catch @panic("unreachable");

    const structc = b.addExecutable(.{
        .name = "structc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/struct-emit.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    structc.root_module.addImport("comptime_templates", comptime_templates);
    default_step.dependOn(&structc.step);

    const comptime_structs = compiler.buildStructs(structc) catch @panic("unreachable");

    verse_lib.addImport("comptime_structs", comptime_structs);
    verse_lib.addImport("comptime_templates", comptime_templates);

    const lib_tests = b.addTest(.{
        .root_module = verse_lib,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    lib_tests.root_module.addOptions("verse_buildopts", options);
    lib_tests.root_module.addImport("comptime_templates", comptime_templates);
    lib_tests.root_module.addImport("comptime_structs", comptime_structs);
    const run_lib_tests = b.addRunArtifact(lib_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    const quick_test_step = b.step("quicktest", "Run unit tests only [exclude examples]");
    quick_test_step.dependOn(&run_lib_tests.step);

    const docs = b.addObject(.{ .name = "verse", .root_module = verse_lib });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Build Verse Docs");
    docs_step.dependOn(&install_docs.step);

    const examples = [_][]const u8{
        "api",              "auth-cookie", "basic",    "cookies",       "endpoint",
        "request-userdata", "stats",       "template", "template-enum", "template-extra",
        "websocket",
    };
    inline for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = example,
            .root_module = b.createModule(.{
                .root_source_file = b.path("examples/" ++ example ++ ".zig"),
                .target = target,
                .optimize = optimize,
            }),
            .use_llvm = use_llvm,
            .use_lld = use_llvm,
        });
        // All Examples should compile for tests to pass
        test_step.dependOn(&example_exe.step);

        example_exe.root_module.addImport("verse", verse_lib);

        const run_example = b.addRunArtifact(example_exe);
        run_example.step.dependOn(b.getInstallStep());
        if (b.args) |args| {
            run_example.addArgs(args);
        }
        const run_name = "run-" ++ example;
        const run_description = "Run example: " ++ example;
        const run_step = b.step(run_name, run_description);
        run_step.dependOn(&run_example.step);
    }
}

const Compiler = struct {
    b: *std.Build,
    dirs: ArrayList(LazyPath),
    files: ArrayList(LazyPath),
    collected: ArrayList(LazyPath),
    templates: ?*Module = null,
    structs: ?*Module = null,
    debugging: bool = false,

    pub fn init(b: *std.Build) Compiler {
        return .{ .b = b, .dirs = .{}, .files = .{}, .collected = .{} };
    }

    pub fn raze(comp: Compiler) void {
        for (comp.dirs.items) |each| comp.b.allocator.free(each);
        comp.dirs.deinit();
        for (comp.files.items) |each| comp.b.allocator.free(each);
        comp.files.deinit();
        for (comp.collected.items) |each| comp.b.allocator.free(each);
        comp.collected.deinit();
    }

    pub fn depPath(comp: *Compiler, path: []const u8) LazyPath {
        return if (comp.b.available_deps.len > 0)
            comp.b.dependencyFromBuildZig(ThisBuild, .{}).path(path)
        else
            comp.b.path(path);
    }

    pub fn addDir(comp: *Compiler, dir: LazyPath) void {
        comp.dirs.append(comp.b.allocator, dir) catch @panic("OOM");
        comp.templates = null;
        comp.structs = null;
    }

    pub fn addFile(comp: *Compiler, file: LazyPath) void {
        comp.files.append(comp.b.allocator, file) catch @panic("OOM");
        comp.templates = null;
        comp.structs = null;
    }

    pub fn buildTemplates(comp: *Compiler) !*Module {
        if (comp.templates) |t| return t;
        const compiled = comp.b.createModule(.{
            .root_source_file = comp.depPath("src/template/comptime.zig"),
        });

        const found = comp.b.addOptions();
        const names: [][]const u8 = comp.b.allocator.alloc([]const u8, comp.collected.items.len) catch @panic("OOM");

        for (comp.collected.items, names) |lpath, *name| {
            name.* = lpath.getPath3(comp.b, null).sub_path;
            _ = compiled.addAnonymousImport(name.*, .{ .root_source_file = lpath });
        }

        found.addOption([]const []const u8, "names", names);
        compiled.addOptions("config", found);
        comp.templates = compiled;
        return compiled;
    }

    pub fn buildStructs(comp: *Compiler, step: *std.Build.Step.Compile) !*Module {
        if (comp.structs) |s| return s;

        if (comp.debugging) std.debug.print("building structs for {}\n", .{comp.collected.items.len});
        const tc_build_run = comp.b.addRunArtifact(step);
        const tc_structs = tc_build_run.addOutputFileArg("compiled-structs.zig");
        const module = comp.b.createModule(.{ .root_source_file = tc_structs });

        comp.structs = module;
        return module;
    }

    pub fn collect(comp: *Compiler, io: std.Io) !void {
        for (comp.dirs.items) |srcdir| {
            try comp.collectDir(srcdir, io);
        }
        for (comp.files.items) |file| {
            try comp.collected.append(comp.b.allocator, file);
        }
    }

    fn collectDir(comp: *Compiler, path: LazyPath, io: std.Io) !void {
        var idir = path.getPath3(comp.b, null).openDir(io, "", .{ .iterate = true }) catch |err| {
            std.debug.print("template build error {} for srcdir {}\n", .{ err, path });
            return err;
        };
        defer idir.close(comp.b.graph.io);

        var itr = try idir.walk(comp.b.allocator);
        while (try itr.next(comp.b.graph.io)) |file| {
            switch (file.kind) {
                .file => {
                    if (!std.mem.endsWith(u8, file.basename, ".html")) continue;
                    //const name = try std.mem.join(comp.b.allocator, "/", &[2][]const u8{ file.path, file.basename });
                    try comp.collected.append(comp.b.allocator, path.path(comp.b, file.path));
                },
                .directory => {},
                else => {},
            }
        }
    }
};

fn version(b: *std.Build) []const u8 {
    if (!std.process.can_spawn) {
        return zon.version;
    }

    var code: u8 = undefined;
    const git_wide = b.runAllowFail(
        &[_][]const u8{
            "git",
            "-C",
            b.build_root.path orelse ".",
            "describe",
            "--dirty",
            "--always",
        },
        &code,
        .ignore,
    ) catch zon.version;

    var git = std.mem.trim(u8, git_wide, " \r\n");
    if (git[0] == 'v') git = git[1..];
    //std.debug.print("version {s}\n", .{git});

    // semver is really dumb, so we need to increment this internally
    var ver = std.SemanticVersion.parse(git) catch return zon.version ++ "-giterr";
    if (ver.pre != null) {
        ver.minor += 1;
        ver.pre = std.fmt.allocPrint(b.allocator, "pre-{s}", .{ver.pre.?}) catch @panic("OOM");
    }

    const final = std.fmt.allocPrint(b.allocator, "{f}", .{ver}) catch @panic("OOM");
    //std.debug.print("version {s}\n", .{final});
    return final;
}

const std = @import("std");
const ArrayList = std.ArrayList;
const LazyPath = std.Build.LazyPath;
const Module = std.Build.Module;
