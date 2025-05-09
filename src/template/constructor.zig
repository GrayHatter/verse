const Kind = enum {
    slice,
    directive,
};

pub const Offset = struct {
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
        list: struct {
            kind: type,
            data_offset: usize,
            len: usize,
        },
    },

    pub fn getData(comptime o: Offset, T: type, ptr: [*]const u8) *const T {
        const ptr_offset: usize = switch (o.kind) {
            .directive => |d| d.data_offset,
            .template => |t| t.data_offset,
            .list => |a| a.data_offset,
            .slice => unreachable,
        };
        return @ptrCast(@alignCast(&ptr[ptr_offset]));
    }
};

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
        a: u64,
        b: u8,
        value: []const u8,
    };
    const test_1 = comptime getOffset(SUT1, "value", 0);
    const test_2 = comptime getOffset(SUT1, "Value", 0);

    try std.testing.expectEqual(8, test_1);
    try std.testing.expectEqual(8, test_2);
    // Yes, by definition, if the previous two are true, the 3rd must be, but
    // it's actually testing specific behavior.
    // dear future me; you can have this back once you comment what specific
    // behavior this proves!
    // try std.testing.expectEqual(test_1, test_2);

    const SUT2 = struct {
        a: u64,
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
                    .array => |array| return array.child,
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
                    .list = .{
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
                    .list = .{
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
    @setEvalBranchQuota(20000);
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
                        .list = .{
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

test {
    _ = &std.testing.refAllDecls(@This());
}

const std = @import("std");
const log = std.log.scoped(.Verse);

const Templates = @import("../template.zig");
const Template = Templates.Template;
const Directive = Templates.Directive;

const eql = std.mem.eql;
const indexOfScalar = std.mem.indexOfScalar;
const indexOfPosLinear = std.mem.indexOfPosLinear;
