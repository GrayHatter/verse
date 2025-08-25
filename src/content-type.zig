base: ContentBase,
parameter: ?CharSet = null,

const ContentType = @This();

pub const @"text/plain": ContentType = .{ .base = .{ .text = .plain } };
pub const @"text/html": ContentType = .{ .base = .{ .text = .html }, .parameter = .@"utf-8" };
pub const @"application/json": ContentType = .{ .base = .{ .application = .json }, .parameter = .@"utf-8" };

pub const html: ContentType = .@"text/html";
pub const json: ContentType = .@"application/json";

pub const default: ContentType = .{
    .base = .{ .text = .html },
    .parameter = .@"utf-8",
};

pub const ContentBase = union(Base) {
    application: Application,
    audio: Audio,
    font: Font,
    image: Image,
    text: Text,
    video: Video,
    /// Multipart types
    multipart: MultiPart,
    message: MultiPart,

    pub fn string(comptime cb: ContentBase) [:0]const u8 {
        return switch (cb) {
            inline else => |tag| tag.string(),
        };
    }

    test "ContentBase.string" {
        try std.testing.expectEqualStrings(
            "application/json",
            (ContentBase{ .application = .json }).string(),
        );

        try std.testing.expectEqualStrings(
            "font/ttf",
            (ContentBase{ .font = .ttf }).string(),
        );
    }
};

pub const Base = enum {
    // Basic types
    application,
    audio,
    font,
    image,
    text,
    video,
    /// Multipart types
    multipart,
    message,

    pub fn isMultipart(b: Base) bool {
        return switch (b) {
            .multipart, .message => true,
            else => false,
        };
    }
};

pub const Application = enum {
    @"x-www-form-urlencoded",
    @"x-git-upload-pack-request",
    @"octet-stream",
    json,

    pub fn string(comptime app: Application) [:0]const u8 {
        return switch (app) {
            inline else => |r| "application/" ++ @tagName(r),
        };
    }

    test "Application.string" {
        try std.testing.expectEqualStrings(
            "application/octet-stream",
            Application.@"octet-stream".string(),
        );
    }
};

pub const Audio = enum {
    ogg,

    pub fn string(comptime app: Audio) [:0]const u8 {
        return switch (app) {
            inline else => |r| "audio/" ++ @tagName(r),
        };
    }
};

pub const Font = enum {
    otf,
    ttf,
    woff,

    pub fn string(comptime app: Font) [:0]const u8 {
        return switch (app) {
            inline else => |r| "font/" ++ @tagName(r),
        };
    }
};

pub const Image = enum {
    png,
    jpeg,

    pub fn string(comptime app: Image) [:0]const u8 {
        return switch (app) {
            inline else => |r| "image/" ++ @tagName(r),
        };
    }
};

pub const Text = enum {
    plain,
    css,
    html,
    javascript,

    pub fn string(comptime app: Text) [:0]const u8 {
        return switch (app) {
            inline else => |r| "text/" ++ @tagName(r),
        };
    }
};

pub const Video = enum {
    mp4,

    pub fn string(comptime app: Video) [:0]const u8 {
        return switch (app) {
            inline else => |r| "video/" ++ @tagName(r),
        };
    }
};

/// If created using fromStr that string must outlive the Multipart
pub const MultiPart = union(enum) {
    mixed: Mixed,
    @"form-data": FormData,

    pub fn fromStr(str: []const u8) !MultiPart {
        inline for (@typeInfo(MultiPart).@"union".fields) |f| {
            if (startsWith(u8, str, f.name)) {
                return try f.type.fromStr(str);
            }
        } else {
            return error.InvalidMultiPart;
        }
    }

    pub const Mixed = struct {
        boundary: []const u8,

        pub fn fromStr(str: []const u8) !MultiPart {
            if (indexOf(u8, str, "boundary=\"")) |i| {
                return .{ .mixed = .{ .boundary = str[i + 10 .. str.len - 1] } };
            } else if (indexOf(u8, str, "boundary=")) |i| {
                return .{ .mixed = .{ .boundary = str[i + 9 ..] } };
            } else return error.InvalidMultiPart;
        }
    };
    pub const FormData = struct {
        boundary: []const u8,

        pub fn fromStr(str: []const u8) !MultiPart {
            if (indexOf(u8, str, "boundary=\"")) |i| {
                return .{ .@"form-data" = .{ .boundary = str[i + 10 .. str.len - 1] } };
            } else if (indexOf(u8, str, "boundary=")) |i| {
                return .{ .@"form-data" = .{ .boundary = str[i + 9 ..] } };
            } else return error.InvalidMultiPart;
        }
    };
};

