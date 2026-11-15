verb: Verb,
noun: []const u8,
otherwise: Otherwise,
bytes: []const u8,
block_body: ?[]const u8 = null,
block_skip: ?usize = null,
base_type: ?BasicType = null,
scope: Scope = .local,

const Directive = @This();

pub const Otherwise = union(enum) {
    required: void,
    delete: void,
    default: []const u8,
    template: *const Template,
    exact: usize,
    literal: []const u8,
    //page: type,

    pub fn fromTag(tag: []const u8, map: *const Attributes.Map) Otherwise {
        if (map.get(.default)) |str|
            return .{ .default = str };

        if (findPos(u8, tag, 0, " ornull")) |_|
            return .delete;

        if (map.get(.@"enum")) |str|
            return .{ .literal = str };

        if (map.get(.type)) |str| {
            if (BasicType.fromStr(str)) |basic| {
                if (basic.isOpt())
                    return .delete;
            } else |_| {}
        }

        return .required;
    }
};

pub const Verb = enum {
    build,
    directive,
    foreach,
    split,
    variable,
    with,
    @"switch",
    case,

    pub fn fromStr(str: []const u8) ?Verb {
        if (eql(u8, str, "For")) {
            return .foreach;
        } else if (eql(u8, str, "Directive")) {
            return .directive;
        } else if (eql(u8, str, "Split")) {
            return .split;
        } else if (eql(u8, str, "With")) {
            return .with;
        } else if (eql(u8, str, "Build")) {
            return .build;
        } else if (eql(u8, str, "Switch")) {
            return .@"switch";
        } else if (eql(u8, str, "Case")) {
            return .case;
        } else return null;
    }
};

pub const BasicType = enum {
    usize,
    isize,
    @"?usize",
    @"enum",
    // Custom verse types
    /// input is i64 as unix epoch output: human readable relative time string.
    humanize,
    /// alias for antibiotic
    abx,
    /// input is unsanitized text output: text with replaced html entities
    antibiotic,
    /// the inverse of antibiotic, caller guarantees the provided slice is safe
    safe,
    /// raw markdown translated to html
    markdown,
    /// helper that will turn path segments into the shortest uri
    uri,

    pub fn fromStr(s: []const u8) !BasicType {
        const E = @typeInfo(BasicType).@"enum";
        inline for (E.field_names, E.field_values) |n, v| {
            if (eql(u8, n, s)) {
                return @fromBackingInt(@intCast(v));
            }
        }
        return error.InvalidType;
    }

    pub fn isOpt(kt: BasicType) bool {
        return @tagName(kt)[0] == '?';
    }

    pub fn format(tt: BasicType, w: *Writer) !void {
        return tt.format2("[TODO enum]", w);
    }

    pub fn format2(tt: BasicType, enm: []const u8, w: *Writer) !void {
        return switch (tt) {
            .@"enum" => try w.writeAll(enm),
            .usize,
            .isize,
            .@"?usize",
            => try w.writeAll(@tagName(tt)),
            .humanize => try w.writeAll("i64"),
            .abx, .antibiotic => try w.writeAll("Abx"),
            .safe => try w.writeAll("[]const u8"),
            .markdown => try w.writeAll("Markdown"),
            .uri => try w.writeAll("Uri.Builder"),
        };
    }
};

pub const Scope = enum {
    local,
    global,
};

pub fn init(str: []const u8) ?Directive {
    if (str.len < 2) return null;
    if (!isUpper(str[1]) and str[1] != '_') return null;
    const tag = findTag(str) catch return null;
    const verb = tag[1 .. findAnyPos(u8, tag, 1, " /") orelse tag.len - 1];

    if (verb.len == tag.len - 2) {
        if (initNoun(verb, tag)) |noun| {
            return noun;
        } else unreachable;
    }

    const noun = tag[verb.len + 1 .. tag.len - 1];

    return initVerb(verb, noun, str) orelse initNoun(verb, tag);
}

