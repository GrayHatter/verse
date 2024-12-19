const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const endsWith = std.mem.endsWith;
const indexOfScalar = std.mem.indexOfScalar;
const allocPrint = std.fmt.allocPrint;
const log = std.log.scoped(.Verse);

const build_mode = @import("builtin").mode;
const compiled = @import("comptime_templates");
pub const Structs = @import("comptime_structs");

pub const Directive = @import("template/directive.zig");

pub const Pages = @import("template/page.zig");
pub const Page = Pages.Page;
pub const PageRuntime = Pages.PageRuntime;

const MAX_BYTES = 2 <<| 15;

pub const Template = struct {
    // path: []const u8,
    name: []const u8 = "undefined",
    blob: []const u8,
    parent: ?*const Template = null,

    pub fn pageOf(self: Template, comptime Kind: type, data: Kind) PageRuntime(Kind) {
        return PageRuntime(Kind).init(.{ .name = self.name, .blob = self.blob }, data);
    }

    pub fn format(_: Template, comptime _: []const u8, _: std.fmt.FormatOptions, _: anytype) !void {
        comptime unreachable;
    }
};

fn tailPath(path: []const u8) []const u8 {
    if (indexOfScalar(u8, path, '/')) |i| {
        return path[i + 1 ..];
    }
    return path[0..0];
}

pub const builtin: []const Template = constructTemplates();

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

pub var dynamic: []const Template = undefined;

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

pub fn raze(a: Allocator) void {
    for (dynamic) |t| {
        // leaks?
        a.free(t.name);
        a.free(t.blob);
    }
    a.free(dynamic);
}

pub fn findWhenever(name: []const u8) Template {
    for (dynamic) |d| {
        if (std.mem.eql(u8, d.name, name)) {
            return d;
        }
    }
    unreachable;
}

pub fn load(a: Allocator, comptime name: []const u8) Template {
    var t = findTemplate(name);
    t.init(a);
    return t;
}

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

pub fn PageData(comptime name: []const u8) type {
    //const n = std.fmt.comptimePrint("search for {s}", .{"templates/" ++ name});
    //const data = @embedFile(name);
    //@compileLog(n);
    //@compileLog(data.len);
    const template = findTemplate(name);
    const page_data = comptime findPageType(name);
    return Page(template, page_data);
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

pub fn findPageType(comptime name: []const u8) type {
    var local: [0xFFFF]u8 = undefined;
    const llen = comptime makeStructName(name, &local);
    return @field(Structs, local[0..llen]);
}

test "load templates" {
    const a = std.testing.allocator;

    initDynamic(a, "src/fallback_html/");
    defer raze(a);

    //try std.testing.expectEqual(3, builtin.len);
    for (builtin) |bi| {
        if (std.mem.eql(u8, bi.name, "fallback_html/index.html")) {
            try std.testing.expectEqualStrings("fallback_html/index.html", bi.name);
            try std.testing.expectEqualStrings("<!DOCTYPE html>", bi.blob[0..15]);
            break;
        }
    } else {
        return error.TemplateNotFound;
    }
}

test findTemplate {
    const tmpl = findTemplate("fallback_html/index.html");
    try std.testing.expectEqualStrings("fallback_html/index.html", tmpl.name);
}

test "directive something" {
    const a = std.testing.allocator;
    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<Something>",
    };

    const Basic = struct {
        something: []const u8,
    };

    const ctx = Basic{
        .something = @as([]const u8, "Some Text Here"),
    };
    const pg = Page(t, @TypeOf(ctx)).init(ctx);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("Some Text Here", p);

    const t2 = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<Something />",
    };

    const ctx2 = Basic{
        .something = @as([]const u8, "Some Text Here"),
    };
    const pg2 = Page(t2, @TypeOf(ctx2)).init(ctx2);
    const p2 = try allocPrint(a, "{}", .{pg2});
    defer a.free(p2);
    try std.testing.expectEqualStrings("Some Text Here", p2);
}

test "directive typed something" {
    var a = std.testing.allocator;

    const Something = struct {
        something: []const u8,
    };

    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<Something>",
    };

    const page = Page(t, Something);

    const pg = page.init(.{
        .something = "Some Text Here",
    });

    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("Some Text Here", p);
}

test "directive typed something /" {
    var a = std.testing.allocator;

    const Something = struct {
        something: []const u8,
    };

    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<Something />",
    };

    const page = Page(t, Something);

    const p = page.init(.{
        .something = "Some Text Here",
    });

    const pg = try allocPrint(a, "{}", .{p});
    defer a.free(pg);
    try std.testing.expectEqualStrings("Some Text Here", pg);
}

test "directive nothing" {
    var a = std.testing.allocator;
    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<!-- nothing -->",
    };

    const ctx = .{};
    const page = Page(t, @TypeOf(ctx));

    const pg = page.init(ctx);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("<!-- nothing -->", p);
}

