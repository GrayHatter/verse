pub const Structs = @import("comptime_structs");
pub const Directive = @import("template/directive.zig");
pub const Template = @import("template/Template.zig");

pub const html = @import("template/html.zig");

const pages = @import("template/page.zig");
pub const Page = pages.Page;

const MAX_BYTES = 2 <<| 15;

const template_data = @import("template/builtins.zig");
pub const builtin = template_data.builtin;
pub var dynamic = &template_data.dynamic;

const makeStructName = template_data.makeStructName;
const makeFieldName = template_data.makeFieldName;
pub const findTemplate = template_data.findTemplate;

pub fn raze(a: Allocator) void {
    for (dynamic.*) |t| {
        // leaks?
        a.free(t.name);
        a.free(t.blob);
    }
    a.free(dynamic.*);
}

pub fn findWhenever(name: []const u8) Template {
    for (dynamic.*) |d| {
        if (eql(u8, d.name, name)) {
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

pub fn PageData(comptime name: []const u8) type {
    //const n = std.fmt.comptimePrint("search for {s}", .{"templates/" ++ name});
    //const data = @embedFile(name);
    //@compileLog(n);
    //@compileLog(data.len);
    const template = findTemplate(name);
    const page_data = comptime findPageType(name);
    return Page(template, page_data);
}

pub fn findPageType(comptime name: []const u8) type {
    var local: [0xFF]u8 = undefined;
    const llen = comptime makeStructName(name, &local);
    return @field(Structs, local[0..llen]);
}

// remove if https://github.com/ziglang/zig/pull/22366 is merged
fn testPrint(comptime fmt: []const u8, args: anytype) void {
    if (@inComptime()) {
        @compileError(std.fmt.comptimePrint(fmt, args));
    } else if (std.testing.backend_can_print) {
        std.debug.print(fmt, args);
    }
}

fn comptimeCountNames(text: []const u8) usize {
    var last: usize = 0;
    var count: usize = 0;
    while (std.mem.indexOfScalarPos(u8, text, last, '<')) |idx| {
        last = idx + 1;
        if (last >= text.len) break;
        if (std.ascii.isUpper(text[last])) count += 1;
        if (Directive.init(text[last - 1 ..])) |drct| switch (drct.verb) {
            .variable => {},
            else => last += drct.tag_block.len,
        };
    }
    return count;
}

fn comptimeFields(text: []const u8) [comptimeCountNames(text)]std.builtin.Type.StructField {
    var fields: [comptimeCountNames(text)]std.builtin.Type.StructField = undefined;
    var last: usize = 0;
    for (&fields) |*field| {
        while (std.mem.indexOfScalarPos(u8, text, last, '<')) |idx| {
            last = idx + 1;
            if (last >= text.len) unreachable;
            if (Directive.init(text[last - 1 ..])) |drct| switch (drct.verb) {
                .variable => {
                    const ws = std.mem.indexOfAnyPos(u8, text, last, " />") orelse unreachable;
                    const name = text[last..ws];
                    var lower: [name.len + 8:0]u8 = @splat(0);
                    const llen = makeFieldName(name, &lower);
                    lower[llen] = 0;
                    const lname: [:0]const u8 = @as([:0]u8, lower[0..llen :0]);

                    field.* = .{
                        .name = lname,
                        .type = []const u8,
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = @alignOf([]const u8),
                    };
                    break;
                },
                .foreach => {
                    var lower: [drct.noun.len + 8:0]u8 = @splat(0);
                    const llen = makeFieldName(drct.noun, &lower);
                    lower[llen] = 0;
                    const lname: [:0]const u8 = @as([:0]u8, lower[0..llen :0]);

                    const body_type = comptimeStruct(drct.tag_block_body.?);

                    field.* = .{
                        .name = lname,
                        .type = switch (drct.otherwise) {
                            .exact => |ex| [ex]body_type,
                            else => []const body_type,
                        },
                        .default_value_ptr = null,
                        .is_comptime = false,
                        .alignment = @alignOf([]const u8),
                    };
                    break;
                },
                else => unreachable,
            };
        }
    }
    return fields;
}

fn comptimeStruct(text: []const u8) type {
    @setEvalBranchQuota(10000);
    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &comptimeFields(text),
        .decls = &.{},
        .is_tuple = false,
    } });
}

test findPageType {
    // Copied from the example template html to create this test, the example
    // html is the cannon definition.
    const Type = findPageType("ExampleHtml");

    const expected: Type = .{
        .simple_variable = "",
        .required_and_provided = "",
        .null_variable = null,
        .default_provided = "",
        .default_missing = "",
        .positive_number = 0,
        .optional_with = null,
        .namespaced_with = .{ .simple_variable = "" },
        .basic_loop = undefined, // TODO FIXME
        .slices = &[_][]const u8{ "", "" },
        .include_vars = .{
            .template_name = "",
            .simple_variable = "",
            .nullable = null,
        },
        .empty_vars = .{},
    };
    // Ensure it builds, then trust the compiler
    try std.testing.expect(@sizeOf(@TypeOf(expected)) > 0);
}

