pub const IOVec = extern struct {
    base: [*]const u8,
    len: usize,

    pub const empty: IOVec = .{ .base = "".ptr, .len = 0 };

    pub fn fromSlice(s: []const u8) IOVec {
        return .{ .base = s.ptr, .len = s.len };
    }
};

pub const IOVArray = std.ArrayListUnmanaged(IOVec);

const std = @import("std");
