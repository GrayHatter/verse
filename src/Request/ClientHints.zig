agent: ?Agent,
mobile: ?bool,
platform: ?Platform,

const ClientHints = @This();

pub const empty: ClientHints = .{
    .agent = null,
    .mobile = null,
    .platform = null,
};

pub const Platform = union(enum) {
    windows: []const u8,
    linux: []const u8,
    macos: []const u8,
    other: []const u8,

    pub fn init(str: []const u8) Platform {
        return .{ .other = str };
    }
};

pub const Agent = struct {
    count: usize,
    bytes: []const u8,
    idx: usize = 0,

    pub fn init(ch_ua: []const u8) Agent {
        return .{
            .count = std.mem.countScalar(u8, ch_ua, ','), // lol, sorry!
            .bytes = ch_ua,
        };
    }

    pub const Pair = struct {
        name: []const u8,
        version: Version,
    };

    pub const Version = struct {
        major: usize,
        minor: usize,
        patch: usize,
        rev: usize,

        pub fn maj(m: usize) Version {
            return .{
                .major = m,
                .minor = 0,
                .patch = 0,
                .rev = 0,
            };
        }

        pub const zero: Version = .{
            .major = 0,
            .minor = 0,
            .patch = 0,
            .rev = 0,
        };
    };

    fn parseName(str: []const u8) ![]const u8 {
        var idx: usize = 0;
        while (idx < str.len and (str[idx] == ' ' or str[idx] == ',')) idx += 1;
        if (idx >= str.len) return error.Empty;
        switch (str[idx]) {
            '"' => {
                idx += 1;
                if (findScalarPos(u8, str, idx, '"')) |pos| {
                    if (pos + 1 < str.len and str[pos + 1] == ';') {
                        return str[idx..pos];
                    } else return error.Invalid;
                } else return error.Invalid;
            },
            else => {
                if (findScalarPos(u8, str, idx, ';')) |pos| {
                    return str[idx..pos];
                } else return error.Invalid;
            },
        }
    }

    fn parseVer(str: []const u8) struct { usize, Version } {
        var idx: usize = 0;
        var ver: Version = .zero;
        if (find(u8, str, ";v=\"")) |found| {
            if (findScalarPos(u8, str, found + 4, '"')) |end| {
                ver.major = std.fmt.parseInt(usize, str[found + 4 .. end], 0) catch 0;
                idx = end;
            } else idx = found;
        }
        return .{
            if (findScalarPos(u8, str, idx + 1, ',')) |end| end + 1 else str.len,
            ver,
        };
    }

    pub fn next(a: *Agent) ?Pair {
        const name = parseName(a.bytes[a.idx..]) catch return null;
        const skip = name.ptr - a.bytes[a.idx..].ptr;
        a.idx += skip + name.len;
        const ver_idx, const ver = parseVer(a.bytes[a.idx..]);
        a.idx += ver_idx;
        if (startsWith(u8, name, "Not") and endsWith(u8, name, "Brand"))
            return a.next();
        return .{ .name = name, .version = ver };
    }

    pub fn peek(a: *Agent) ?Pair {
        const old = a.idx;
        defer a.idx = old;
        return a.next();
    }
};

pub fn init(h: *const Headers) ClientHints {
    return .{
        .agent = if (h.getCustomValue("HTTP_SEC_CH_UA")) |v| .init(v) else |_| null,
        .mobile = if (h.getCustomValue("HTTP_SEC_CH_MOBILE")) |v| std.mem.eql(u8, v, "?1") else |_| null,
        .platform = if (h.getCustomValue("HTTP_SEC_CH_PLATFORM")) |v| .init(v) else |_| null,
    };
}

test {
    _ = &std.testing.refAllDecls(@This());
}

test Agent {
    const spam =
        \\"Google Chrome";v="141", "Not?A_Brand";v="8", "Chromium";v="141"
    ;
    var agent: Agent = .init(spam);
    try std.testing.expectEqualDeep(Agent{ .count = 2, .bytes = spam }, agent);
    try std.testing.expectEqualDeep(Agent.Pair{ .name = "Google Chrome", .version = .maj(141) }, agent.next().?);
    try std.testing.expectEqualDeep(Agent.Pair{ .name = "Chromium", .version = .maj(141) }, agent.next().?);
    try std.testing.expectEqualDeep(@as(?Agent.Pair, null), agent.next());
}

const Headers = @import("../Headers.zig");
const std = @import("std");
const findScalarPos = std.mem.findScalarPos;
const find = std.mem.find;
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