test MultiPart {
    // RFC2046
    // valid
    const mixed_0 = "Content-Type: multipart/mixed; boundary=gc0p4Jq0M2Yt08j34c0p";
    // invalid
    const mixed_1 = "Content-Type: multipart/mixed; boundary=gc0pJq0M:08jU534c0p";
    // valid
    const mixed_2 = "Content-Type: multipart/mixed; boundary=\"gc0pJq0M:08jU534c0p\"";

    const test_m0 = try MultiPart.fromStr(mixed_0[24..]);
    const test_m1 = try MultiPart.fromStr(mixed_1[24..]);
    const test_m2 = try MultiPart.fromStr(mixed_2[24..]);

    const boundary_0 = "gc0p4Jq0M2Yt08j34c0p";
    const boundary_1 = "gc0pJq0M:08jU534c0p";
    const boundary_2 = "gc0pJq0M:08jU534c0p";

    try std.testing.expectEqualStrings(boundary_0, test_m0.mixed.boundary);
    try std.testing.expectEqualStrings(boundary_1, test_m1.mixed.boundary); // This test should error
    try std.testing.expectEqualStrings(boundary_2, test_m2.mixed.boundary);

    const fd_0 = "Content-Type: multipart/form-data; boundary=gc0p4Jq0M2Yt08j34c0p";
    const fd_1 = "Content-Type: multipart/form-data; boundary=gc0pJq0M:08jU534c0p";
    const fd_2 = "Content-Type: multipart/form-data; boundary=\"gc0pJq0M:08jU534c0p\"";

    const test_fd0 = try MultiPart.fromStr(fd_0[24..]);
    const test_fd1 = try MultiPart.fromStr(fd_1[24..]);
    const test_fd2 = try MultiPart.fromStr(fd_2[24..]);

    try std.testing.expectEqualStrings(boundary_0, test_fd0.@"form-data".boundary);
    try std.testing.expectEqualStrings(boundary_1, test_fd1.@"form-data".boundary); // This test should error
    try std.testing.expectEqualStrings(boundary_2, test_fd2.@"form-data".boundary);
}

pub const CharSet = enum {
    @"utf-8",
};

pub fn string(comptime ct: ContentType) []const u8 {
    const kind: [:0]const u8 = switch (ct.base) {
        inline else => |tag| @tagName(ct.base) ++ "/" ++ @tagName(tag),
    };

    if (ct.parameter) |param| {
        return switch (param) {
            inline else => |p| return kind ++ "; charset=" ++ @tagName(p),
        };
    } else return kind;
}

test string {
    try std.testing.expectEqualStrings("text/html; charset=utf-8", default.string());
    try std.testing.expectEqualStrings("image/png", (ContentType{ .base = .{ .image = .png } }).string());

    try std.testing.expectEqualStrings(
        "text/html",
        (ContentType{
            .base = .{ .text = .html },
        }).string(),
    );
}

pub fn fromStr(str: []const u8) !ContentType {
    inline for (std.meta.fields(ContentBase)) |field| {
        if (startsWith(u8, str, field.name)) {
            return wrapBase(field.type, str[field.name.len + 1 ..]);
        }
    }
    return error.UnknownContentType;
}

fn wrapField(comptime Kind: type, str: []const u8) !Kind {
    inline for (std.meta.fields(Kind)) |field| {
        if (startsWith(u8, str, field.name)) {
            return @enumFromInt(field.value);
        }
    }
    return error.UnknownContentType;
}

fn wrapBase(comptime kind: type, val: anytype) !ContentType {
    return .{
        .base = switch (kind) {
            MultiPart => .{ .multipart = try MultiPart.fromStr(val) },
            Application => .{ .application = try wrapField(kind, val) },
            Audio => .{ .audio = try wrapField(kind, val) },
            Font => .{ .font = try wrapField(kind, val) },
            Image => .{ .image = try wrapField(kind, val) },
            Text => .{ .text = try wrapField(kind, val) },
            Video => .{ .video = try wrapField(kind, val) },
            else => @compileError("not implemented type " ++ @typeName(kind)),
        },
    };
}

pub fn fromFileExtension(ext: []const u8) !ContentType {
    if (endsWith(u8, ext, "html") or endsWith(u8, ext, "htm")) {
        return .{ .base = .{ .text = .html } };
    }

    if (endsWith(u8, ext, "css")) {
        return .{ .base = .{ .text = .css } };
    }

    if (endsWith(u8, ext, "js")) {
        return .{ .base = .{ .text = .javascript } };
    }

    if (endsWith(u8, ext, "png")) {
        return .{ .base = .{ .image = .png } };
    }

    if (endsWith(u8, ext, "jpg") or endsWith(u8, ext, "jpeg")) {
        return .{ .base = .{ .image = .jpeg } };
    }

    return error.UnknownFileExtension;
}

test ContentType {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
const startsWith = std.mem.startsWith;
const endsWith = std.mem.endsWith;
const indexOf = std.mem.indexOf;
const eql = std.mem.eql;