test "load templates" {
    //try std.testing.expectEqual(3, builtin.len);
    for (builtin) |bi| {
        if (std.mem.eql(u8, bi.name, "builtin-html/index.html")) {
            try std.testing.expectEqualStrings("builtin-html/index.html", bi.name);
            try std.testing.expectEqualStrings("<!DOCTYPE html>", bi.blob[0..15]);
            break;
        }
    } else {
        return error.TemplateNotFound;
    }
}

test findTemplate {
    const tmpl = findTemplate("builtin-html/index.html");
    try std.testing.expectEqualStrings("builtin-html/index.html", tmpl.name);
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p2 = try allocPrint(a, "{f}", .{pg2});
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

    const p = try allocPrint(a, "{f}", .{pg});
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

    const pg = try allocPrint(a, "{f}", .{p});
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
    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("<!-- nothing -->", p);
}

test "directive nothing new" {
    // TODO fix test
    if (true) return error.SkipZigTest;

    const a = std.testing.allocator;
    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<Nothing>",
    };

    const ctx = .{};

    // TODO is this still the expected behavior
    //const p = Page(t, @TypeOf(ctx)).init(.{});
    //try std.testing.expectError(error.VariableMissing, p);

    const pg = Page(t, @TypeOf(ctx)).init(.{});
    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("<Nothing>", p);
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings("", p);

    const t2 = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = "<This ornull>",
    };

    const nullpage = Page(t2, @TypeOf(ctx)).init(ctx);
    const p2 = try allocPrint(a, "{f}", .{nullpage});
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
    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);

    ctx = .{
        .loop = &.{
            .{ .name = "first" },
            .{ .name = "second" },
        },
    };

    const dbl_page = Page(t, @TypeOf(ctx)).init(ctx);
    const pg2 = try allocPrint(a, "{f}", .{dbl_page});
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "directive for with for for" {
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    const a = arena.allocator();
    defer arena.deinit();

    const blob =
        \\<div>
        \\  <For Loop>
        \\    <With Maybe>
        \\      <For Indexes>
        \\        <span><Idx></span>
        \\       </For>
        \\    </With>
        \\    <With MaybeNames>
        \\      <For First>
        \\        <span><Name></span>
        \\       </For>
        \\      <For Second>
        \\        <span><LastName></span>
        \\       </For>
        \\    </With>
        \\  </For>
        \\</div>
    ;

    {
        //const emit = @import("template/struct-emit.zig");
        //const this = try emit.AbstTree.init(a, "Testing", null);
        //const gop = try emit.root_tree.getOrPut(a, this.name);
        //if (!gop.found_existing) {
        //    gop.value_ptr.* = this;
        //}
        //try emit.emitSourceVars(a, blob, this);
        //std.debug.print("this {}", .{this});
    }

    const FTF = struct {
        const Loop = struct {
            maybe: ?Maybe,
            maybe_names: ?MaybeNames,
        };
        const Maybe = struct {
            indexes: []const Indexes,
        };
        const MaybeNames = struct {
            first: []const First,
            second: []const Second,
        };
        const Indexes = struct {
            idx: []const u8,
        };
        const First = struct {
            name: []const u8,
        };
        const Second = struct {
            last_name: []const u8,
        };

        loop: []const Loop,
    };

    const t = Template{
        .name = "test",
        .blob = blob,
    };
    const page = Page(t, FTF);

    var page_data: FTF = .{
        .loop = &[2]FTF.Loop{
            .{ .maybe = null, .maybe_names = null },
            .{ .maybe = null, .maybe_names = null },
        },
    };
    var page_temp = page.init(page_data);
    var rendered = try allocPrint(a, "{f}", .{page_temp});
    const expected_empty: []const u8 = "<div>\n  \n    \n  \n    \n  \n</div>";
    try std.testing.expectEqualStrings(expected_empty, rendered);

    page_data = .{
        .loop = &[2]FTF.Loop{ .{
            .maybe = .{ .indexes = &[4]FTF.Indexes{
                .{ .idx = "0" },
                .{ .idx = "1" },
                .{ .idx = "2" },
                .{ .idx = "3" },
            } },
            .maybe_names = null,
        }, .{ .maybe = null, .maybe_names = null } },
    };

    page_temp = page.init(page_data);
    rendered = try allocPrint(a, "{f}", .{page_temp});
    const expected_first: []const u8 =
        \\<div>
        \\  <span>0</span>
        \\       <span>1</span>
        \\       <span>2</span>
        \\       <span>3</span>
        \\
    ++ "       \n" //
    ++ "    \n" //
    ++ "    \n" //
    ++ "  \n" //
    ++ "    \n" //
    ++ "  \n" //
    ++ "</div>";
    try std.testing.expectEqualStrings(expected_first, rendered);

    page_data = .{
        .loop = &[2]FTF.Loop{
            .{ .maybe = null, .maybe_names = null }, .{
                .maybe = null,
                .maybe_names = .{
                    .first = &[3]FTF.First{
                        .{ .name = "First" },
                        .{ .name = "Third" },
                        .{ .name = "Fifth" },
                    },
                    .second = &[3]FTF.Second{
                        .{ .last_name = "Second" },
                        .{ .last_name = "Forth" },
                        .{ .last_name = "Sixth" },
                    },
                },
            },
        },
    };

    page_temp = page.init(page_data);
    rendered = try allocPrint(a, "{f}", .{page_temp});
    const expected_second: []const u8 =
        \\<div>
        \\
    ++ "  \n" //
    ++ "    \n" //
    ++ "  \n" ++
        \\    <span>First</span>
        \\       <span>Third</span>
        \\       <span>Fifth</span>
        \\
    ++ "       \n" ++
        \\      <span>Second</span>
        \\       <span>Forth</span>
        \\       <span>Sixth</span>
        \\
    ++ "       \n" //
    ++ "    \n" //
    ++ "  \n" ++
        \\</div>
    ;

    try std.testing.expectEqualStrings(expected_second, rendered);
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p2 = try allocPrint(a, "{f}", .{pg2});
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
            "Alice\n",
            "Bob\n",
            "Charlie\n",
            "Eve\n",
        },
    };
    const pg = page.init(slice);
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const p = try allocPrint(a, "{f}", .{pg});
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
    const print = try allocPrint(a, "{f}", .{PType.init(data)});
    defer a.free(print);
    try std.testing.expectEqualStrings(expected, print);
}

