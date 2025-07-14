verb: Verb,
noun: []const u8,
otherwise: Otherwise,
tag_block: []const u8,
tag_block_body: ?[]const u8 = null,
tag_block_skip: ?usize = null,
html_type: ?HtmlType = null,

pub const Directive = @This();

pub const Otherwise = union(enum) {
    required: void,
    delete: void,
    default: []const u8,
    template: Template,
    exact: usize,
    literal: []const u8,
    //page: type,
};

pub const Verb = enum {
    build,
    directive,
    foreach,
    split,
    variable,
    with,
};

pub const HtmlType = enum {
    usize,
    isize,
    @"?usize",
    @"enum",

    pub fn fromStr(s: []const u8) !HtmlType {
        inline for (std.meta.fields(HtmlType)) |ht| {
            if (eql(u8, ht.name, s)) {
                return @enumFromInt(ht.value);
            }
        }
        return error.InvalidHtmlType;
    }

    pub fn nullable(kt: HtmlType) bool {
        return switch (kt) {
            .usize,
            .isize,
            .@"enum",
            => false,
            .@"?usize" => true,
        };
    }
};

pub fn init(str: []const u8) ?Directive {
    if (str.len < 2) return null;
    if (!isUpper(str[1]) and str[1] != '_') return null;
    const tag = findTag(str) catch return null;
    const verb = tag[1 .. indexOfAnyPos(u8, tag, 1, " /") orelse tag.len - 1];

    if (verb.len == tag.len - 2) {
        if (initNoun(verb, tag)) |noun| {
            return noun;
        } else unreachable;
    }

    const noun = tag[verb.len + 1 .. tag.len - 1];

    return initVerb(verb, noun, str) orelse initNoun(verb, tag);
}

fn initNoun(noun: []const u8, tag: []const u8) ?Directive {
    //std.debug.print("init noun {s}\n", .{noun});

    if (noun[0] == '_') @panic("Template Directives must not start with _");

    var default_str: ?[]const u8 = null;
    var h_type: ?HtmlType = null;
    var tag_name: ?[]const u8 = null;
    var directive: ?[]const u8 = null;
    var rem_attr: []const u8 = tag[noun.len + 1 .. tag.len - 1];
    while (indexOfScalar(u8, rem_attr, '=') != null) {
        if (findAttribute(rem_attr)) |attr| {
            if (eql(u8, attr.name, "type")) {
                h_type = HtmlType.fromStr(attr.value) catch {
                    std.debug.print("Unable to resolve requested type '{s}'\n", .{attr.value});
                    unreachable;
                };
            } else if (eql(u8, "default", attr.name)) {
                default_str = attr.value;
            } else if (eql(u8, "enum", attr.name)) {
                tag_name = attr.value;
                h_type = .@"enum";
            } else if (eql(u8, "text", attr.name)) {
                directive = attr.value;
            }

            rem_attr = rem_attr[attr.len..];
        } else |err| switch (err) {
            error.AttrInvalid => break,
            else => unreachable,
        }
    }

    return Directive{
        .verb = .variable,
        .noun = noun,
        .otherwise = if (default_str) |str|
            .{ .default = str }
        else if (indexOf(u8, tag, " ornull")) |_|
            .delete
        else if (h_type) |htype|
            if (htype.nullable())
                .delete
            else if (htype == .@"enum")
                .{ .literal = tag_name orelse b: {
                    if (!@inComptime()) {
                        std.debug.print("Tag name not given for enum type\n", .{});
                        unreachable;
                    }
                    break :b "blah";
                } }
            else
                .required
        else
            .required,
        .html_type = h_type,
        .tag_block = tag,
    };
}