fn initNoun(noun: []const u8, tag: []const u8) ?Directive {
    if (noun[0] == '_') @panic("Template Directives must not start with _");
    const tag_map = Attributes.find(tag[noun.len + 1 .. tag.len - 1]) catch return null;
    const otherwise: Otherwise = .fromTag(tag, &tag_map);
    const base: ?BasicType = if (tag_map.get(.type)) |str|
        BasicType.fromStr(str) catch null
    else
        null;

    return .{
        .verb = .variable,
        .noun = noun,
        .otherwise = otherwise,
        .base_type = base,
        .bytes = tag,
    };
}

pub const TemplateDirective = struct {};

pub fn initVerb(verb: []const u8, noun: []const u8, blob: []const u8) ?Directive {
    switch (Verb.fromStr(verb) orelse return null) {
        .variable => unreachable,
        .build => {
            const b_noun = noun[1..(findScalarPos(u8, noun, 1, ' ') orelse return null)];
            const tail = noun[b_noun.len + 1 ..];
            const b_html = tail[1..(findScalarPos(u8, tail, 2, ' ') orelse return null)];
            return .{
                .verb = .build,
                .noun = b_noun,
                .otherwise = .{ .template = template_data.findTemplate(b_html) },
                .bytes = blob[0 .. verb.len + 2 + noun.len],
            };
        },
        .directive => {
            const end = calcBody("Directive", noun, blob) orelse return null;
            const body_end: usize = end;
            const tag_block_body = blob[0..body_end];
            var end_idx: usize = verb.len + 2 + noun.len;
            while (end_idx < blob.len and (blob[end_idx] == ' ' or blob[end_idx] == '\n')) end_idx += 1;
            const tag_block = blob[0..end_idx];

            const tag_map = Attributes.find(tag_block_body["<Directive ".len..body_end]) catch return null;

            const name: ?[]const u8 = tag_map.get(.name);
            const text: ?[]const u8 = tag_map.get(.text);

            return Directive{
                .verb = .directive,
                .noun = name orelse @panic("literal text not given for directive"),
                .otherwise = .{ .literal = text orelse @panic("literal text not given for directive") },
                .bytes = tag_block,
            };
        },
        .foreach,
        .split,
        .with,
        => |verb_tag| {
            const end = switch (verb_tag) {
                .foreach => calcBody("For", noun, blob) orelse return null,
                .split => calcBody("Split", noun, blob) orelse return null,
                .with => calcBody("With", noun, blob) orelse return null,
                else => unreachable,
            };

            var name_end = (findAnyPos(u8, noun, 1, " >") orelse noun.len);
            if (noun[name_end - 1] == '/') name_end -= 1;
            const name = noun[1..name_end];

            const tag_map = Attributes.find(noun[1 + name.len ..]) catch return null;
            const exact: ?usize = if (tag_map.get(.exact)) |e| std.fmt.parseInt(usize, e, 10) catch null else null;
            const use: ?[]const u8 = tag_map.get(.use);
            const scope: []const u8 = tag_map.get(.scope) orelse "local";

            const body_start = 1 + (findPosLinear(u8, blob, 0, ">") orelse return null);
            const body_end: usize = end - @as(usize, if (verb_tag == .foreach) 6 else if (verb_tag == .with) 7 else 0);
            const tag_block_body = blob[body_start..body_end];
            return .{
                .verb = verb_tag,
                .noun = name,
                .otherwise = if (exact != null and use != null)
                    @panic("use & exact not implemented")
                else if (exact) |e|
                    .{ .exact = e }
                else if (use) |u|
                    .{ .template = template_data.findTemplate(u) }
                else
                    .required,
                .bytes = blob[0..end],
                .block_body = tag_block_body,
                .block_skip = body_start,
                .scope = if (eql(u8, scope, "global")) .global else .local,
            };
        },
        .@"switch", .case => |verb_tag| {
            const end = switch (verb_tag) {
                .@"switch" => calcBody("Switch", noun, blob) orelse return null,
                .case => calcBody("Case", noun, blob) orelse return null,
                else => unreachable,
            };

            const name_end = (findAnyPos(u8, noun, 1, " >") orelse noun.len);
            if (noun[name_end - 1] == '/') unreachable;
            const name = noun[1..name_end];

            const body_start = 1 + (findPosLinear(u8, blob, 0, ">") orelse return null);
            const body_end: usize = end - @as(usize, if (verb_tag == .@"switch")
                9
            else if (verb_tag == .case)
                7
            else
                0);
            const tag_block_body = blob[body_start..body_end];
            return .{
                .verb = verb_tag,
                .noun = name,
                .otherwise = .required,
                .bytes = blob[0..end],
                .block_body = tag_block_body,
                .block_skip = body_start,
            };
        },
    }
}

