pub const Dom = @import("html/Dom.zig");
/// TODO remove this alias
pub const DOM = Dom;
pub const Extra = @import("html/extra.zig");

pub const Attribute = struct {
    key: []const u8,
    value: []const u8,

    pub fn class(val: []const u8) Attribute {
        return .{ .key = "class", .value = val };
    }

    pub fn href(val: []const u8) Attribute {
        return .{ .key = "href", .value = val };
    }

    pub fn alloc(a: Allocator, keys: []const []const u8, vals: []const []const u8) ![]Attribute {
        const all = try a.alloc(Attribute, @max(keys.len, vals.len));
        errdefer a.free(all);
        for (all, keys, vals) |*dst, k, v| {
            dst.* = .{
                .key = try a.dupe(u8, k),
                .value = try a.dupe(u8, v),
            };
        }
        return all;
    }

    pub fn create(a: Allocator, k: []const u8, v: []const u8) ![]Attribute {
        return alloc(a, &[_][]const u8{k}, &[_][]const u8{v});
    }

    pub fn format(self: Attribute, out: *Writer) !void {
        try out.print(" {s}", .{self.key});
        if (self.value.len > 0)
            try out.print("=\"{s}\"", .{self.value});
    }
};

pub const Attr = Attribute;
pub const E = Element;

pub const Element = union(enum) {
    bytes: []const u8,
    tag: Tag,

    pub const txt = Element.text;
    pub fn text(str: []const u8) Element {
        return .{ .bytes = str };
    }

    pub fn elem(str: []const u8) Element {
        return .{ .bytes = str };
    }

    pub fn format(e: Element, out: *Writer) error{WriteFailed}!void {
        return switch (e) {
            .bytes => out.writeAll(e.bytes),
            .tag => |each| each.format(out),
        };
    }

    pub fn fmtPretty(e: Element, out: *Writer) error{WriteFailed}!void {
        return switch (e) {
            .bytes => out.writeAll(e.bytes),
            .tag => |each| each.fmtPretty(out),
        };
    }
};

pub const Tag = struct {
    name: []const u8,
    attrs: []const Attribute = &.{},
    children: []const Element = &.{},
    self_close: bool = false,

    pub const Names = enum {
        a,
        div,
        span,
    };

    pub fn format(t: Tag, out: *Writer) error{WriteFailed}!void {
        if (t.name[0] == '_') unreachable;

        try out.print("<{s}", .{t.name});
        for (t.attrs) |attr|
            try out.print("{f}", .{attr});

        if (t.self_close) return try out.print(" />", .{});

        try out.print(">", .{});

        if (t.self_close)
            return try out.print(" />", .{})
        else for (t.children) |child| {
            try out.print("{f}", .{child});
        }

        try out.print("</{s}>", .{t.name});
    }

    pub fn fmtPretty(t: Tag, out: *Writer) error{WriteFailed}!void {
        if (t.name[0] == '_') unreachable;

        try out.print("<{s}", .{t.name});
        for (t.attrs) |attr|
            try out.print("{f}", .{attr});

        if (t.self_close)
            return try out.print(" />", .{});
        try out.print(">", .{});

        if (t.self_close)
            return try out.print(" />", .{})
        else for (t.children) |child| {
            try out.print("\n{f}", .{std.fmt.alt(child, .fmtPretty)});
        } else try out.writeAll("\n");

        try out.print("</{s}>", .{t.name});
    }
};