test "directive nothing new" {
    //const a = std.testing.allocator;
    //const t = Template{
    //    //.path = "/dev/null",
    //    .name = "test",
    //    .blob = "<Nothing>",
    //};

    //const ctx = .{};

    //// TODO is this still the expected behavior
    ////const p = Page(t, @TypeOf(ctx)).init(.{});
    ////try std.testing.expectError(error.VariableMissing, p);

    //const pg = Page(t, @TypeOf(ctx)).init(.{});
    //const p = try allocPrint(a, "{}", .{pg});
    //defer a.free(p);
    //try std.testing.expectEqualStrings("<Nothing>", p);
}

test "directive ORELSE" {
    var a = std.testing.allocator;
    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<This default='string until end'>",
    };

    const Basic = struct {
        this: ?[]const u8,
    };

    const ctx = Basic{
        .this = null,
    };

    const pg = Page(t, @TypeOf(ctx)).init(ctx);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("string until end", p);
}

test "directive ORNULL" {
    var a = std.testing.allocator;
    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        // Invalid because 'string until end' is known to be unreachable
        .blob = "<This ornull string until end>",
    };

    const Basic = struct {
        this: ?[]const u8,
    };

    const ctx = Basic{
        .this = null,
    };

    const pg = Page(t, @TypeOf(ctx)).init(ctx);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("", p);

    const t2 = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<This ornull>",
    };

    const nullpage = Page(t2, @TypeOf(ctx)).init(ctx);
    const p2 = try allocPrint(a, "{}", .{nullpage});
    defer a.free(p2);
    try std.testing.expectEqualStrings("", p2);
}

test "directive For 0..n" {}

test "directive For" {
    var a = std.testing.allocator;

    const blob =
        \\<div><For Loop><span><Name></span></For></div>
    ;

    const expected: []const u8 =
        \\<div><span>not that</span></div>
    ;

    const dbl_expected: []const u8 =
        \\<div><span>first</span><span>second</span></div>
    ;

    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = blob,
    };

    var ctx: struct {
        loop: []const struct {
            name: []const u8,
        },
    } = .{
        .loop = &.{
            .{ .name = "not that" },
        },
    };

    const pg = Page(t, @TypeOf(ctx)).init(ctx);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);

    ctx = .{
        .loop = &.{
            .{ .name = "first" },
            .{ .name = "second" },
        },
    };

    const dbl_page = Page(t, @TypeOf(ctx)).init(ctx);
    const pg2 = try allocPrint(a, "{}", .{dbl_page});
    defer a.free(pg2);
    try std.testing.expectEqualStrings(dbl_expected, pg2);
}

test "directive For & For" {
    var a = std.testing.allocator;

    const blob =
        \\<div>
        \\  <For Loop>
        \\    <span><Name></span>
        \\    <For Numbers>
        \\      <Number>
        \\    </For>
        \\  </For>
        \\</div>
    ;

    const expected: []const u8 =
        \\<div>
        \\  <span>Alice</span>
        \\    A0
        \\    A1
        \\    A2
    ++ "\n    \n" ++
        \\  <span>Bob</span>
        \\    B0
        \\    B1
        \\    B2
    ++ "\n    \n  \n" ++
        \\</div>
    ;

    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = blob,
    };

    const ctx: struct {
        loop: []const struct {
            name: []const u8,
            numbers: []const struct {
                number: []const u8,
            },
        },
    } = .{
        .loop = &.{
            .{
                .name = "Alice",
                .numbers = &.{
                    .{ .number = "A0" },
                    .{ .number = "A1" },
                    .{ .number = "A2" },
                },
            },
            .{
                .name = "Bob",
                .numbers = &.{
                    .{ .number = "B0" },
                    .{ .number = "B1" },
                    .{ .number = "B2" },
                },
            },
        },
    };

    const pg = Page(t, @TypeOf(ctx)).init(ctx);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive for then for" {
    var a = std.testing.allocator;

    const blob =
        \\<div>
        \\  <For Loop>
        \\    <span><Name></span>
        \\  </For>
        \\  <For Numbers>
        \\    <Number>
        \\  </For>
        \\</div>
    ;

    const expected: []const u8 =
        \\<div>
        \\  <span>Alice</span>
        \\  <span>Bob</span>
    ++ "\n  \n" ++
        \\  A0
        \\  A1
        \\  A2
    ++ "\n  \n" ++
        \\</div>
    ;

    const FTF = struct {
        const Loop = struct {
            name: []const u8,
        };
        const Numbers = struct {
            number: []const u8,
        };

        loop: []const Loop,
        numbers: []const Numbers,
    };

    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = blob,
    };
    const page = Page(t, FTF);

    const loop = [2]FTF.Loop{
        .{ .name = "Alice" },
        .{ .name = "Bob" },
    };
    const numbers = [3]FTF.Numbers{
        .{ .number = "A0" },
        .{ .number = "A1" },
        .{ .number = "A2" },
    };
    const pg = page.init(.{
        .loop = loop[0..],
        .numbers = numbers[0..],
    });
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive With" {
    const a = std.testing.allocator;

    const blob =
        \\<div>
        \\  <With Thing>
        \\    <span><Thing></span>
        \\  </With>
        \\</div>
    ;

    const expected_empty: []const u8 =
        \\<div>
    ++ "\n  \n" ++
        \\</div>
    ;
    // trailing spaces expected and required
    try std.testing.expect(std.mem.count(u8, expected_empty, "  \n") == 1);
    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = blob,
    };

    var ctx: struct {
        thing: ?struct {
            thing: []const u8,
        },
    } = .{
        .thing = null,
    };

    const page = Page(t, @TypeOf(ctx));
    const pg = page.init(ctx);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected_empty, p);

    ctx = .{
        .thing = .{ .thing = "THING" },
    };

    const expected_thing: []const u8 =
        \\<div>
        \\  <span>THING</span>
        // TODO fix this whitespace alignment and delete the extra newline
    ++ "\n  \n" ++
        \\</div>
    ;

    const pg2 = page.init(ctx);
    const p2 = try allocPrint(a, "{}", .{pg2});
    defer a.free(p2);
    try std.testing.expectEqualStrings(expected_thing, p2);
}

