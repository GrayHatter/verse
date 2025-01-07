const Auth = @This();

pub const cookie = @import("auth/cookie.zig");

pub const Cookie = @import("auth/cookie.zig").Cookie;
pub const MTLS = @import("auth/mtls.zig");
pub const Provider = @import("auth/provider.zig");
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

pub const InvalidAuth = struct {
    pub fn provider() Provider {
        return Provider{
            .ctx = undefined,
            .vtable = .{
                .authenticate = authenticate,
                .valid = valid,
                .lookup_user = lookupUser,
                .create_session = createSession,
                .get_cookie = getCookie,
            },
        };
    }

    fn authenticate(_: *const anyopaque, _: *const Headers) Error!User {
        return error.UnknownUser;
    }

    fn createSession(_: *const anyopaque, _: *const User) Error!void {
        return error.Unauthenticated;
    }
    fn getCookie(_: *const anyopaque, _: User) Error!?RequestCookie {
        return error.Unauthenticated;
    }

    fn valid(_: *const anyopaque, _: *const User) bool {
        return false;
    }

    fn lookupUser(_: *const anyopaque, _: []const u8) Error!User {
        return error.UnknownUser;
    }
};

const TestingAuth = struct {
    pub fn init() TestingAuth {
        return .{};
    }

    fn lookupUser(_: *const TestingAuth, user_id: []const u8) Error!User {
        // Using std.mem.eql in this way is not a safe implementation for any
        // reasonable authentication system. The specific constant time
        // comparison you should use depends strongly on the auth source.
        if (std.mem.eql(u8, "12345", user_id)) {
            return User{
                .user_ptr = undefined,
            };
        } else return error.UnknownUser;
    }

    pub fn lookupUserUntyped(self: *const anyopaque, user_id: []const u8) Error!User {
        const typed: *const TestingAuth = @ptrCast(self);
        return typed.lookupUser(user_id);
    }

    pub fn provider(self: *TestingAuth) Provider {
        return .{
            .ctx = self,
            .vtable = .{
                .authenticate = null,
                .valid = null,
                .lookup_user = lookupUserUntyped,
                .create_session = null,
                .get_cookie = null,
            },
        };
    }
};

test TestingAuth {
    const expected_user = Auth.User{
        .user_ptr = undefined,
    };

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
pub const unsafeEql = std.mem.eql;
pub const constTimeEql = std.crypto.utils.timingSafeEql;
