const Templates = @import("../template.zig");
const Template = Templates.Template;
const Directive = Templates.Directive;

const Kind = enum {
    slice,
    directive,
};

const Offset = struct {
    start: usize,
    end: usize,
    kind: union(enum) {
        slice: []const u8,
        directive: struct {
            kind: type,
            data_offset: usize,
            d: Directive,
        },
        template: struct {
            html: []const u8,
            kind: type,
            data_offset: usize,
            len: usize,
        },
        array: struct {
            kind: type,
            data_offset: usize,
            len: usize,
        },
    },

    pub fn getData(comptime o: Offset, T: type, ptr: [*]const u8) *const T {
        const ptr_offset: usize = switch (o.kind) {
            .directive => |d| d.data_offset,
            .template => |t| t.data_offset,
            .array => |a| a.data_offset,
            .slice => unreachable,
        };
        return @ptrCast(@alignCast(&ptr[ptr_offset]));
    }
};

pub fn PageRuntime(comptime PageDataType: type) type {
    return struct {
        pub const Self = @This();
        pub const Kind = PageDataType;
        template: Template,
        data: PageDataType,

        pub fn init(t: Template, d: PageDataType) PageRuntime(PageDataType) {
            return .{
                .template = t,
                .data = d,
            };
        }

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
            //var ctx = self.data;
            var blob = self.template.blob;
            while (blob.len > 0) {
                if (indexOfScalar(u8, blob, '<')) |offset| {
                    try out.writeAll(blob[0..offset]);
                    blob = blob[offset..];
                    if (Directive.init(blob)) |drct| {
                        const end = drct.tag_block.len;
                        drct.formatTyped(PageDataType, self.data, out) catch |err| switch (err) {
                            error.IgnoreDirective => try out.writeAll(blob[0..end]),
                            error.VariableMissing => {
                                if (!is_test) log.err("Template Error, variable missing {{{s}}}", .{blob[0..end]});
                                try out.writeAll(blob[0..end]);
                            },
                            else => return err,
                        };

                        blob = blob[end..];
                    } else {
                        if (indexOfPosLinear(u8, blob, 1, "<")) |next| {
                            try out.writeAll(blob[0..next]);
                            blob = blob[next..];
                        } else {
                            return try out.writeAll(blob);
                        }
                    }
                    continue;
                }
                return try out.writeAll(blob);
            }
        }
    };
}

fn getOffset(T: type, name: []const u8, base: usize) usize {
    switch (@typeInfo(T)) {
        .@"struct" => {
            var local: [0xff]u8 = undefined;
            const end = makeFieldName(name, &local);
            const field = local[0..end];
            return @offsetOf(T, field) + base;
        },
        else => unreachable,
    }
}

test getOffset {
    const SUT1 = struct {
        a: usize,
        b: u8,
        value: []const u8,
    };
    const test_1 = comptime getOffset(SUT1, "value", 0);
    const test_2 = comptime getOffset(SUT1, "Value", 0);

    try std.testing.expectEqual(8, test_1);
    try std.testing.expectEqual(8, test_2);
    // Yes, by definition, if the previous two are true, the 3rd must be, but
    // it's actually testing specific behavior.
    try std.testing.expectEqual(test_1, test_2);

    const SUT2 = struct {
        a: usize,
        b: u16,
        parent: SUT1,
    };
    const test_4 = comptime getOffset(SUT2, "parent", 0);
    try std.testing.expectEqual(8, test_4);

    const test_5 = comptime getOffset(SUT1, "value", test_4);
    try std.testing.expectEqual(16, test_5);

    const vut = SUT2{
        .a = 12,
        .b = 98,
        .parent = .{
            .a = 21,
            .b = 89,
            .value = "clever girl",
        },
    };

    // Force into runtime
    var vari: *const []const u8 = undefined;
    const ptr: [*]const u8 = @ptrCast(&vut);
    vari = @as(*const []const u8, @ptrCast(@alignCast(&ptr[test_5])));
    try std.testing.expectEqualStrings("clever girl", vari.*);
}