test "directive Split" {
    var a = std.testing.allocator;

    const blob =
        \\<div>
        \\  <Split Slice />
        \\</div>
        \\
    ;

    const expected: []const u8 =
        \\<div>
        \\  Alice
        \\Bob
        \\Charlie
        \\Eve
    ++ "\n\n" ++
        \\</div>
        \\
    ;

    const SplitS = struct {
        slice: []const []const u8,
    };

    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = blob,
    };
    const page = Page(t, SplitS);

    const slice = SplitS{
        .slice = &[_][]const u8{
            "Alice",
            "Bob",
            "Charlie",
            "Eve",
        },
    };
    const pg = page.init(slice);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive Build" {
    var a = std.testing.allocator;

    const blob =
        \\<Build Name _test_template.html />
    ;

    const expected: []const u8 =
        \\<div>
        \\AliceBobCharlieEve
        \\</div>
    ;

    const FE = struct {
        const This = struct {
            this: []const u8,
        };
        name: struct {
            slice: []const This,
        },
    };

    const t = Template{
        .name = "test",
        .blob = blob,
    };

    //dynamic = &[1]Template{
    //    .{
    //        .name = "_template.html",
    //        .blob = "<div>\n<For Slice><This></For>\n</div>",
    //    },
    //};
    if (true) return error.SkipZigTest;
    const page = Page(t, FE);

    const slice = FE{
        .name = .{
            .slice = &[4]FE.This{
                .{ .this = "Alice" },
                .{ .this = "Bob" },
                .{ .this = "Charlie" },
                .{ .this = "Eve" },
            },
        },
    };
    const pg = page.init(slice);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive typed usize" {
    var a = std.testing.allocator;
    const blob = "<Number type=\"usize\" />";
    const expected: []const u8 = "420";

    const FE = struct { number: usize };

    const t = Template{ .name = "test", .blob = blob };
    const page = Page(t, FE);

    const slice = FE{ .number = 420 };
    const pg = page.init(slice);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive typed ?usize" {
    var a = std.testing.allocator;
    const blob = "<Number type=\"?usize\" />";
    const expected: []const u8 = "420";

    const MaybeUsize = struct { number: ?usize };

    const t = Template{ .name = "test", .blob = blob };
    const page = Page(t, MaybeUsize);

    const slice = MaybeUsize{ .number = 420 };
    const pg = page.init(slice);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive typed ?usize null" {
    var a = std.testing.allocator;
    const blob = "<Number type=\"?usize\" />";
    const expected: []const u8 = "";

    const FE = struct { number: ?usize };

    const Temp = Template{ .name = "test", .blob = blob };
    const page = Page(Temp, FE);

    const slice = FE{ .number = null };
    const pg = page.init(slice);
    const p = try allocPrint(a, "{}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive typed isize" {
    var a = std.testing.allocator;
    const blob = "<Number type=\"isize\" />";
    const expected: []const u8 = "-420";

    const PData = struct {
        number: isize,
    };
    const Temp = Template{ .name = "test", .blob = blob };
    const PType = Page(Temp, PData);

    const data = PData{ .number = -420 };
    const print = try allocPrint(a, "{}", .{PType.init(data)});
    defer a.free(print);
    try std.testing.expectEqualStrings(expected, print);
}

test "grouped offsets" {
    const blob =
        \\<html>
        \\  <div>
        \\    <p>
        \\      <span>text</span>
        \\    </p>
        \\  </div>
        \\</html>
    ;
    const Temp = Template{ .name = "test", .blob = blob };
    const PData = struct {};
    const PType = Page(Temp, PData);
    try std.testing.expectEqual(1, PType.DataOffsets.len);
    var a = std.testing.allocator;
    const print = try allocPrint(a, "{}", .{PType.init(PData{})});
    defer a.free(print);
    const expected = blob;
    try std.testing.expectEqualStrings(expected, print);
}

test "comment tags" {
    var a = std.testing.allocator;

    const blob =
        \\<!-- <ValidButInComment /> -->
    ;

    const PData = struct {};
    const t = Template{ .name = "test", .blob = blob };
    const PType = Page(t, PData);

    const data = PData{};
    const expected = blob;

    const page = try allocPrint(a, "{}", .{PType.init(data)});
    defer a.free(page);

    try std.testing.expectEqualStrings(expected, page);
}