test "directive typed humanize" {
    // Disabled while I give the implementation more thought
    if (true) return error.SkipZigTest;
    var a = std.testing.allocator;
    const blob =
        \\<Date type="humanize" />
    ;
    const expected: []const u8 = "<span>1 hour ago</span>";

    const FE = struct { date: i64 };

    const t = Template{ .name = "test", .blob = blob };
    const page = Page(t, FE);

    const slice = FE{ .date = std.time.timestamp() - 3600 };
    const pg = page.init(slice);
    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "EnumLiteral" {
    var a = std.testing.allocator;
    const blob =
        \\<Directive name="EnumLiteral" type="enum" text="active" />
        \\<li><a href="" class="<EnumLiteral enum="settings" />">Settings</a></li>
        \\<li><a href="" class="<EnumLiteral enum="other"  />">Other</a></li>
        \\<li><a href="" class="<EnumLiteral enum="default"  />">Default</a></li>
        \\
    ;
    const expected: []const u8 =
        \\<li><a href="" class="active">Settings</a></li>
        \\<li><a href="" class="">Other</a></li>
        \\<li><a href="" class="">Default</a></li>
        \\
    ;

    const PData = struct {
        enum_literal: enum(u16) {
            settings,
            other,
            default,

            pub const VALUE = "active";
        },
    };
    const Temp = Template{ .name = "test", .blob = blob };
    const PType = Page(Temp, PData);

    const data = PData{ .enum_literal = .settings };
    const print = try allocPrint(a, "{f}", .{PType.init(data)});
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
    const print = try allocPrint(a, "{f}", .{PType.init(PData{})});
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

    const page = try allocPrint(a, "{f}", .{PType.init(data)});
    defer a.free(page);

    try std.testing.expectEqualStrings(expected, page);
}

test "For exact" {
    var a = std.testing.allocator;

    // 4 chosen by a fair dice roll!
    const blob =
        \\<For Loop exact="4">
        \\    <span><Name></span>
        \\</For>
    ;

    const expected: []const u8 =
        \\<span>first</span>
        \\<span>second</span>
        \\<span>third</span>
        \\<span>forth</span>
        \\
    ;

    const t = Template{
        //.path = "/dev/null",
        .name = "test",
        .blob = blob,
    };

    const PgType = comptimeStruct(blob);

    const ctx = PgType{
        .loop = .{
            .{ .name = "first" },
            .{ .name = "second" },
            .{ .name = "third" },
            .{ .name = "forth" },
        },
    };
    const pg = Page(t, PgType).init(ctx);

    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);
    try std.testing.expectEqualStrings(expected, p);
}

test "For use=" {
    var a = std.testing.allocator;
    const FE = struct {
        const This = struct {
            name: []const u8,
        };
        loop: []const This,
    };

    const t = Template{
        .name = "test",
        .blob =
        \\<div>
        \\<For Loop use="_For_Use_template.html"></For>
        \\</div>
        ,
    };

    const slice = FE{
        .loop = &[4]FE.This{
            .{ .name = "Alice" },
            .{ .name = "Bob" },
            .{ .name = "Charlie" },
            .{ .name = "Eve" },
        },
    };

    const page = Page(t, FE);
    const pg = page.init(slice);
    const p = try allocPrint(a, "{f}", .{pg});
    defer a.free(p);

    const expected: []const u8 =
        \\<div>
        \\Alice
        \\
        \\Bob
        \\
        \\Charlie
        \\
        \\Eve
        \\
        \\
        \\</div>
    ;

    try std.testing.expectEqualStrings(expected, p);
}

test {
    _ = std.testing.refAllDecls(@This());
    _ = &html;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const eql = std.mem.eql;
const endsWith = std.mem.endsWith;
const indexOfScalar = std.mem.indexOfScalar;
const allocPrint = std.fmt.allocPrint;
const log = std.log.scoped(.Verse);

const build_mode = @import("builtin").mode;
