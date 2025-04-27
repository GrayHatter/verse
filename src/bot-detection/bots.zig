pub const Rules = struct {
    pub fn rfc9110(ua: UA, r: *const Request, score: *f16) !void {
        _ = ua;
        _ = r;
        _ = score;
        if (false) {}
    }
};

pub const TxtRules = struct {
    name: []const u8,
    allow: bool,
    delay: bool = false,
};

const UA = @import("../user-agent.zig");
const Request = @import("../request.zig");