/// TODO this desperately needs to return a type instead
pub fn element(comptime name: []const u8, children: []const Element, attrs: []const Attribute) Element {
    const ChildrenType = @TypeOf(children);
    if (ChildrenType == @TypeOf(null)) return .{ .name = name, .attrs = attrs };
    const child_type_info = @typeInfo(ChildrenType);
    return switch (child_type_info) {
        .pointer => |ptr| switch (ptr.size) {
            .one => switch (@typeInfo(ptr.child)) {
                .array => |arr| switch (arr.child) {
                    u8 => .{ .name = name, .text = children, .attrs = attrs },
                    Element => .{ .tag = .{ .name = name, .children = children, .attrs = attrs } },
                    else => @compileError("Unknown type given to element"),
                },
                .pointer => @compileError("Pointer to a pointer, (perhaps &[]u8) did you mistakenly add a &?"),
                else => {
                    @compileLog(ptr);
                    @compileLog(ptr.child);
                    @compileLog(@typeInfo(ptr.child));
                    @compileLog(ChildrenType);
                },
            },
            .slice => switch (ptr.child) {
                u8 => .{ .name = name, .text = children, .attrs = attrs },
                Element => .{ .tag = .{ .name = name, .children = children, .attrs = attrs } },
                else => {
                    @compileLog(ptr);
                    @compileLog(ptr.child);
                    @compileLog(ptr.size);
                    @compileLog(ChildrenType);
                    @compileError("Invalid pointer children given");
                },
            },
            else => {
                @compileLog(ptr);
                @compileLog(ptr.size);
                @compileLog(ChildrenType);
            },
        },
        .@"struct" => @compileError("Raw structs aren't allowed, element must be a slice"),
        .array => |arr| switch (arr.child) {
            Element => .{ .tag = .{ .name = name, .children = children.ptr, .attrs = attrs } },
            else => {
                @compileLog(ChildrenType);
                @compileLog(@typeInfo(ChildrenType));
                @compileError("children must be either Element, or []Element or .{}");
            },
        },
        else => {
            @compileLog(ChildrenType);
            @compileLog(@typeInfo(ChildrenType));
            @compileError("children must be either Element, or []Element or .{}");
        },
    };
}

pub const Options = struct {
    selfclose: bool = false,
};

pub fn elementOpt(comptime name: []const u8, attrs: []const Attribute, opt: Options) Element {
    var e = element(name, &.{}, attrs);
    e.tag.self_close = opt.selfclose;
    return e;
}

pub fn text(c: []const u8) Element {
    return .text(c);
}

pub fn html(c: []const Element) Element {
    return element("html", c, &.{});
}

pub fn head(c: []const Element) Element {
    return element("head", c, &.{});
}

pub fn body(c: []const Element) Element {
    return element("body", c, &.{});
}

pub fn div(c: []const Element, a: []const Attribute) Element {
    return element("div", c, a);
}

pub fn h1(c: []const Element, a: []const Attribute) Element {
    return element("h1", c, a);
}

pub fn h2(c: []const Element, a: []const Attribute) Element {
    return element("h2", c, a);
}

pub fn h3(c: []const Element, a: []const Attribute) Element {
    return element("h3", c, a);
}

pub fn p(c: []const Element, a: []const Attribute) Element {
    return element("p", c, a);
}

pub fn br() Element {
    return elementOpt("br", &.{}, .{});
}

pub fn span(c: []const Element, a: []const Attribute) Element {
    return element("span", c, a);
}

pub fn strong(c: []const Element) Element {
    return element("strong", c, &.{});
}

pub fn anch(c: []const Element, attr: []const Attribute) Element {
    return element("a", c, attr);
}

pub fn aHrefAlloc(a: Allocator, txt: []const u8, href: []const u8) !Element {
    var attr = try a.alloc(Attribute, 1);
    attr[0] = .{ .key = "href", .value = href };
    return anch(&.{.txt(txt)}, attr);
}

pub fn form(c: []const Element, attr: []const Attribute) Element {
    return element("form", c, attr);
}

/// Written to work with DOM
pub fn formAlloc(a: Allocator, action: []const u8, o: struct { method: []const u8 = &.{} }) !Element {
    var attr = try a.alloc(Attribute, if (o.method.len == 0) 1 else 2);
    attr[0] = .{ .key = "action", .value = action };
    if (o.method.len != 0) attr[1] = .{
        .key = "method",
        .value = o.method,
    };
    return element("form", &.{}, attr);
}

pub fn textarea(c: []const Element, attr: []const Attribute) Element {
    return element("textarea", c, attr);
}

