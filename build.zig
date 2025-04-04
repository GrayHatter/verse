const std = @import("std");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const ver = version(b);
    const options = b.addOptions();
    options.addOption([]const u8, "version", ver);
    options.addOption(bool, "botdetection", true);

    const verse_lib = b.addModule("verse", .{
        .root_source_file = b.path("src/verse.zig"),
        .target = target,
        .optimize = optimize,
    });

    verse_lib.addOptions("verse_buildopts", options);

    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/verse.zig"),
        .target = target,
        .optimize = optimize,
    });
    lib_unit_tests.root_module.addOptions("verse_buildopts", options);

    var compiler = Compiler.init(b);

    var comptime_structs: ?*std.Build.Module = null;
    var comptime_templates: ?*std.Build.Module = null;

    if (std.fs.cwd().access("src/fallback_html/index.html", .{})) {
        compiler.addDir("src/fallback_html/");
        compiler.addDir("examples/templates/");
        compiler.collect() catch unreachable;
        comptime_templates = compiler.buildTemplates() catch unreachable;
        // Zig build time doesn't expose it's state in a way I know how to check...
        // so we yolo it like python :D
        lib_unit_tests.root_module.addImport("comptime_templates", comptime_templates orelse unreachable);
        comptime_structs = compiler.buildStructs() catch unreachable;
        lib_unit_tests.root_module.addImport("comptime_structs", comptime_structs orelse unreachable);

        verse_lib.addImport("comptime_structs", comptime_structs orelse @panic("structs missing"));
        verse_lib.addImport("comptime_templates", comptime_templates orelse @panic("structs missing"));
    } else |_| {}
    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_lib_unit_tests.step);

    const docs = b.addObject(.{ .name = "verse", .root_module = verse_lib });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    const docs_step = b.step("docs", "Build Verse Docs");
    docs_step.dependOn(&install_docs.step);

    const examples = [_][]const u8{
        "basic",
        "cookies",
        "template",
        "endpoint",
        "auth-cookie",
        "request-userdata",
        "api",
        "websocket",
    };
    inline for (examples) |example| {
        const example_exe = b.addExecutable(.{
            .name = example,
            .root_source_file = b.path("examples/" ++ example ++ ".zig"),
            .target = target,
            .optimize = optimize,
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

pub const Compiler = struct {
    b: *std.Build,
    dirs: std.ArrayList([]const u8),
    files: std.ArrayList([]const u8),
    collected: std.ArrayList([]const u8),
    templates: ?*std.Build.Module = null,
    structs: ?*std.Build.Module = null,
    debugging: bool = false,

    pub fn init(b: *std.Build) Compiler {
        return .{
            .b = b,
            .dirs = std.ArrayList([]const u8).init(b.allocator),
            .files = std.ArrayList([]const u8).init(b.allocator),
            .collected = std.ArrayList([]const u8).init(b.allocator),
        };
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

    pub fn addDir(self: *Compiler, dir: []const u8) void {
        const copy = self.b.allocator.dupe(u8, dir) catch @panic("OOM");
        self.dirs.append(copy) catch @panic("OOM");
        self.templates = null;
        self.structs = null;
    }

    pub fn addFile(self: *Compiler, file: []const u8) void {
        const copy = self.b.allocator.dupe(u8, file) catch @panic("OOM");
        self.files.append(copy) catch @panic("OOM");
        self.templates = null;
        self.structs = null;
    }

    pub fn buildTemplates(self: *Compiler) !*std.Build.Module {
        if (self.templates) |t| return t;

        //std.debug.print("building for {}\n", .{self.collected.items.len});
        const compiled = self.b.createModule(.{
            .root_source_file = self.depPath("src/template/comptime.zig"),
        });

        const found = self.b.addOptions();
        found.addOption([]const []const u8, "names", self.collected.items);
        compiled.addOptions("config", found);

        for (self.collected.items) |file| {
            _ = compiled.addAnonymousImport(file, .{
                .root_source_file = self.b.path(file),
            });
        }

        self.templates = compiled;
        return compiled;
    }

    pub fn buildStructs(self: *Compiler) !*std.Build.Module {
        if (self.structs) |s| return s;

        if (self.debugging) std.debug.print("building structs for {}\n", .{self.collected.items.len});
        const t_compiler = self.b.addExecutable(.{
            .name = "template-compiler",
            .root_module = self.b.createModule(.{
                .root_source_file = self.depPath("src/template/struct-emit.zig"),
                .target = self.b.graph.host,
            }),
        });

        const comptime_templates = try self.buildTemplates();
        t_compiler.root_module.addImport("comptime_templates", comptime_templates);
        const tc_build_run = self.b.addRunArtifact(t_compiler);
        const tc_structs = tc_build_run.addOutputFileArg("compiled-structs.zig");
        const module = self.b.createModule(.{
            .root_source_file = tc_structs,
        });

        self.structs = module;
        return module;
    }

    pub fn collect(self: *Compiler) !void {
        var cwd = std.fs.cwd();
        for (self.dirs.items) |srcdir| {
            var idir = cwd.openDir(srcdir, .{ .iterate = true }) catch |err| {
                std.debug.print("template build error {} for srcdir {s}\n", .{ err, srcdir });
                return err;
            };
            defer idir.close();

            var itr = idir.iterate();
            while (try itr.next()) |file| {
                if (!std.mem.endsWith(u8, file.name, ".html")) continue;
                try self.collected.append(self.b.pathJoin(&[2][]const u8{ srcdir, file.name }));
            }
        }
        for (self.files.items) |file| {
            try self.collected.append(file);
        }
    }
};

fn version(b: *std.Build) []const u8 {
    if (!std.process.can_spawn) {
        std.debug.print("Can't get a version number\n", .{});
        std.process.exit(1);
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
    ) catch @panic("git is having a bad day");

    var git = std.mem.trim(u8, git_wide, " \r\n");
    if (git[0] == 'v') git = git[1..];
    //std.debug.print("version {s}\n", .{git});

    // semver is really dumb, so we need to increment this internally
    var ver = std.SemanticVersion.parse(git) catch return "v0.0.0-dev";
    if (ver.pre != null) {
        ver.minor += 1;
        ver.pre = std.fmt.allocPrint(b.allocator, "pre-{s}", .{ver.pre.?}) catch @panic("OOM");
    }

    const final = std.fmt.allocPrint(b.allocator, "{}", .{ver}) catch @panic("OOM");
    //std.debug.print("version {s}\n", .{final});
    return final;
}