fn findTag(blob: []const u8) ![]const u8 {
    return blob[0 .. 1 + (findScalarPos(u8, blob, 0, '>') orelse return error.TagInvalid)];
}

pub const Attributes = struct {
    pub const Map = std.EnumMap(Key, []const u8);

    pub const Key = enum {
        /// adds the specified string to the generate enum
        @"enum",
        /// Provides default text for <Tags>
        default,
        /// Use a comptime known length and array
        exact,
        /// Used in <Directives>, specifies the name for the following tags
        name,
        /// Used in <Directives>, specifies the text returned for the given/active tag
        text,
        /// Use supported zig type
        type,
        /// Use a builtin template for the "body" of this tag
        use,
        /// Defines the scope for the tag body, either global or local
        scope,

        pub fn fromStr(str: []const u8) !Key {
            const E = @typeInfo(Key).@"enum";
            inline for (E.field_names, E.field_values) |name, val| {
                if (eql(u8, name, str)) return @fromBackingInt(@intCast(val));
            }
            return error.InvalidKey;
        }
    };

    const State = enum { start, skip, key, eql, val_raw, val_sqt, val_dqt, save };

    pub fn find(tag: []const u8) !Map {
        var map: Map = .init(.{});
        var idx: usize = 0;
        var key: ?Key = null;
        var val: ?[]const u8 = null;
        parse: switch (State.skip) {
            .start => if (findScalarPos(u8, tag, idx, '=')) |_| {
                while (idx < tag.len) switch (tag[idx]) {
                    ' ' => idx += 1,
                    'a'...'z' => continue :parse .key,
                    else => continue :parse .skip,
                } else break :parse;
            } else break :parse,
            .skip => while (idx < tag.len) switch (tag[idx]) {
                'a'...'z' => continue :parse .start,
                else => idx += 1,
            } else break :parse,
            .key => {
                const start = idx;
                while (idx < tag.len) switch (tag[idx]) {
                    'a'...'z' => idx += 1,
                    else => {
                        key = try .fromStr(tag[start..idx]);
                        if (tag[idx] != '=') idx += 1;
                        continue :parse .eql;
                    },
                } else break :parse; // = not found
            },
            .eql => while (idx + 1 < tag.len) switch (tag[idx]) {
                ' ' => idx += 1,
                '=' => {
                    idx += 1;
                    while (idx + 1 < tag.len) switch (tag[idx]) {
                        ' ' => idx += 1,
                        '"' => continue :parse .val_dqt,
                        '\'' => continue :parse .val_sqt,
                        '0'...'9', 'A'...'Z', 'a'...'z' => continue :parse .val_raw,
                        else => return error.AttrParseError,
                    };
                },
                else => return error.AttrParseError,
            } else return error.AttrParseError,
            .val_raw => {
                const start = idx;
                while (idx < tag.len) switch (tag[idx]) {
                    '0'...'9', '?'...'Z', 'a'...'z', '#'...'&', '_', '.', '-' => idx += 1,
                    else => break,
                };
                val = tag[start..idx];
                continue :parse .save;
            },
            .val_sqt => {
                idx += 1;
                const start = idx;
                while (idx < tag.len) switch (tag[idx]) {
                    else => idx += 1,
                    '\n' => return error.AttrParseError,
                    '\'' => {
                        if (tag[idx - 1] == '\\') return error.AttrParseErrorDetected;
                        val = tag[start..idx];
                        idx += 1;
                        continue :parse .save;
                    },
                } else return error.AttrParseError;
            },
            .val_dqt => {
                idx += 1;
                const start = idx;
                while (idx < tag.len) switch (tag[idx]) {
                    else => idx += 1,
                    '\n' => return error.AttrParseError,
                    '"' => {
                        if (tag[idx - 1] == '\\') return error.AttrParseErrorDetected;
                        val = tag[start..idx];
                        idx += 1;
                        continue :parse .save;
                    },
                } else return error.AttrParseError;
            },
            .save => {
                if (map.get(key.?)) |_| return error.DuplicateAttr;
                map.put(key.?, val.?);
                key = null;
                val = null;
                if (idx + 3 < tag.len) continue :parse .start;
                break :parse;
            },
        }
        return map;
    }

    test find {
        var map = try find(
            \\type=usize
        );
        try std.testing.expectEqualStrings(map.get(.type).?, "usize");

        map = try find(
            \\type="isize"
        );
        try std.testing.expectEqualStrings(map.get(.type).?, "isize");

        map = try find(
            \\type="?usize"
        );
        try std.testing.expectEqualStrings(map.get(.type).?, "?usize");

        map = try find(
            \\type="humanize" orelse
        );
        try std.testing.expectEqualStrings(map.get(.type).?, "humanize");

        map = try find(
            \\default = custom
        );
        try std.testing.expectEqualStrings(map.get(.default).?, "custom");

        map = try find(
            \\default="text"
        );
        try std.testing.expectEqualStrings(map.get(.default).?, "text");

        map = try find(
            \\default="text" />
        );
        try std.testing.expectEqualStrings(map.get(.default).?, "text");

        const err = find(
            \\default="t" default="tx" default="txt" default="text" />
        );
        try std.testing.expectError(error.DuplicateAttr, err);

        map = try find(
            \\name="txt" default="default" text="name" enum="blerg" />
        );
        try std.testing.expectEqualStrings(map.get(.default).?, "default");
        try std.testing.expectEqualStrings(map.get(.@"enum").?, "blerg");
        try std.testing.expectEqualStrings(map.get(.name).?, "txt");
        try std.testing.expectEqualStrings(map.get(.text).?, "name");

        map = try find(
            \\ enum='bah!!' />
        );
        try std.testing.expectEqualStrings(map.get(.@"enum").?, "bah!!");
        map = try find(
            \\ text="name" enum='bah!!' />
        );
        try std.testing.expectEqualStrings(map.get(.@"enum").?, "bah!!");
        try std.testing.expectEqualStrings(map.get(.text).?, "name");
        map = try find(
            \\ default=default text="name" enum='bah!!' />
        );
        try std.testing.expectEqualStrings(map.get(.default).?, "default");
        try std.testing.expectEqualStrings(map.get(.@"enum").?, "bah!!");
        try std.testing.expectEqualStrings(map.get(.text).?, "name");
        map = try find(
            \\name="'txt'" default=default text="name" enum='bah!!' />
        );
        try std.testing.expectEqualStrings(map.get(.default).?, "default");
        try std.testing.expectEqualStrings(map.get(.@"enum").?, "bah!!");
        try std.testing.expectEqualStrings(map.get(.name).?, "'txt'");
        try std.testing.expectEqualStrings(map.get(.text).?, "name");
    }
};

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

    var start = 1 + (findPosLinear(u8, blob, 0, ">") orelse return null);
    var close_pos: usize = findPosLinear(u8, blob, 0, close_tag) orelse return null;
    // count is not comptime compliant while it uses findPos increasing
    // backward branches. I've raised the quota, but complicated templates might
    // require a naive implementation
    var skip: usize = 0;
    var blocks = count(u8, blob[start..close_pos], open_tag);
    while (skip < blocks) : (skip += 1) {
        close_pos = findPosLinear(u8, blob, close_pos + 1, close_tag) orelse close_pos;
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

fn typeField(T: type, name: []const u8, data: T) ?[]const u8 {
    if (@typeInfo(T) != .@"struct") return null;
    var local: [0xff]u8 = undefined;
    const realname = nameFieldSlice(name, &local);
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

pub fn formatTyped(d: Directive, comptime T: type, ctx: T, w: *std.Io.Writer) !void {
    switch (T) {
        Abx.Html => try ctx.format(w),
        Abx => try ctx.format(w),
        ?Abx.Html => if (ctx) |c| try c.format(w),
        ?Abx => if (ctx) |c| try c.format(w),
        else => switch (d.verb) {
            .variable => {
                if (d.base_type) |_| {
                    var local: [0xff]u8 = undefined;
                    const realname = d.nameField(&local);
                    switch (@typeInfo(T)) {
                        .@"struct" => inline for (std.meta.fields(T)) |field| {
                            if (comptime isStringish(field.type)) continue;
                            switch (@typeInfo(field.type)) {
                                .pointer => if (eql(u8, field.name, realname)) {
                                    const child = @field(ctx, field.name);
                                    for (child) |each| switch (field.type) {
                                        []const []const u8 => {
                                            std.debug.assert(d.verb == .split);
                                            try w.writeAll(each);
                                            try w.writeAll("\n");
                                        },
                                        else => comptime unreachable,
                                    };
                                },
                                else => comptime unreachable,
                            }
                        },
                        .int => try w.print("{d}", .{ctx}),
                        else => comptime unreachable,
                    }
                    return;
                }
                const noun = d.noun;
                const var_name = typeField(T, noun, ctx);
                if (var_name) |data_blob| {
                    try w.writeAll(data_blob);
                } else switch (d.otherwise) {
                    .default => |str| try w.writeAll(str),
                    // Not really an error, just instruct caller to print original text
                    .required => {},
                    .delete => {},
                    .literal => unreachable,
                    .template => |template| {
                        if (T == usize) unreachable;
                        if (@typeInfo(T) != .@"struct") unreachable;
                        inline for (std.meta.fields(T)) |field| switch (@typeInfo(field.type)) {
                            .optional => |otype| {
                                if (otype.child == []const u8) continue;

                                var local: [0xff]u8 = undefined;
                                const realname = nameFieldSlice(noun[1 .. noun.len - 5], &local);
                                if (std.mem.eql(u8, field.name, realname)) {
                                    if (@field(ctx, field.name)) |subdata| {
                                        var subpage = template.pageOf(otype.child, subdata);
                                        try subpage.format("{}", .{}, w);
                                    } else log.err(
                                        "sub template data was null for {s}\n",
                                        .{field.name},
                                    );
                                }
                            },
                            .@"struct" => if (std.mem.eql(u8, field.name, noun)) {
                                const subdata = @field(ctx, field.name);
                                var subpage = template.pageOf(@TypeOf(subdata), subdata);
                                try subpage.format("{}", .{}, w);
                            },
                            else => {}, //@compileLog(field.type),
                        };
                    },
                    .exact => unreachable,
                }
            },
            else => {
                var local: [0xff]u8 = undefined;
                const realname = d.nameField(&local);
                switch (@typeInfo(T)) {
                    .int => try w.print("{d}", .{ctx}),
                    .@"struct" => inline for (std.meta.fields(T)) |field| {
                        if (comptime isStringish(field.type)) continue;
                        switch (@typeInfo(field.type)) {
                            .pointer => if (eql(u8, field.name, realname)) {
                                const child = @field(ctx, field.name);
                                for (child) |each| switch (field.type) {
                                    []const []const u8 => {
                                        std.debug.assert(d.verb == .split);
                                        try w.writeAll(each);
                                        try w.writeAll("\n");
                                        //try out.writeAll( self.otherwise.blob.whitespace);
                                    },
                                    else => comptime unreachable,
                                };
                            },
                            else => comptime unreachable,
                        }
                    },
                    else => comptime unreachable,
                }
            },
        },
    }
}

fn intToWord(in: u8) []const u8 {
    return switch (in) {
        '0' => "Zero",
        '1' => "One",
        '2' => "Two",
        '3' => "Three",
        '4' => "Four",
        '5' => "Five",
        '6' => "Six",
        '7' => "Seven",
        '8' => "Eight",
        '9' => "Nine",
        else => unreachable,
    };
}

pub fn nameStruct(d: Directive, buffer: []u8) []u8 {
    return Template.nameSlice(d.noun, buffer);
}

pub fn nameStructAlloc(d: Directive, a: Allocator) ![]u8 {
    var sn_b: [0x200]u8 = undefined;
    const name = d.nameStruct(&sn_b);
    return try a.dupe(u8, name);
}

pub fn nameFieldAlloc(d: Directive, a: Allocator) ![]u8 {
    var fn_b: [0x200]u8 = undefined;
    const name = try d.nameField(&fn_b);
    return try a.dupe(u8, name);
}

pub fn nameField(d: Directive, buffer: []u8) ![]u8 {
    return nameFieldSlice(d.noun, buffer);
}

pub fn nameFieldSlice(in: []const u8, buffer: []u8) ![]u8 {
    var i: usize = 0;
    for (in) |chr| {
        if (i >= buffer.len) return error.OutOfSpace;
        switch (chr) {
            'a'...'z' => {
                buffer[i] = chr;
                i += 1;
            },
            'A'...'Z' => {
                if (i != 0) {
                    buffer[i] = '_';
                    i += 1;
                }
                buffer[i] = chr | 0b0010_0000;
                i += 1;
            },
            inline '0'...'9' => |x| {
                for (intToWord(x)) |cchr| {
                    buffer[i] = cchr;
                    i += 1;
                }
            },
            '-', '_', '.' => {
                buffer[i] = '_';
                i += 1;
            },
            else => {},
        }
    }

    return buffer[0..i];
}

pub fn fmtField(d: Directive, w: *Writer) !void {
    var b: [0x200]u8 = undefined;
    try w.print("{s}", .{d.nameField(&b) catch "[Name Too Long]"});
}

pub fn typeFmt(d: Directive, struct_name: []const u8, comptime default_str_type: []const u8) TypeFormatter {
    return .{
        .d = d,
        .struct_name = struct_name,
        .default_str = default_str_type,
    };
}

pub const TypeFormatter = struct {
    d: Directive,
    struct_name: []const u8,
    default_str: []const u8,

    pub fn format(f: TypeFormatter, w: *Writer) !void {
        const basic_type = f.default_str;
        switch (f.d.otherwise) {
            .required => if (f.d.base_type) |ht|
                try ht.format2(f.struct_name, w)
            else
                try w.writeAll(basic_type),
            .exact => unreachable,
            .template => try w.print("?{s}", .{f.struct_name}),
            .default => |default| if (f.d.base_type) |ht|
                try w.print("{f} = {s}", .{ ht, default })
            else
                try w.print("{f}", .{f.d.fmtWithDefault(verse_buildopts.abx_required)}),
            .delete => if (f.d.base_type) |ht|
                try w.print("{f}", .{ht})
            else
                try w.print("?{s} = null", .{basic_type}),
            .literal => if (f.d.base_type) |ht|
                try ht.format2(f.struct_name, w)
            else
                try w.writeAll(f.struct_name),
        }
    }
};

pub fn fmtWithDefault(d: Directive, abx: bool) FormatDefault {
    return .init(d, abx);
}

pub const FormatDefault = struct {
    name: []const u8,
    default: []const u8,
    abx: bool,

    pub fn init(d: Directive, abx: bool) FormatDefault {
        return .{
            .name = std.mem.cutSuffix(u8, d.noun, ".html") orelse d.noun,
            .default = d.otherwise.default,
            .abx = abx,
        };
    }

    pub fn format(f: FormatDefault, w: *Writer) !void {
        if (f.abx) {
            try w.print("Abx = .safe(\"{s}\")", .{f.default});
        } else {
            try w.print("[]const u8 = \"{s}\"", .{f.default});
        }
    }
};

test Directive {
    _ = &Attributes;
    _ = &Otherwise;
    _ = &BasicType;
    _ = &Verb;
    _ = &TypeFormatter;
    _ = &FormatDefault;
}

const Template = @import("Template.zig");
const Abx = @import("Antibiotic");
const Allocator = std.mem.Allocator;

const std = @import("std");
const Writer = std.Io.Writer;
const eql = std.mem.eql;
const startsWith = std.mem.startsWith;
const findPos = std.mem.findPos;
const findPosLinear = std.mem.findPosLinear;
const findAnyPos = std.mem.findAnyPos;
const findScalarPos = std.mem.findScalarPos;
const count = std.mem.count;
const trim = std.mem.trim;
const isUpper = std.ascii.isUpper;
const whitespace = std.ascii.whitespace[0..];
const isWhitespace = std.ascii.isWhitespace;

const template_data = @import("builtins.zig");
const verse_buildopts = @import("verse_buildopts");
const log = std.log.scoped(.verse_directive);