pub fn initVerb(verb: []const u8, noun: []const u8, blob: []const u8) ?Directive {
    const word: Verb = if (eql(u8, verb, "For"))
        .foreach
    else if (eql(u8, verb, "Directive"))
        .directive
    else if (eql(u8, verb, "Split"))
        .split
    else if (eql(u8, verb, "With"))
        .with
    else if (eql(u8, verb, "Build"))
        .build
    else
        return null;

    switch (word) {
        .variable => unreachable,
        .build => {
            const b_noun = noun[1..(indexOfScalarPos(u8, noun, 1, ' ') orelse return null)];
            const tail = noun[b_noun.len + 1 ..];
            const b_html = tail[1..(indexOfScalarPos(u8, tail, 2, ' ') orelse return null)];
            if (@inComptime()) {
                if (getBuiltin(b_html)) |bi| return Directive{
                    .verb = .build,
                    .noun = b_noun,
                    .otherwise = .{ .template = bi },
                    .tag_block = blob[0 .. verb.len + 2 + noun.len],
                };
            } else {
                if (getBuiltin(b_html)) |bi| {
                    return Directive{
                        .verb = .build,
                        .noun = b_noun,
                        .otherwise = .{ .template = bi },
                        .tag_block = blob[0 .. verb.len + 2 + noun.len],
                    };
                } else return null;
            }
        },
        .directive => {
            const end = calcBody("Directive", noun, blob) orelse return null;
            const body_end: usize = end;
            const tag_block_body = blob[0..body_end];
            var end_idx: usize = verb.len + 2 + noun.len;
            while (end_idx < blob.len and (blob[end_idx] == ' ' or blob[end_idx] == '\n')) end_idx += 1;
            const tag_block = blob[0..end_idx];

            var name: ?[]const u8 = null;
            var text: ?[]const u8 = null;
            var rem_attr: []const u8 = tag_block_body["<Directive ".len..body_end];
            while (indexOfScalar(u8, rem_attr, '=') != null) {
                if (findAttribute(rem_attr)) |attr| {
                    if (eql(u8, attr.name, "type")) {
                        if (!eql(u8, "enum", attr.value)) {
                            std.debug.print("Unable to resolve requested type '{s}'\n", .{attr.value});
                            @panic("wut");
                        }
                    } else if (eql(u8, "name", attr.name)) {
                        name = attr.value;
                    } else if (eql(u8, "text", attr.name)) {
                        text = attr.value;
                    } else {
                        unreachable;
                    }
                    rem_attr = rem_attr[attr.len..];
                } else |err| switch (err) {
                    error.AttrInvalid => break,
                    else => unreachable,
                }
            }
            std.debug.assert(std.mem.indexOf(u8, rem_attr, "name") == null);
            return Directive{
                .verb = .directive,
                .noun = name orelse @panic("literal text not given for directive"),
                .otherwise = .{ .literal = text orelse @panic("literal text not given for directive") },
                .tag_block = tag_block,
            };
        },
        .foreach,
        .split,
        .with,
        => {
            const end = switch (word) {
                .foreach => calcBody("For", noun, blob) orelse return null,
                .split => calcBody("Split", noun, blob) orelse return null,
                .with => calcBody("With", noun, blob) orelse return null,
                else => unreachable,
            };

            var name_end = (indexOfAnyPos(u8, noun, 1, " >") orelse noun.len);
            if (noun[name_end - 1] == '/') name_end -= 1;
            const name = noun[1..name_end];

            var exact: ?usize = null;
            var use: ?[]const u8 = null;

            var rem_attr: []const u8 = noun[1 + name.len ..];
            while (indexOfScalar(u8, rem_attr, '=') != null) {
                if (findAttribute(rem_attr)) |attr| {
                    if (eql(u8, attr.name, "exact")) {
                        exact = std.fmt.parseInt(usize, attr.value, 10) catch null;
                    } else if (eql(u8, attr.name, "use")) {
                        use = attr.value;
                    } else {
                        std.debug.print("attr {s}\n", .{attr.name});
                        unreachable;
                    }
                    rem_attr = rem_attr[attr.len..];
                } else |err| switch (err) {
                    error.AttrInvalid => break,
                    else => unreachable,
                }
            }

            const body_start = 1 + (indexOfPosLinear(u8, blob, 0, ">") orelse return null);
            const body_end: usize = end - @as(usize, if (word == .foreach) 6 else if (word == .with) 7 else 0);
            const tag_block_body = blob[body_start..body_end];
            return .{
                .verb = word,
                .noun = name,
                .otherwise = if (exact != null and use != null)
                    @panic("use & exact not implemented")
                else if (exact) |e|
                    .{ .exact = e }
                else if (use) |u|
                    .{ .template = getBuiltin(u) orelse @panic("built in missing") }
                else
                    .required,
                .tag_block = blob[0..end],
                .tag_block_body = tag_block_body,
                .tag_block_skip = body_start,
            };
        },
    }
}

fn findTag(blob: []const u8) ![]const u8 {
    return blob[0 .. 1 + (indexOf(u8, blob, ">") orelse return error.TagInvalid)];
}

const TAttr = struct {
    name: []const u8,
    value: []const u8,
    len: usize,
};

