alloc: Allocator,
elems: ArrayList(Elem),
parent: ?*DOM = null,
child: ?*DOM = null,
opened: ?Elem = null,

const DOM = @This();

pub fn create(a: Allocator) *DOM {
    const self = a.create(DOM) catch unreachable;
    self.* = DOM{ .alloc = a, .elems = .{} };
    return self;
}

pub fn open(self: *DOM, elem: HTML.E) *DOM {
    if (self.child) |_| @panic("DOM Already Open");
    self.child = create(self.alloc);
    self.child.?.parent = self;
    self.child.?.opened = elem;
    return self.child.?;
}

pub fn pushSlice(self: *DOM, elems: []const HTML.E) void {
    for (elems) |elem| self.push(elem);
}

pub fn push(self: *DOM, elem: HTML.E) void {
    self.elems.append(self.alloc, elem) catch unreachable;
}

pub fn dupe(self: *DOM, elem: HTML.E) void {
    self.elems.append(self.alloc, HTML.E{
        .name = elem.name,
        .text = elem.text,
        .children = if (elem.children) |c| self.alloc.dupe(HTML.E, c) catch null else null,
        .attrs = if (elem.attrs) |a| self.alloc.dupe(HTML.Attribute, a) catch null else null,
    }) catch unreachable;
}

pub fn close(self: *DOM) *DOM {
    if (self.parent) |p| {
        self.opened.?.children = self.elems.toOwnedSlice(self.alloc) catch unreachable;
        p.push(self.opened.?);
        p.child = null;
        defer self.alloc.destroy(self);
        return p;
    } else @panic("DOM ISN'T OPEN");
    unreachable;
}

pub fn done(self: *DOM) []HTML.E {
    if (self.child) |_| @panic("INVALID STATE DOM STILL HAS OPEN CHILDREN");
    defer self.alloc.destroy(self);
    return self.elems.toOwnedSlice(self.alloc) catch unreachable;
}

fn freeChildren(a: Allocator, elems: []const Elem) void {
    for (elems) |elem| {
        if (elem.children) |children| {
            freeChildren(a, children);
            a.free(children);
        }
    }
}

pub fn raze(d: *DOM) void {
    freeChildren(d.alloc, d.elems.items);
    d.elems.deinit(d.alloc);
    d.alloc.destroy(d);
}

pub fn fmtFull(d: DOM, w: *Writer) Writer.Error!void {
    if (d.child) |_| @panic("INVALID STATE DOM STILL HAS OPEN CHILDREN");
    for (d.elems.items) |e| {
        w.print("{f}", .{std.fmt.alt(e, .pretty)}) catch unreachable;
    }
}

pub fn format(d: DOM, w: *Writer) Writer.Error!void {
    for (d.elems.items) |e| {
        w.print("{f}", .{e}) catch unreachable;
    }
}

pub fn render(d: *DOM, a: Allocator, comptime style: enum { full, compact }) ![]u8 {
    if (d.child) |_| @panic("INVALID STATE DOM STILL HAS OPEN CHILDREN");
    defer d.raze();

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
    var dom: *DOM = .create(a);
    dom = dom.open(HTML.form(null, &[_]HTML.Attr{
        .{ .key = "method", .value = "POST" },
        .{ .key = "action", .value = "/endpoint" },
    }));
    dom = dom.open(HTML.element("button", null, &[_]HTML.Attr{
        .{ .key = "name", .value = "new" },
    }));
    dom.dupe(HTML.element("_text", "create new", null));
    dom = dom.close();
    dom = dom.close();

    const compact = try dom.render(a, .compact);
    defer a.free(compact);
    const expected_compact =
        \\<form method="POST" action="/endpoint"><button name="new">create new</button></form>
    ;
    try std.testing.expectEqualStrings(expected_compact, compact);

    dom = .create(a);
    dom = dom.open(HTML.form(null, &[_]HTML.Attr{
        .{ .key = "method", .value = "POST" },
        .{ .key = "action", .value = "/endpoint" },
    }));
    dom = dom.open(HTML.element("button", null, &[_]HTML.Attr{
        .{ .key = "name", .value = "new" },
    }));
    dom.dupe(HTML.element("_text", "create new", null));
    dom = dom.close();
    dom = dom.close();

    const full = try dom.render(a, .full);
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

    var new_dom = dom.open(HTML.div(null, null));
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
