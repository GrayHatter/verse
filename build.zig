const std = @import("std");
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

    //if (b.args) |args| for (args) |arg| std.debug.print("arg {s}\n", .{arg});
    //std.debug.print("default: {s}\n", .{b.default_step.name});

    // root build options
    const template_path: ?std.Build.LazyPath = b.option(std.Build.LazyPath, "template-path", "path for the templates generated at comptime");
    const bot_detection = b.option(bool, "bot-detection", "path for the templates generated at comptime") orelse
        false;

    const options = b.addOptions();

    const ver = version(b);
    options.addOption([]const u8, "version", ver);
    options.addOption(bool, "botdetection", bot_detection);

    const verse_lib = b.addModule("verse", .{
        .root_source_file = b.path("src/verse.zig"),
        .target = target,
        .optimize = optimize,
    });

    verse_lib.addOptions("verse_buildopts", options);

    // Set up template compiler
    var compiler = Compiler.init(b);
    if (template_path) |path| {
        compiler.addDir(path);
    } else {
        compiler.addDir(b.path("examples/templates/"));
        compiler.addDir(b.path("src/builtin-html/"));
    }
    compiler.addFile(b.path("src/builtin-html/verse-stats.html"));
    compiler.collect() catch @panic("unreachable");

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
    const quick_test_step = b.step("unit-test", "Run unit tests only [exclude examples]");
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
        "basic",            "cookies", "template",  "endpoint", "auth-cookie",
        "request-userdata", "api",     "websocket", "stats",
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

const ThisBuild = @This();

const Compiler = struct {
    b: *std.Build,
    dirs: std.ArrayListUnmanaged(std.Build.LazyPath),
    files: std.ArrayListUnmanaged(std.Build.LazyPath),
    collected: std.ArrayListUnmanaged(std.Build.LazyPath),
    templates: ?*std.Build.Module = null,
    structs: ?*std.Build.Module = null,
    debugging: bool = false,

    pub fn init(b: *std.Build) Compiler {
        return .{ .b = b, .dirs = .{}, .files = .{}, .collected = .{} };
    }

    pub fn raze(self: Compiler) void {
        for (self.dirs.items) |each| self.b.allocator.free(each);
        self.dirs.deinit();
        for (self.files.items) |each| self.b.allocator.free(each);
        self.files.deinit();
        for (self.collected.items) |each| self.b.allocator.free(each);
        self.collected.deinit();
    }

    pub fn depPath(self: *Compiler, path: []const u8) std.Build.LazyPath {
        return if (self.b.available_deps.len > 0)
            self.b.dependencyFromBuildZig(ThisBuild, .{}).path(path)
        else
            self.b.path(path);
    }

    pub fn addDir(self: *Compiler, dir: std.Build.LazyPath) void {
        self.dirs.append(self.b.allocator, dir) catch @panic("OOM");
        self.templates = null;
        self.structs = null;
    }

    pub fn addFile(self: *Compiler, file: std.Build.LazyPath) void {
        self.files.append(self.b.allocator, file) catch @panic("OOM");
        self.templates = null;
        self.structs = null;
    }

    pub fn buildTemplates(self: *Compiler) !*std.Build.Module {
        if (self.templates) |t| return t;
        const compiled = self.b.createModule(.{
            .root_source_file = self.depPath("src/template/comptime.zig"),
        });

        const found = self.b.addOptions();
        const names: [][]const u8 = self.b.allocator.alloc([]const u8, self.collected.items.len) catch @panic("OOM");

        for (self.collected.items, names) |lpath, *name| {
            name.* = lpath.getPath3(self.b, null).sub_path;
            _ = compiled.addAnonymousImport(name.*, .{ .root_source_file = lpath });
        }

        found.addOption([]const []const u8, "names", names);
        compiled.addOptions("config", found);
        self.templates = compiled;
        return compiled;
    }

    pub fn buildStructs(self: *Compiler, comp: *std.Build.Step.Compile) !*std.Build.Module {
        if (self.structs) |s| return s;

        if (self.debugging) std.debug.print("building structs for {}\n", .{self.collected.items.len});
        const tc_build_run = self.b.addRunArtifact(comp);
        const tc_structs = tc_build_run.addOutputFileArg("compiled-structs.zig");
        const module = self.b.createModule(.{ .root_source_file = tc_structs });

        self.structs = module;
        return module;
    }

    pub fn collect(self: *Compiler) !void {
        for (self.dirs.items) |srcdir| {
            try self.collectDir(srcdir);
        }
        for (self.files.items) |file| {
            try self.collected.append(self.b.allocator, file);
        }
    }

    fn collectDir(self: *Compiler, path: std.Build.LazyPath) !void {
        var idir = path.getPath3(self.b, null).openDir("", .{ .iterate = true }) catch |err| {
            std.debug.print("template build error {} for srcdir {}\n", .{ err, path });
            return err;
        };
        defer idir.close();

        var itr = try idir.walk(self.b.allocator);
        while (try itr.next()) |file| {
            switch (file.kind) {
                .file => {
                    if (!std.mem.endsWith(u8, file.basename, ".html")) continue;
                    //const name = try std.mem.join(self.b.allocator, "/", &[2][]const u8{ file.path, file.basename });
                    try self.collected.append(self.b.allocator, path.path(self.b, file.path));
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
        .Ignore,
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
