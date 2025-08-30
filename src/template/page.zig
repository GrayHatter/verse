pub fn Page(comptime template: Template, comptime PageDataType: type) type {
    const offsets = validateBlock(template.blob, PageDataType, 0);
    const offset_len = offsets.len;

    return struct {
        data: PageDataType,

        pub const Self = @This();
        pub const Kind = PageDataType;
        pub const PageTemplate = template;
        pub const DataOffsets: [offset_len]Offset = offsets[0..offset_len].*;

        pub fn init(d: PageDataType) Page(template, PageDataType) {
            return .{ .data = d };
        }

        pub fn iovecCount(ofs: []const Offset, data: [*]const u8) usize {
            var count: usize = 0;
            var skip: usize = 0;
            inline for (ofs, 1..) |dos, idx| {
                if (skip > 0) {
                    skip -= 1;
                } else switch (dos.kind) {
                    .slice => count += 1,
                    .directive => |_| {
                        // I originally implemented this assuming that the
                        // correct implementation should give the exact size,
                        // but it's possible the correct implementation should
                        // give a max size, to optimize for time instead of
                        // space.
                        // TODO actually less that 1
                        count += 1;
                    },
                    .template => |t| {
                        const child_data = dos.getData(t.kind, data);
                        count += iovecCount(ofs[idx..][0..t.len], @ptrCast(child_data));
                        skip = t.len;
                    },
                    .component => |comp| switch (@typeInfo(comp.kind)) {
                        .pointer => {
                            const child_data: comp.kind = dos.getData(comp.kind, data).*;
                            for (child_data) |cd| {
                                count += iovecCount(ofs[idx..][0..comp.len], @ptrCast(&cd));
                            }
                            skip = comp.len;
                        },
                        .optional => {
                            const child_data = dos.getData(comp.kind, data).*;
                            if (child_data) |cd| {
                                count += iovecCount(ofs[idx..][0..comp.len], @ptrCast(&cd));
                            } else count += comp.len;
                            skip = comp.len;
                        },
                        .array => {
                            const child_data: comp.kind = dos.getData(comp.kind, data).*;
                            for (child_data) |cd| {
                                count += iovecCount(ofs[idx..][0..comp.len], @ptrCast(&cd));
                            }
                            skip = comp.len;
                        },
                        else => comptime unreachable,
                    },
                }
            }
            return count;
        }

        pub fn iovecCountAll(self: Self) usize {
            return iovecCount(Self.DataOffsets[0..], @ptrCast(&self.data));
        }

        fn offsetDirective(T: type, data: T, directive: Directive, out: *Writer) error{WriteFailed}!void {
            std.debug.assert(directive.verb == .variable);
            switch (T) {
                []const u8 => try out.writeAll(data),
                ?[]const u8 => if (data) |d| {
                    try out.writeAll(d);
                } else if (directive.otherwise == .default) {
                    try out.writeAll(directive.otherwise.default);
                },
                ?usize => {
                    if (data) |us| {
                        return try directive.formatTyped(usize, us, out);
                    }
                },
                else => {
                    return try directive.formatTyped(T, data, out);
                },
            }
        }

        fn offsetOptionalItem(T: type, item: ?T, comptime ofs: []const Offset, html: []const u8, out: *Writer) !void {
            if (comptime T == ?[]const u8) return offsetDirective(T, item.?, ofs[0], out);
            switch (@typeInfo(T)) {
                .int => std.debug.print("skipped int\n", .{}),
                .@"struct" => if (item) |itm| try formatDirective(T, itm, ofs, html, out),
                else => comptime unreachable,
            }
        }

        fn offsetArray(T: type, data: T, comptime ofs: []const Offset, html: []const u8, out: *Writer) !void {
            return switch (T) {
                []const u8, u8 => unreachable,
                []const []const u8 => {
                    for (data) |each| {
                        try out.writeAll(each);
                        // I should find a better way to write this hack
                        if (ofs.len == 2) {
                            if (ofs[1].kind == .slice) {
                                try out.writeAll(html[ofs[1].start..ofs[1].end]);
                            }
                        }
                    }
                },
                else => switch (@typeInfo(T)) {
                    .pointer => |ptr| {
                        comptime std.debug.assert(ptr.size == .slice);
                        for (data) |each| try formatDirective(ptr.child, each, ofs, html, out);
                    },
                    .optional => |opt| {
                        if (opt.child == []const u8) unreachable;
                        try offsetOptionalItem(opt.child, data, ofs, html, out);
                    },
                    .array => |array| {
                        for (data) |each| try formatDirective(array.child, each, ofs, html, out);
                    },
                    else => {
                        @compileLog("unexpected type {s}\n", .{@typeName(T)});
                        comptime unreachable;
                    },
                },
            };
        }

        fn formatDirective(T: type, data: T, comptime ofs: []const Offset, html: []const u8, out: *Writer) error{WriteFailed}!void {
            var skip: usize = 0;
            inline for (ofs, 0..) |os, idx| {
                if (skip > 0) {
                    skip -|= 1;
                } else switch (os.kind) {
                    .slice => |slice| {
                        if (idx == 0) {
                            try out.writeAll(std.mem.trimLeft(u8, slice, " \n\r"));
                        } else if (idx == ofs.len) {
                            //try out.writeAll(std.mem.trimRight(u8, html[os.start..os.end], " \n\r"));
                            try out.writeAll(slice);
                        } else if (ofs.len == 1) {
                            try out.writeAll(std.mem.trim(u8, slice, " \n\r"));
                        } else {
                            try out.writeAll(slice);
                        }
                    },
                    .component => |comp| {
                        const child_data = os.getData(comp.kind, @ptrCast(&data));
                        try offsetArray(comp.kind, child_data.*, ofs[idx + 1 ..][0..comp.len], html[os.start..os.end], out);
                        skip = comp.len;
                    },
                    .directive => |directive| switch (directive.d.verb) {
                        .variable => {
                            const child_data = os.getData(directive.kind, @ptrCast(&data));
                            switch (directive.d.otherwise) {
                                .literal => |lit| {
                                    // TODO figure out how to make this a u16 cmp instead of mem.eql
                                    if (std.mem.eql(u8, @tagName(child_data.*), lit)) {
                                        try out.writeAll(directive.kind.VALUE);
                                    }
                                },
                                else => {
                                    try offsetDirective(directive.kind, child_data.*, directive.d, out);
                                },
                            }
                        },
                        else => {
                            std.debug.print("directive skipped {} {}\n", .{ directive.d.verb, ofs.len });
                        },
                    },
                    .template => |tmpl| {
                        const child_data = os.getData(tmpl.kind, @ptrCast(&data));
                        try formatDirective(tmpl.kind, child_data.*, ofs[idx + 1 ..][0..tmpl.len], tmpl.html, out);
                        skip = tmpl.len;
                    },
                }
            }
        }

        fn ioVecDirective(T: type, data: T, drct: Directive, varr: *IOVArray, a: Allocator) !void {
            std.debug.assert(drct.verb == .variable);
            switch (T) {
                []const u8 => {
                    varr.appendAssumeCapacity(.fromSlice(data));
                },
                ?[]const u8 => {
                    if (data) |d| {
                        if (d.len > 0) varr.appendAssumeCapacity(.fromSlice(d));
                    } else if (drct.otherwise == .default) {
                        if (drct.otherwise.default.len > 0)
                            varr.appendAssumeCapacity(.fromSlice(drct.otherwise.default));
                    }
                },
                usize, isize => {
                    const int = try allocPrint(a, "{}", .{data});
                    varr.appendAssumeCapacity(.fromSlice(int));
                },
                ?usize => {
                    if (data) |us| {
                        const int = try allocPrint(a, "{}", .{us});
                        varr.appendAssumeCapacity(.fromSlice(int));
                    }
                },
                else => comptime unreachable,
            }
        }

        fn ioVecArray(T: type, data: T, comptime ofs: []const Offset, varr: *IOVArray, a: Allocator) !void {
            switch (T) {
                []const u8, u8 => comptime unreachable,
                []const []const u8 => {
                    for (data) |each| {
                        varr.appendAssumeCapacity(.fromSlice(each));
                        // I should find a better way to write this hack
                        if (ofs.len == 2) {
                            if (ofs[1].kind == .slice and ofs[1].kind.slice.len > 0) {
                                varr.appendAssumeCapacity(.fromSlice(ofs[1].kind.slice));
                            }
                        }
                    }
                },
                else => switch (@typeInfo(T)) {
                    .pointer => |ptr| {
                        std.debug.assert(ptr.size == .slice);
                        for (data) |each| try ioVecCore(ptr.child, each, ofs, varr, a);
                    },
                    .optional => |opt| {
                        if (opt.child == []const u8) unreachable;
                        switch (@typeInfo(opt.child)) {
                            .int => std.debug.print("skipped int\n", .{}),
                            .@"struct" => {
                                if (data) |d| return try ioVecCore(opt.child, d, ofs, varr, a);
                            },
                            else => unreachable,
                        }
                    },
                    .array => |array| {
                        for (data) |each| try ioVecCore(array.child, each, ofs, varr, a);
                    },
                    else => {
                        std.debug.print("unexpected type {s}\n", .{@typeName(T)});
                        comptime unreachable;
                    },
                },
            }
        }

        pub fn ioVecCore(T: type, data: T, ofs: []const Offset, varr: *IOVArray, a: Allocator) !void {
            var skip: usize = 0;
            inline for (ofs, 1..) |os, os_idx| {
                if (skip > 0) {
                    skip -|= 1;
                } else switch (os.kind) {
                    .slice => |slice| {
                        varr.appendAssumeCapacity(.fromSlice(slice));
                    },
                    .component => |comp| {
                        const child_data = os.getData(comp.kind, @ptrCast(&data));
                        try ioVecArray(comp.kind, child_data.*, ofs[os_idx..][0..comp.len], varr, a);
                        skip = comp.len;
                    },
                    .directive => |directive| switch (directive.d.verb) {
                        .variable => {
                            const child_data = os.getData(directive.kind, @ptrCast(&data));
                            switch (directive.d.otherwise) {
                                .literal => |lit| {
                                    // TODO figure out how to make this a u16 cmp instead of mem.eql
                                    if (std.mem.eql(u8, @tagName(child_data.*), lit)) {
                                        varr.appendAssumeCapacity(.fromSlice(directive.kind.VALUE));
                                    }
                                },
                                else => {
                                    try ioVecDirective(directive.kind, child_data.*, directive.d, varr, a);
                                },
                            }
                        },
                        else => {
                            std.debug.print("directive skipped {} {}\n", .{ directive.d.verb, ofs.len });
                        },
                    },
                    .template => |tmpl| {
                        const child_data = os.getData(tmpl.kind, @ptrCast(&data));
                        try ioVecCore(tmpl.kind, child_data.*, ofs[os_idx..][0..tmpl.len], varr, a);
                        skip = tmpl.len;
                    },
                }
            }
        }

        /// Caller must
        /// 0. provide a vec that is large enough for the entire page.
        /// 1. provide an allocator that's able to track allocations outside of
        ///    this function (e.g. an ArenaAllocator) This unintentionally leaks by design.
        pub fn ioVec(self: Self, vec: *IOVArray, a: Allocator) !void {
            return try ioVecCore(PageDataType, self.data, Self.DataOffsets[0..], vec, a);
        }

        pub fn format(self: Self, out: *Writer) error{WriteFailed}!void {
            //std.debug.print("offs {any}\n", .{Self.DataOffsets});
            const blob = Self.PageTemplate.blob;
            if (Self.DataOffsets.len == 0)
                return try out.writeAll(blob);

            try formatDirective(PageDataType, self.data, Self.DataOffsets[0..], blob, out);
        }
    };
}