fn baseType(T: type, name: []const u8) type {
    var local: [0xff]u8 = undefined;
    const field = local[0..makeFieldName(name, &local)];
    //return @TypeOf(@FieldType(T, field)); // not in 0.13.0
    for (std.meta.fields(T)) |f| {
        if (eql(u8, f.name, field)) {
            switch (f.type) {
                []const u8 => unreachable,
                ?[]const u8 => unreachable,
                ?usize => unreachable,
                else => switch (@typeInfo(f.type)) {
                    .pointer => |ptr| return ptr.child,
                    .optional => |opt| return opt.child,
                    .@"struct" => return f.type,
                    .int => return f.type,
                    else => @compileError("Unexpected kind " ++ f.name),
                },
            }
        }
    } else unreachable;
}

fn fieldType(T: type, name: []const u8) type {
    var local: [0xff]u8 = undefined;
    const field = local[0..makeFieldName(name, &local)];
    //return @TypeOf(@FieldType(T, field)); // not in 0.13.0
    for (std.meta.fields(T)) |f| {
        if (eql(u8, f.name, field)) {
            return f.type;
        }
    } else unreachable;
}

pub fn commentTag(blob: []const u8) ?usize {
    if (blob.len > 2 and blob[1] == '!' and blob.len > 4 and blob[2] == '-' and blob[3] == '-') {
        if (indexOfPosLinear(u8, blob, 4, "-->")) |comment| {
            return comment + 3;
        }
    }
    return null;
}

fn validateBlockSplit(
    index: usize,
    offset: usize,
    end: usize,
    pblob: []const u8,
    drct: Directive,
    data_offset: usize,
) []const Offset {
    const os = Offset{
        .start = index,
        .end = index + end,
        .kind = .{
            .directive = .{
                .kind = []const u8,
                .data_offset = data_offset,
                .d = drct,
            },
        },
    };
    // TODO Split needs whitespace postfix
    const ws_start: usize = offset + end;
    var wsidx = ws_start;
    while (wsidx < pblob.len and
        (pblob[wsidx] == ' ' or pblob[wsidx] == '\t' or
        pblob[wsidx] == '\n' or pblob[wsidx] == '\r'))
    {
        wsidx += 1;
    }
    if (wsidx > 0) {
        return &[_]Offset{
            .{
                .start = index + drct.tag_block.len,
                .end = index + wsidx,
                .kind = .{
                    .array = .{
                        .data_offset = data_offset,
                        .kind = []const []const u8,
                        .len = 2,
                    },
                },
            },
            os,
            .{
                .start = 0,
                .end = wsidx - end,
                .kind = .{
                    .slice = pblob[offset + end .. wsidx],
                },
            },
        };
    } else {
        return &[_]Offset{
            .{
                .start = index + drct.tag_block.len,
                .end = index + end,
                .data_offset = null,
                .kind = .{
                    .array = .{
                        .kind = []const []const u8,
                        .data_offset = data_offset,
                        .len = 1,
                    },
                },
            },
            os,
        };
    }
}

fn validateDirective(
    BlockType: type,
    index: usize,
    offset: usize,
    drct: Directive,
    pblob: []const u8,
    base_offset: usize,
) []const Offset {
    @setEvalBranchQuota(15000);
    const data_offset = getOffset(BlockType, drct.noun, base_offset);
    const end = drct.tag_block.len;
    switch (drct.verb) {
        .variable => {
            const FieldT = fieldType(BlockType, drct.noun);
            const os = Offset{
                .start = index,
                .end = index + end,
                .kind = .{
                    .directive = .{
                        .kind = FieldT,
                        .data_offset = data_offset,
                        .d = drct,
                    },
                },
            };
            return &[_]Offset{os};
        },
        .split => {
            const FieldT = fieldType(BlockType, drct.noun);
            std.debug.assert(FieldT == []const []const u8);
            return validateBlockSplit(index, offset, end, pblob, drct, data_offset)[0..];
        },
        .foreach, .with => {
            const FieldT = fieldType(BlockType, drct.noun);
            const os = Offset{
                .start = index,
                .end = index + end,
                .kind = .{
                    .directive = .{
                        .kind = FieldT,
                        .data_offset = data_offset,
                        .d = drct,
                    },
                },
            };
            // left in for testing
            if (drct.tag_block_body) |body| {
                // The code as written descends into the type.
                // if the call stack flattens out, it might be
                // better to calculate the offset from root.
                const BaseT = baseType(BlockType, drct.noun);
                const loop = validateBlock(body, BaseT, 0);
                return &[_]Offset{.{
                    .start = index + drct.tag_block_skip.?,
                    .end = index + end,
                    .kind = .{
                        .array = .{
                            .kind = FieldT,
                            .data_offset = data_offset,
                            .len = loop.len,
                        },
                    },
                }} ++ loop;
            } else {
                return &[_]Offset{os};
            }
        },
        .build => {
            const BaseT = baseType(BlockType, drct.noun);
            const FieldT = fieldType(BlockType, drct.noun);
            const loop = validateBlock(drct.otherwise.template.blob, BaseT, 0);
            return &[_]Offset{.{
                .start = index,
                .end = index + end,
                .kind = .{
                    .template = .{
                        .html = drct.otherwise.template.blob,
                        .kind = FieldT,
                        .data_offset = data_offset,
                        .len = loop.len,
                    },
                },
            }} ++ loop;
        },
    }
}