fn findAttribute(tag: []const u8) !TAttr {
    const equi = indexOfScalar(u8, tag, '=') orelse return error.AttrInvalid;
    const name = trim(u8, tag[0..equi], whitespace);
    var value = trim(u8, tag[equi + 1 ..], whitespace);

    var end: usize = equi + 1;
    while (end < tag.len and isWhitespace(tag[end])) end += 1;
    while (end < tag.len) {
        // TODO rewrite with tagged switch syntax
        switch (tag[end]) {
            '\n', '\r', '\t', ' ' => end += 1,
            '\'', '"' => |qut| {
                end += 1;
                while (end <= tag.len and tag[end] != qut) end += 1;
                if (end == tag.len) return error.AttrInvalid;
                if (tag[end] != qut) return error.AttrInvalid else end += 1;
                value = trim(u8, tag[equi + 1 .. end], whitespace.* ++ &[_]u8{ qut, '=', '<', '>', '/' });
                break;
            },
            else => {
                while (end < tag.len and !isWhitespace(tag[end])) end += 1;
            },
        }
    }
    return .{
        .name = name,
        .value = value,
        .len = end,
    };
}

test findAttribute {
    var attr = try findAttribute("type=\"usize\"");
    try std.testing.expectEqualDeep(TAttr{ .name = "type", .value = "usize", .len = 12 }, attr);
    attr = try findAttribute("type=\"isize\"");
    try std.testing.expectEqualDeep(TAttr{ .name = "type", .value = "isize", .len = 12 }, attr);
    attr = try findAttribute("type=\"?usize\"");
    try std.testing.expectEqualDeep(TAttr{ .name = "type", .value = "?usize", .len = 13 }, attr);
    attr = try findAttribute("default=\"text\"");
    try std.testing.expectEqualDeep(TAttr{ .name = "default", .value = "text", .len = 14 }, attr);
    attr = try findAttribute("default=\"text\" />");
    try std.testing.expectEqualDeep(TAttr{ .name = "default", .value = "text", .len = 14 }, attr);
}

fn validChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z' => true,
        '-', '_', '.', ':' => true,
        else => false,
    };
}

fn calcBody(comptime keyword: []const u8, noun: []const u8, blob: []const u8) ?usize {
    const open: *const [keyword.len + 2]u8 = "<" ++ keyword ++ " ";
    const close: *const [keyword.len + 3]u8 = "</" ++ keyword ++ ">";

    if (!startsWith(u8, blob, open)) @panic("error compiling template");
    var shape_i: usize = open.len;
    while (shape_i < blob.len and blob[shape_i] != '/' and blob[shape_i] != '>')
        shape_i += 1;
    switch (blob[shape_i]) {
        '/' => return if (blob.len <= shape_i + 1) null else shape_i + 2,
        '>' => {},
        else => return null,
    }

    var start = 1 + (indexOfPosLinear(u8, blob, 0, ">") orelse return null);
    var close_pos: usize = indexOfPosLinear(u8, blob, 0, close) orelse return null;
    // count is not comptime compliant while it uses indexOfPos increasing
    // backward branches. I've raised the quota, but complicated templates might
    // require a naive implementation
    var skip = count(u8, blob[start..close_pos], open);
    while (skip > 0) : (skip -= 1) {
        close_pos = indexOfPosLinear(u8, blob, close_pos + 1, close) orelse close_pos;
    }

    const end = close_pos + close.len;
    while (start < end and isWhitespace(blob[start])) : (start +|= 1) {}

    //while (endws > start and isWhitespace(blob[endws])) : (endws -|= 1) {}
    //endws += 1;

    var width: usize = 1;
    while (width < noun.len and validChar(noun[width])) {
        width += 1;
    }
    return end;
}

fn isStringish(t: type) bool {
    return switch (t) {
        []const u8, ?[]const u8 => true,
        else => false,
    };
}

pub fn doTyped(self: Directive, T: type, ctx: anytype, out: anytype) anyerror!void {
    //@compileLog(T);
    var local: [0xff]u8 = undefined;
    const realname = local[0..makeFieldName(self.noun, &local)];
    switch (@typeInfo(T)) {
        .@"struct" => {
            inline for (std.meta.fields(T)) |field| {
                if (comptime isStringish(field.type)) continue;
                switch (@typeInfo(field.type)) {
                    .pointer => {
                        if (eql(u8, field.name, realname)) {
                            const child = @field(ctx, field.name);
                            for (child) |each| {
                                switch (field.type) {
                                    []const []const u8 => {
                                        std.debug.assert(self.verb == .split);
                                        try out.writeAll(each);
                                        try out.writeAll("\n");
                                        //try out.writeAll( self.otherwise.blob.whitespace);
                                    },
                                    else => {
                                        std.debug.assert(self.verb == .foreach);
                                        try self.forEachTyped(@TypeOf(each), each, out);
                                    },
                                }
                            }
                        }
                    },
                    .optional => {
                        if (eql(u8, field.name, realname)) {
                            //@compileLog("optional for {s}\n", field.name, field.type, T);
                            const child = @field(ctx, field.name);
                            if (child) |exists| {
                                if (self.verb == .with)
                                    try self.withTyped(@TypeOf(exists), exists, out)
                                else
                                    try self.doTyped(@TypeOf(exists), exists, out);
                            }
                        }
                    },
                    .@"struct" => {
                        if (eql(u8, field.name, realname)) {
                            const child = @field(ctx, field.name);
                            std.debug.assert(self.verb == .build);
                            try self.withTyped(@TypeOf(child), child, out);
                        }
                    },
                    .int => |int| {
                        if (eql(u8, field.name, realname)) {
                            std.debug.assert(int.bits == 64);
                            try std.fmt.formatInt(@field(ctx, field.name), 10, .lower, .{}, out);
                        }
                    },
                    else => unreachable,
                }
            }
        },
        .int => {
            //std.debug.assert(int.bits == 64);
            try std.fmt.formatInt(ctx, 10, .lower, .{}, out);
        },
        else => |ERR| {
            //@compileLog(ERR);
            _ = ERR;
            unreachable;
        },
    }
}