test Page {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    const PUT = Templates.PageData("templates/example.html");

    var vecbuf = [_]IOVec{undefined} ** 128;
    var varr: IOVArray = .initBuffer(&vecbuf);

    const page = PUT.init(.{
        .simple_variable = " ",
        .required_and_provided = " ",
        .default_provided = " ",
        .positive_number = 1,
        .optional_with = null,
        .namespaced_with = .{ .simple_variable = " " },
        .basic_loop = &.{
            .{ .color = "red", .text = "red" },
            .{ .color = "blue", .text = "blue" },
            .{ .color = "green", .text = "green" },
        },
        .slices = &.{ "1", "2", "3", "4" },
        .include_vars = .{ .template_name = " ", .simple_variable = " " },
        .empty_vars = .{},
    });

    try page.ioVec(&varr, a);

    try std.testing.expect(varr.items.len < page.iovecCountAll());
    // The following two numbers weren't validated in anyway.
    try std.testing.expectEqual(49, varr.items.len);
    try std.testing.expectEqual(56, page.iovecCountAll());
}

test {
    _ = &std.testing.refAllDecls(@This());
    _ = &constructor;
}

const Templates = @import("../template.zig");
const Template = Templates.Template;
const Directive = Templates.Directive;
const constructor = @import("constructor.zig");

const validateBlock = constructor.validateBlock;
const Offset = constructor.Offset;

const std = @import("std");
const is_test = @import("builtin").is_test;
const log = std.log.scoped(.Verse);
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const iov = @import("../iovec.zig");
const IOVec = iov.IOVec;
const IOVArray = iov.IOVArray;

const indexOfScalar = std.mem.indexOfScalar;
const indexOfPosLinear = std.mem.indexOfPosLinear;
const allocPrint = std.fmt.allocPrint;
