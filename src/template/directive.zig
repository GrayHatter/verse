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
    humanize,

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
            .humanize,
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

    const tag_map = findAttrs(tag[noun.len + 1 .. tag.len - 1]) catch return null;
    //const directive: ?[]const u8 = if (tag_map.get(.text)) |ht| try .fromStr(ht) else null;
    const default_str: ?[]const u8 = tag_map.get(.default);
    const h_type: ?HtmlType, const tag_name: ?[]const u8 = if (tag_map.get(.@"enum")) |ht|
        .{ .@"enum", ht }
    else if (tag_map.get(.type)) |ht|
        .{
            HtmlType.fromStr(ht) catch null, null,
        }
    else
        .{ null, null };

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

            const tag_map = findAttrs(tag_block_body["<Directive ".len..body_end]) catch return null;

            const name: ?[]const u8 = tag_map.get(.name);
            const text: ?[]const u8 = tag_map.get(.text);

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

            const tag_map = findAttrs(noun[1 + name.len ..]) catch return null;
            const exact: ?usize = if (tag_map.get(.exact)) |e| std.fmt.parseInt(usize, e, 10) catch null else null;
            const use: ?[]const u8 = tag_map.get(.use);

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

pub const TagAttribute = enum {
    @"enum",
    default,
    exact,
    name,
    text,
    type,
    use,
};

pub const TagAttrMap = std.EnumMap(TagAttribute, []const u8);

fn findAttrs(src_tag: []const u8) !TagAttrMap {
    var map: TagAttrMap = .init(.{});
    var tag = src_tag;
    while (indexOfScalar(u8, tag, '=')) |eq_idx| {
        const name = trim(u8, tag[0..eq_idx], whitespace);
        var value = trim(u8, tag[eq_idx + 1 ..], whitespace);

        var end: usize = eq_idx + 1;
        while (end < tag.len and isWhitespace(tag[end])) end += 1;
        while (end < tag.len) {
            // TODO rewrite with tagged switch syntax
            switch (tag[end]) {
                '\n', '\r', '\t', ' ' => end += 1,
                '\'', '"' => |qut| {
                    end += 1;
                    while (end < tag.len and tag[end] != qut) end += 1;
                    if (end == tag.len) return error.AttrInvalid;
                    if (tag[end] != qut) return error.AttrInvalid else end += 1;
                    value = trim(u8, tag[eq_idx + 1 .. end], whitespace);
                    value = trim(u8, tag[eq_idx + 1 .. end], &[1]u8{qut});
                    break;
                },
                else => while (end < tag.len and !isWhitespace(tag[end])) : (end += 1) {},
            }
        }
        tag = tag[end..];

        inline for (@typeInfo(TagAttribute).@"enum".fields) |f| {
            if (eql(u8, f.name, name)) {
                map.put(@enumFromInt(f.value), value);
                break;
            }
        } else @panic("unreachable name");
    }
    return map;
}

test findAttrs {
    var map = try findAttrs("type=\"usize\"");
    try std.testing.expectEqualStrings(map.get(.type).?, "usize");
    map = try findAttrs("type=\"isize\"");
    try std.testing.expectEqualStrings(map.get(.type).?, "isize");
    map = try findAttrs("type=\"?usize\"");
    try std.testing.expectEqualStrings(map.get(.type).?, "?usize");
    map = try findAttrs("type=\"humanize\"");
    try std.testing.expectEqualStrings(map.get(.type).?, "humanize");
    map = try findAttrs("default=\"text\"");
    try std.testing.expectEqualStrings(map.get(.default).?, "text");
    map = try findAttrs("default=\"text\" />");
    try std.testing.expectEqualStrings(map.get(.default).?, "text");
    map = try findAttrs("default=\"t\" default=\"tx\" default=\"txt\" default=\"text\" />");
    try std.testing.expectEqualStrings(map.get(.default).?, "text");
    map = try findAttrs("name=\"txt\" default=\"default\" text=\"name\" enum=\"blerg\" />");
    try std.testing.expectEqualStrings(map.get(.default).?, "default");
    try std.testing.expectEqualStrings(map.get(.@"enum").?, "blerg");
    // Yes, they're reversed intentionally
    try std.testing.expectEqualStrings(map.get(.name).?, "txt");
    try std.testing.expectEqualStrings(map.get(.text).?, "name");
}

fn validChar(c: u8) bool {
    return switch (c) {
        'A'...'Z', 'a'...'z' => true,
        '-', '_', '.', ':' => true,
        else => false,
    };
}

fn calcBody(comptime keyword: []const u8, noun: []const u8, blob: []const u8) ?usize {
    const open_tag = "<" ++ keyword ++ " ";
    const close_tag = "</" ++ keyword ++ ">";

    if (!startsWith(u8, blob, open_tag)) @panic("error compiling template");
    var shape_i: usize = open_tag.len;
    while (shape_i < blob.len and blob[shape_i] != '/' and blob[shape_i] != '>')
        shape_i += 1;
    switch (blob[shape_i]) {
        '/' => return if (blob.len <= shape_i + 1) null else shape_i + 2,
        '>' => {},
        else => return null,
    }

    var start = 1 + (indexOfPosLinear(u8, blob, 0, ">") orelse return null);
    var close_pos: usize = indexOfPosLinear(u8, blob, 0, close_tag) orelse return null;
    // count is not comptime compliant while it uses indexOfPos increasing
    // backward branches. I've raised the quota, but complicated templates might
    // require a naive implementation
    var skip: usize = 0;
    var blocks = count(u8, blob[start..close_pos], open_tag);
    while (skip < blocks) : (skip += 1) {
        close_pos = indexOfPosLinear(u8, blob, close_pos + 1, close_tag) orelse close_pos;
        blocks = count(u8, blob[start..close_pos], open_tag);
    }

    const end = close_pos + close_tag.len;
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
