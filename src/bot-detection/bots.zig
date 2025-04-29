pub const Rules = struct {
    pub fn rfc9110_10_1_2(ua: UA, r: *const Request, score: *f16) !void {
        // https://www.rfc-editor.org/rfc/rfc9110#section-10.1.2

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