pub fn textareaAlloc(
    a: Allocator,
    name: []const u8,
    o: struct { placeholder: []const u8 = &.{} },
) !Element {
    var attr = try a.alloc(Attribute, if (o.placeholder.len == 0) 1 else 2);
    attr[0] = .{
        .key = "name",
        .value = name,
    };
    if (o.placeholder.len != 0)
        attr[1] = .{
            .key = "placeholder",
            .value = o.placeholder,
        };

    return element("textarea", &.{}, attr);
}

pub fn input(attr: []const Attribute) Element {
    return elementOpt("input", attr, .{});
}

pub fn inputAlloc(
    a: Allocator,
    name: []const u8,
    o: struct { placeholder: []const u8 = &.{} },
) !Element {
    var attr = try a.alloc(Attribute, if (o.placeholder.len == 0) 1 else 2);
    attr[0] = .{ .key = "name", .value = name };

    if (o.placeholder.len > 0) attr[1] = .{
        .key = "placeholder",
        .value = o.placeholder,
    };

    return elementOpt("input", attr, .{});
}

pub fn btn(c: []const Element, attr: []const Attribute) Element {
    return element("button", c, attr);
}

pub fn btnDupe(txt: []const u8, name: []const u8) Element {
    return element("button", &.{.txt(txt)}, &.{.{ .key = "name", .value = name }});
}

pub fn linkBtnAlloc(a: Allocator, txt: []const u8, href: []const u8) !Element {
    const attr = [2]Attr{
        .class("btn"),
        .href(href),
    };
    return element(
        "a",
        try a.dupe(Element, &.{.txt(txt)}),
        try a.dupe(Attr, &attr),
    );
}

pub fn li(c: []const Element, attr: []const Attribute) Element {
    return element("li", c, attr);
}

test "html" {
    var a = std.testing.allocator;

    const str = try std.fmt.allocPrint(a, "{f}", .{html(&.{})});
    defer a.free(str);
    try std.testing.expectEqualStrings("<html></html>", str);

    const str2 = try std.fmt.allocPrint(a, "{f}", .{std.fmt.alt(html(&[_]E{body(&.{})}), .fmtPretty)});
    defer a.free(str2);
    try std.testing.expectEqualStrings("<html>\n<body>\n</body>\n</html>", str2);
}

test "nested" {
    var a = std.testing.allocator;
    const str = try std.fmt.allocPrint(a, "{f}", .{
        std.fmt.alt(html(&[_]E{
            head(&.{}),
            body(&.{
                div(&.{p(&.{}, &.{})}, &.{}),
            }),
        }), .fmtPretty),
    });
    defer a.free(str);

    const example =
        \\<html>
        \\<head>
        \\</head>
        \\<body>
        \\<div>
        \\<p>
        \\</p>
        \\</div>
        \\</body>
        \\</html>
    ;
    try std.testing.expectEqualStrings(example, str);
}

test "text" {
    var a = std.testing.allocator;

    const str = try std.fmt.allocPrint(a, "{f}", .{text("this is text")});
    defer a.free(str);
    try std.testing.expectEqualStrings("this is text", str);

    const pt = try std.fmt.allocPrint(a, "{f}", .{p(&.{.txt("this is text")}, &.{})});
    defer a.free(pt);
    try std.testing.expectEqualStrings("<p>this is text</p>", pt);

    const p_txt = try std.fmt.allocPrint(a, "{f}", .{p(&[_]E{.txt("this is text")}, &.{})});
    defer a.free(p_txt);
    try std.testing.expectEqualStrings("<p>this is text</p>", p_txt);
}

test "attrs" {
    var a = std.testing.allocator;
    const str = try std.fmt.allocPrint(a, "{f}", .{
        std.fmt.alt(html(&[_]E{
            head(&.{}),
            body(
                &.{div(
                    &.{p(&.{}, &.{})},
                    &.{.{ .key = "class", .value = "something" }},
                )},
            ),
        }), .fmtPretty),
    });
    defer a.free(str);

    const example =
        \\<html>
        \\<head>
        \\</head>
        \\<body>
        \\<div class="something">
        \\<p>
        \\</p>
        \\</div>
        \\</body>
        \\</html>
    ;
    try std.testing.expectEqualStrings(example, str);
}

test {
    _ = std.testing.refAllDecls(@This());
    _ = &DOM;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