pub fn validateBlock(comptime html: []const u8, BlockType: type, base_offset: usize) []const Offset {
    @setEvalBranchQuota(10000);
    var found_offsets: []const Offset = &[0]Offset{};
    var pblob = html;
    var index: usize = 0;
    var open_idx: usize = 0;
    // Originally attempted to write this just using index, but got catastrophic
    // backtracking errors when compiling. I'd have assumed this version would
    // be more expensive, but here we are :D
    while (pblob.len > 0) {
        if (indexOfScalar(u8, pblob, '<')) |offset| {
            // TODO this implementation makes tracking whitespace much harder.
            pblob = pblob[offset..];
            index += offset;
            if (Directive.init(pblob)) |drct| {
                found_offsets = found_offsets ++
                    [_]Offset{.{
                    .start = open_idx,
                    .end = index,
                    .kind = .{
                        .slice = html[open_idx..index],
                    },
                }} ++ validateDirective(BlockType, index, offset, drct, pblob, base_offset);
                const end = drct.tag_block.len;
                pblob = pblob[end..];
                index += end;
                open_idx = index;
            } else if (commentTag(pblob)) |skip| {
                pblob = pblob[skip..];
                index += skip;
            } else {
                if (indexOfPosLinear(u8, pblob, 1, "<")) |next| {
                    pblob = pblob[next..];
                    index += next;
                } else break;
            }
        } else break;
    }
    if (index != pblob.len or open_idx == 0) {
        found_offsets = found_offsets ++ [_]Offset{.{
            .start = open_idx,
            .end = html.len,
            .kind = .{
                .slice = html[open_idx..],
            },
        }};
    }
    return found_offsets;
}

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
                        // TODO actually less that 1
                        count += 1;

                        // I originally implemented this assuming that the
                        // correct implementation should give the exact size,
                        // but it's possible the correct implementation should
                        // give a max size, to optimize for time instead of
                        // space.
                        //
                        //const dr_opt = dos.getData(drct.kind, @ptrCast(&self.data));
                        //switch (drct.kind) {
                        //    usize, []const u8 => count += 1,
                        //    ?[]const u8 => {
                        //        if (dr_opt.*) |_| {
                        //            count += 1;
                        //        } else if (drct.d.otherwise == .default) {
                        //            count += 1;
                        //        }
                        //    },
                        //    ?usize => {
                        //        if (dr_opt.*) |_| count += 1;
                        //    },
                        //    else => |t| @compileError("unsupported directive type " ++ @typeName(t)),
                        //}

                    },
                    .template => |t| {
                        const child_data = dos.getData(t.kind, data);
                        count += iovecCount(ofs[idx..][0..t.len], @ptrCast(child_data));
                        skip = t.len;
                    },
                    .array => |array| switch (@typeInfo(array.kind)) {
                        .pointer => {
                            const child_data: array.kind = dos.getData(array.kind, data).*;
                            for (child_data) |cd| {
                                count += iovecCount(ofs[idx..][0..array.len], @ptrCast(&cd));
                            }
                            skip = array.len;
                        },
                        .optional => {
                            const child_data = dos.getData(array.kind, data).*;
                            if (child_data) |cd| {
                                count += iovecCount(ofs[idx..][0..array.len], @ptrCast(&cd));
                            } else count += array.len;
                            skip = array.len;
                        }, // TODO implement
                        else => unreachable,
                    },
                }
            }
            return count;
        }

        pub fn iovecCountAll(self: Self) usize {
            return iovecCount(Self.DataOffsets[0..], @ptrCast(&self.data));
        }

        fn offsetDirective(T: type, data: T, directive: Directive, out: anytype) !void {
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

        fn offsetOptionalItem(T: type, item: ?T, comptime ofs: []const Offset, html: []const u8, out: anytype) !void {
            if (comptime T == ?[]const u8) return offsetDirective(T, item.?, ofs[0], out);
            switch (@typeInfo(T)) {
                .int => std.debug.print("skipped int\n", .{}),
                .@"struct" => if (item) |itm| try formatDirective(T, itm, ofs, html, out),
                else => comptime unreachable,
            }
        }

        fn offsetArray(T: type, data: T, comptime ofs: []const Offset, html: []const u8, out: anytype) !void {
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
                        std.debug.assert(ptr.size == .slice);
                        for (data) |each| try formatDirective(ptr.child, each, ofs, html, out);
                    },
                    .optional => |opt| {
                        if (opt.child == []const u8) unreachable;
                        try offsetOptionalItem(opt.child, data, ofs, html, out);
                    },
                    else => {
                        std.debug.print("unexpected type {s}\n", .{@typeName(T)});
                        unreachable;
                    },
                },
            };
        }

        fn formatDirective(T: type, data: T, comptime ofs: []const Offset, html: []const u8, out: anytype) !void {
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
                    .array => |array| {
                        const child_data = os.getData(array.kind, @ptrCast(&data));
                        try offsetArray(array.kind, child_data.*, ofs[idx + 1 ..][0..array.len], html[os.start..os.end], out);
                        skip = array.len;
                    },
                    .directive => |directive| switch (directive.d.verb) {
                        .variable => {
                            //std.debug.print("directive\n", .{});
                            const child_data = os.getData(directive.kind, @ptrCast(&data));
                            try offsetDirective(directive.kind, child_data.*, directive.d, out);
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

        fn ioVecDirective(T: type, data: T, drct: Directive, vec: []IOVec, a: Allocator) !usize {
            std.debug.assert(drct.verb == .variable);
            switch (T) {
                []const u8 => vec[0] = .{ .base = data.ptr, .len = data.len },
                ?[]const u8 => if (data) |d| {
                    vec[0] = .{ .base = d.ptr, .len = d.len };
                } else if (drct.otherwise == .default) {
                    vec[0] = .{ .base = drct.otherwise.default.ptr, .len = drct.otherwise.default.len };
                },
                usize, isize => {
                    const int = try allocPrint(a, "{}", .{data});
                    vec[0] = .{ .base = int.ptr, .len = int.len };
                },
                ?usize => {
                    if (data) |us| {
                        const int = try allocPrint(a, "{}", .{us});
                        vec[0] = .{ .base = int.ptr, .len = int.len };
                    }
                },
                else => {
                    std.debug.print("ignored directive {} {s}\n", .{ drct.verb, drct.noun });
                    return 0;
                },
            }
            return if (vec[0].len > 0) 1 else 0;
        }

        fn ioVecArray(T: type, data: T, comptime ofs: []const Offset, vec: []IOVec, a: Allocator) !usize {
            var idx: usize = 0;
            switch (T) {
                []const u8, u8 => unreachable,
                []const []const u8 => {
                    for (data) |each| {
                        vec[idx] = .{ .base = each.ptr, .len = each.len };
                        idx += 1;
                        // I should find a better way to write this hack
                        if (ofs.len == 2) {
                            if (ofs[1].kind == .slice and ofs[1].kind.slice.len > 0) {
                                vec[idx] = .{ .base = ofs[1].kind.slice.ptr, .len = ofs[1].kind.slice.len };
                                idx += 1;
                            }
                        }
                    }
                },
                else => switch (@typeInfo(T)) {
                    .pointer => |ptr| {
                        std.debug.assert(ptr.size == .slice);
                        for (data) |each| idx += try ioVecCore(ptr.child, each, ofs, vec[idx..], a);
                    },
                    .optional => |opt| {
                        if (opt.child == []const u8) unreachable;
                        switch (@typeInfo(opt.child)) {
                            .int => std.debug.print("skipped int\n", .{}),
                            .@"struct" => {
                                if (data) |d| return try ioVecCore(opt.child, d, ofs, vec, a);
                            },
                            else => unreachable,
                        }
                    },
                    else => {
                        std.debug.print("unexpected type {s}\n", .{@typeName(T)});
                        unreachable;
                    },
                },
            }
            return idx;
        }

        pub fn ioVecCore(T: type, data: T, ofs: []const Offset, vec: []IOVec, a: Allocator) !usize {
            var skip: usize = 0;
            var vec_idx: usize = 0;
            inline for (ofs, 1..) |os, os_idx| {
                if (skip > 0) {
                    skip -|= 1;
                } else switch (os.kind) {
                    .slice => |slice| {
                        vec[vec_idx] = .{
                            .base = slice.ptr,
                            .len = slice.len,
                        };
                        vec_idx += 1;
                    },
                    .array => |array| {
                        const child_data = os.getData(array.kind, @ptrCast(&data));
                        vec_idx += try ioVecArray(array.kind, child_data.*, ofs[os_idx..][0..array.len], vec[vec_idx..], a);
                        skip = array.len;
                    },
                    .directive => |directive| switch (directive.d.verb) {
                        .variable => {
                            const child_data = os.getData(directive.kind, @ptrCast(&data));
                            vec_idx += try ioVecDirective(directive.kind, child_data.*, directive.d, vec[vec_idx..], a);
                        },
                        else => {
                            std.debug.print("directive skipped {} {}\n", .{ directive.d.verb, ofs.len });
                        },
                    },
                    .template => |tmpl| {
                        const child_data = os.getData(tmpl.kind, @ptrCast(&data));
                        vec_idx += try ioVecCore(tmpl.kind, child_data.*, ofs[os_idx..][0..tmpl.len], vec[vec_idx..], a);
                        skip = tmpl.len;
                    },
                }
            }
            return vec_idx;
        }

        /// Caller must
        /// 0. provide a vec that is large enough for the entire page.
        /// 1. provide an allocator that's able to track allocations outside of
        ///    this function (e.g. an ArenaAllocator) This unintentionally leaks by design.
        pub fn ioVec(self: Self, vec: []IOVec, a: Allocator) ![]IOVec {
            return vec[0..try ioVecCore(PageDataType, self.data, Self.DataOffsets[0..], vec[0..], a)];
        }

        pub fn format(self: Self, comptime _: []const u8, _: std.fmt.FormatOptions, out: anytype) !void {
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

    const vec = try page.ioVec(vecbuf[0..], a);

    try std.testing.expect(vec.len < page.iovecCountAll());
    // The following two numbers weren't validated in anyway.
    try std.testing.expectEqual(49, vec.len);
    try std.testing.expectEqual(56, page.iovecCountAll());
}

const makeFieldName = @import("builtins.zig").makeFieldName;
fn typeField(T: type, name: []const u8, data: T) ?[]const u8 {
    if (@typeInfo(T) != .@"struct") return null;
    var local: [0xff]u8 = undefined;
    const realname = local[0..makeFieldName(name, &local)];
    inline for (std.meta.fields(T)) |field| {
        if (eql(u8, field.name, realname)) {
            switch (field.type) {
                []const u8,
                ?[]const u8,
                => return @field(data, field.name),

                else => return null,
            }
        }
    }
    return null;
}

const std = @import("std");
const is_test = @import("builtin").is_test;
const log = std.log.scoped(.Verse);
const Allocator = std.mem.Allocator;
const AnyWriter = std.io.AnyWriter;
const IOVec = std.posix.iovec_const;
const eql = std.mem.eql;
const indexOfScalar = std.mem.indexOfScalar;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const indexOfPosLinear = std.mem.indexOfPosLinear;
const allocPrint = std.fmt.allocPrint;
