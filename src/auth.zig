const Auth = @This();

pub const cookie = @import("auth/cookie.zig");

pub const Cookie = @import("auth/cookie.zig").Cookie;
pub const MTLS = @import("auth/mtls.zig");
pub const Provider = @import("auth/Provider.zig");
pub const User = @import("auth/user.zig");

pub const Error = error{
    InvalidAuth,
    NoSpaceLeft,
    NotProvided,
    OutOfMemory,
    TokenExpired,
    Unauthenticated,
    UnknownUser,
};

pub const TestingAuth = struct {
    _provider: Provider = undefined,

    pub fn init() TestingAuth {
        return .{};
    }

    pub fn getValidUser(ta: *TestingAuth) User {
        ta._provider = ta.provider();
        return .{
            .origin_provider = &ta._provider,
            .unique_id = "_force_valid_user",
            .user_ptr = @ptrCast(@constCast("_force_valid_user")),
            .authenticated = true,
        };
    }

    fn lookupUser(_: *const TestingAuth, user_id: []const u8) Error!User {
        // Using std.mem.eql in this way is not a safe implementation for any
        // reasonable authentication system. The specific constant time
        // comparison you should use depends strongly on the auth source.
        if (std.mem.eql(u8, "12345", user_id)) {
            return .{
                .unique_id = null,
            };
        } else return error.UnknownUser;
    }

    pub fn lookupUserUntyped(self: *const anyopaque, user_id: []const u8) Error!User {
        const typed: *const TestingAuth = @ptrCast(@alignCast(self));
        return typed.lookupUser(user_id);
    }

    pub fn valid(_: *const anyopaque, u: *const User) bool {
        return (unsafe.eql(u8, u.unique_id orelse return false, "_force_valid_user") and
            unsafe.eql(u8, @as(*const [17:0]u8, @ptrCast(u.user_ptr orelse return false)), "_force_valid_user"));
    }

    pub fn provider(self: *TestingAuth) Provider {
        return .{
            .ctx = self,
            .vtable = .{
                .authenticate = null,
                .valid = valid,
                .lookup_user = lookupUserUntyped,
                .create_session = null,
                .get_cookie = null,
            },
        };
    }
};

test TestingAuth {
    const expected_user: Auth.User = .invalid_user;

    var t = TestingAuth{};
    const provider = t.provider();
    const user = provider.lookupUser("12345");
    try std.testing.expectEqualDeep(expected_user, user);
    const erruser = provider.lookupUser("123456");
    try std.testing.expectError(error.UnknownUser, erruser);
}

test {
    _ = std.testing.refAllDecls(MTLS);
    _ = std.testing.refAllDecls(cookie);
    _ = std.testing.refAllDecls(Provider);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Headers = @import("headers.zig");
const RequestCookie = @import("cookies.zig").Cookie;

// Verse.Auth attempts to provide strong security guarantees where reasonable
// e.g. std.mem.eql faster, but doesn't work in constant time. In an effort to
// avoid confusion, the two comparison functions are given possibly misleading
// names to encourage closer inspection and annotation over which is being used,
// and how it's safe to do so.
pub const unsafe = struct {
    pub const eql = std.mem.eql;
};
pub const timing_safe = std.crypto.timing_safe;