pub fn forEachTyped(self: Directive, T: type, data: T, out: anytype) anyerror!void {
    var p = PageRuntime(T){
        .data = data,
        .template = .{
            .name = self.noun,
            .blob = trimLeft(u8, self.tag_block_body.?, whitespace),
        },
    };
    try p.format("", .{}, out);
}

fn getBuiltin(name: []const u8) ?Template {
    if (@inComptime()) {
        return template_data.findTemplate(name);
    }
    for (0..builtin.len) |i| {
        if (eql(u8, builtin[i].name, name)) {
            return builtin[i];
        }
    }
    return null;
}

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

pub fn formatTyped(d: Directive, comptime T: type, ctx: T, out: anytype) !void {
    switch (d.verb) {
        .variable => {
            if (d.html_type) |_| return d.doTyped(T, ctx, out);
            const noun = d.noun;
            const var_name = typeField(T, noun, ctx);
            if (var_name) |data_blob| {
                try out.writeAll(data_blob);
            } else {
                //if (DEBUG) std.debug.print("[missing var {s}]\n", .{noun.vari});
                switch (d.otherwise) {
                    .default => |str| try out.writeAll(str),
                    // Not really an error, just instruct caller to print original text
                    .required => return error.VariableMissing,
                    .delete => {},
                    .literal => unreachable,
                    .template => |template| {
                        if (T == usize) unreachable;
                        if (@typeInfo(T) != .@"struct") unreachable;
                        inline for (std.meta.fields(T)) |field| {
                            switch (@typeInfo(field.type)) {
                                .optional => |otype| {
                                    if (otype.child == []const u8) continue;

                                    var local: [0xff]u8 = undefined;
                                    const realname = local[0..makeFieldName(noun[1 .. noun.len - 5], &local)];
                                    if (std.mem.eql(u8, field.name, realname)) {
                                        if (@field(ctx, field.name)) |subdata| {
                                            var subpage = template.pageOf(otype.child, subdata);
                                            try subpage.format("{}", .{}, out);
                                        } else std.debug.print(
                                            "sub template data was null for {s}\n",
                                            .{field.name},
                                        );
                                    }
                                },
                                .@"struct" => {
                                    if (std.mem.eql(u8, field.name, noun)) {
                                        const subdata = @field(ctx, field.name);
                                        var subpage = template.pageOf(@TypeOf(subdata), subdata);
                                        try subpage.format("{}", .{}, out);
                                    }
                                },
                                else => {}, //@compileLog(field.type),
                            }
                        }
                    },
                    .exact => unreachable,
                    //inline for (std.meta.fields(T)) |field| {
                    //    if (eql(u8, field.name, noun)) {
                    //        const subdata = @field(ctx, field.name);
                    //        var page = template.pageOf(@TypeOf(subdata), subdata);
                    //        try page.format("{}", .{}, out);
                    //    }
                    //}
                }
            }
        },
        else => d.doTyped(T, ctx, out) catch unreachable,
    }
}

const Pages = @import("page.zig");
const PageRuntime = Pages.PageRuntime;
const Template = @import("Template.zig");

const std = @import("std");
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;
const indexOf = std.mem.indexOf;
const indexOfPosLinear = std.mem.indexOfPosLinear;
const indexOfAnyPos = std.mem.indexOfAnyPos;
const indexOfScalar = std.mem.indexOfScalar;
const indexOfScalarPos = std.mem.indexOfScalarPos;
const isUpper = std.ascii.isUpper;
const count = std.mem.count;
const isWhitespace = std.ascii.isWhitespace;
const trim = std.mem.trim;
const trimLeft = std.mem.trimLeft;
const whitespace = std.ascii.whitespace[0..];

const template_data = @import("builtins.zig");
const dynamic = &template_data.dynamic;
const builtin = template_data.builtin;
const makeFieldName = template_data.makeFieldName;
