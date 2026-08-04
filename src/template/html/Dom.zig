alloc: Allocator,
elems: ArrayList(Elem),
parent: ?*Dom = null,
child: ?*Dom = null,
opened: ?Elem = null,

const Dom = @This();

pub fn create(a: Allocator) *Dom {
    const d = a.create(Dom) catch unreachable;
    d.* = Dom{ .alloc = a, .elems = .empty };
    return d;
}

pub fn open(d: *Dom, elem: HTML.E) *Dom {
    if (d.child) |_| @panic("DOM Already Open");
    d.child = create(d.alloc);
    d.child.?.parent = d;
    d.child.?.opened = elem;
    return d.child.?;
}

pub fn pushSlice(d: *Dom, elems: []const HTML.E) void {
    for (elems) |elem| d.push(elem);
}

pub fn push(d: *Dom, elem: HTML.E) void {
    d.elems.append(d.alloc, elem) catch unreachable;
}

pub fn dupe(d: *Dom, elem: HTML.E) void {
    d.elems.append(d.alloc, switch (elem) {
        .tag => HTML.E{ .tag = .{
            .name = elem.tag.name,
            .children = d.alloc.dupe(HTML.E, elem.tag.children) catch &.{},
            .attrs = d.alloc.dupe(HTML.Attribute, elem.tag.attrs) catch &.{},
        } },
        .bytes => HTML.E{ .bytes = d.alloc.dupe(u8, elem.bytes) catch &.{} },
    }) catch unreachable;
}

pub fn close(d: *Dom) *Dom {
    if (d.parent) |p| {
        d.opened.?.tag.children = d.elems.toOwnedSlice(d.alloc) catch unreachable;
        p.push(d.opened.?);
        p.child = null;
        defer d.alloc.destroy(d);
        return p;
    } else @panic("Dom ISN'T OPEN");
    unreachable;
}

pub fn done(d: *Dom) []HTML.E {
    if (d.child) |_| @panic("INVALID STATE DOM STILL HAS OPEN CHILDREN");
    defer d.alloc.destroy(d);
    return d.elems.toOwnedSlice(d.alloc) catch unreachable;
}

fn freeChildren(a: Allocator, elems: []const Elem) void {
    for (elems) |elem| switch (elem) {
        .tag => |tag| {
            freeChildren(a, tag.children);
            a.free(tag.children);
        },
        .bytes => |b| a.free(b),
    };
}

pub fn raze(d: *Dom) void {
    freeChildren(d.alloc, d.elems.items);
    d.elems.deinit(d.alloc);
    d.alloc.destroy(d);
}

pub fn fmtFull(d: Dom, w: *Writer) Writer.Error!void {
    if (d.child) |_| @panic("INVALID STATE DOM STILL HAS OPEN CHILDREN");
    for (d.elems.items) |e| {
        w.print("{f}", .{std.fmt.alt(e, .fmtPretty)}) catch unreachable;
    }
}

pub fn format(d: Dom, w: *Writer) Writer.Error!void {
    for (d.elems.items) |e| {
        w.print("{f}", .{e}) catch unreachable;
    }
}

pub fn render(d: *Dom, a: Allocator, comptime style: enum { full, compact }) ![]u8 {
    if (d.child) |_| @panic("INVALID STATE DOM STILL HAS OPEN CHILDREN");
    var html: Writer.Allocating = .init(a);
    if (comptime style == .full) {
        try d.fmtFull(&html.writer);
    } else {
        try d.format(&html.writer);
    }
    return try html.toOwnedSlice();
}

test render {
    const a = std.testing.allocator;
    var dom: *Dom = .create(a);
    dom = dom.open(HTML.form(&.{}, &[_]HTML.Attr{
        .{ .key = "method", .value = "POST" },
        .{ .key = "action", .value = "/endpoint" },
    }));
    dom = dom.open(
        HTML.element("button", &.{}, &.{.{ .key = "name", .value = "new" }}),
    );
    dom.dupe(HTML.text("create new"));
    dom = dom.close();
    dom = dom.close();

    const compact = try dom.render(a, .compact);
    dom.raze();
    defer a.free(compact);
    const expected_compact =
        \\<form method="POST" action="/endpoint"><button name="new">create new</button></form>
    ;
    try std.testing.expectEqualStrings(expected_compact, compact);

    dom = .create(a);
    dom = dom.open(HTML.form(&.{}, &[_]HTML.Attr{
        .{ .key = "method", .value = "POST" },
        .{ .key = "action", .value = "/endpoint" },
    }));
    dom = dom.open(HTML.element("button", &.{}, &.{
        .{ .key = "name", .value = "new" },
    }));
    dom.dupe(HTML.E.txt("create new"));
    dom = dom.close();
    dom = dom.close();

    const full = try dom.render(a, .full);
    dom.raze();
    defer a.free(full);
    const expected_full =
        \\<form method="POST" action="/endpoint">
        \\<button name="new">
        \\create new
        \\</button>
        \\</form>
    ;

    try std.testing.expectEqualStrings(expected_full, full);
}

test "basic" {
    const a = std.testing.allocator;
    var dom = create(a);
    try std.testing.expect(dom.child == null);
    _ = dom.done();
}

test "open close" {
    var a = std.testing.allocator;
    var dom = create(a);
    try std.testing.expect(dom.child == null);

    var new_dom = dom.open(HTML.div(&.{}, &.{}));
    try std.testing.expect(new_dom.child == null);
    try std.testing.expect(dom.child == new_dom);
    const closed = new_dom.close();
    try std.testing.expect(dom == closed);
    try std.testing.expect(dom.child == null);

    a.free(dom.done());
}

const std = @import("std");
const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;
const HTML = @import("../html.zig");
const Elem = HTML.E;
