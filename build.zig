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
    const use_llvm = false;

    const default_step = b.getInstallStep();

    // root build options
    const abx_required: bool = b.option(bool, "abx-required",
        \\templates will default to Abx instead of []const u8
    ) orelse false;

    const templates: []const LazyPath = b.option([]const LazyPath, "templates",
        \\path for the templates generated at comptime
    ) orelse &.{};

    const ua_validation = b.option(bool, "ua-validation",
        \\[not-implemented] disable user agent validation
    ) orelse true;

    const accept_lang_heat = b.option([]const u8, "accept-lang-heat",
        \\[not-implemented] add bot detection heat to given language
    ) orelse "";

    const options = b.addOptions();

    const ver = version(b);
    options.addOption([]const u8, "version", ver);
    options.addOption(bool, "abx-required", abx_required);
    options.addOption(bool, "ua-validation", ua_validation);
    options.addOption([]const u8, "accept-lang-heat", accept_lang_heat);

    const verse_lib = b.addModule("verse", .{
        .root_source_file = b.path("src/verse.zig"),
        .target = target,
        .optimize = optimize,
    });
    verse_lib.addOptions("verse_buildopts", options);

    const abx = b.addModule("Antibiotic", .{
        .root_source_file = b.path("src/Antibiotic.zig"),
        .target = target,
        .optimize = optimize,
    });
    verse_lib.addImport("Antibiotic", abx);

    // Set up template compiler
    var compiler = Compiler.init(b);
    for (templates) |path| {
        compiler.addFile(path);
    }

    if (templates.len == 0) {
        compiler.addDir(b.path("examples/templates/"));
        compiler.addDir(b.path("src/builtin-html/"));
    }
    compiler.addFile(b.path("src/builtin-html/verse-stats.html"));
    compiler.collect();

    const comptime_templates = compiler.moduleTemplate();

    const structc = b.addExecutable(.{
        .name = "structc",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/struct-emit.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    structc.root_module.addImport("comptime_templates", comptime_templates);
    structc.root_module.addOptions("verse_buildopts", options);
    default_step.dependOn(&structc.step);

    const comptime_structs = compiler.moduleStruct(structc);
    comptime_structs.addImport("Antibiotic", abx);

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

    const abx_tests = b.addTest(.{
        .root_module = abx,
        .use_llvm = use_llvm,
        .use_lld = use_llvm,
    });
    const abx_tests_run = b.addRunArtifact(abx_tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_tests.step);
    test_step.dependOn(&abx_tests_run.step);
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
        run_example.addPassthruArgs();
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
        return .{
            .b = b,
            .dirs = .empty,
            .files = .empty,
            .collected = .empty,
        };
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

    pub fn moduleTemplate(comp: *Compiler) *Module {
        if (comp.templates) |t| return t;

        const compiled = comp.b.createModule(.{
            .root_source_file = comp.depPath("src/template/comptime.zig"),
        });

        const found = comp.b.addOptions();
        const names: [][]const u8 = comp.b.allocator.alloc([]const u8, comp.collected.items.len) catch @panic("OOM");

        for (comp.collected.items, names) |lpath, *name| {
            name.* = comp.b.fmt("{f}", .{lpath});
            _ = compiled.addAnonymousImport(name.*, .{ .root_source_file = lpath });
        }

        found.addOption([]const []const u8, "names", names);
        compiled.addOptions("config", found);
        comp.templates = compiled;
        return compiled;
    }

    pub fn moduleStruct(comp: *Compiler, step: *std.Build.Step.Compile) *Module {
        if (comp.structs) |s| return s;

        if (comp.debugging) std.debug.print("building structs for {}\n", .{comp.collected.items.len});

        const tc_build_run = comp.b.addRunArtifact(step);
        const tc_structs = tc_build_run.addOutputFileArg("compiled-structs.zig");
        const s_module = comp.b.createModule(.{ .root_source_file = tc_structs });

        comp.structs = s_module;
        return s_module;
    }

    pub fn collect(comp: *Compiler) void {
        for (comp.dirs.items) |srcdir|
            comp.collectDir(srcdir);
        for (comp.files.items) |file| {
            comp.b.dependOnFileContents(file);
            comp.collected.append(comp.b.allocator, file) catch @panic("OOM");
        }
    }

    fn collectDir(comp: *Compiler, path: LazyPath) void {
        comp.b.dependOnDirectoryContents(path);

        const a = comp.b.allocator;
        const io = comp.b.graph.io;
        const filename = comp.b.fmt("{f}", .{path});
        //std.debug.print("filename {s}\n", .{filename});
        const dir = comp.b.root.openDir(io, filename, .{ .iterate = true }) catch |err| switch (err) {
            else => @panic("unable to open dir"),
        };
        defer dir.close(io);

        var itr = dir.walk(a) catch @panic("OOM");
        while (itr.next(io) catch @panic("IO")) |file| {
            switch (file.kind) {
                .file => if (std.mem.endsWith(u8, file.basename, ".html")) {
                    //std.debug.print("basename {s}\n", .{file.basename});
                    const new = path.path(comp.b, a.dupe(u8, file.path) catch @panic("OOM"));
                    comp.collected.append(a, new) catch @panic("OOM");
                    comp.b.dependOnFileContents(new);
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

    const git_wide: []const u8 = switch (b.runFallible(&[_][]const u8{
        "git",
        "-C",       b.fmt("{f}", .{b.root}), //
        "describe", "--dirty",
        "--always",
    }, .{})) {
        .success => |out| out,
        else => zon.version,
    };

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
