//! Verse Authentication
//!
//!
//!

vtable: *const VTable,

const cookie = @import("Auth/cookie.zig");
pub const Cookie = cookie.Cookie;
pub const MTLS = @import("Auth/mtls.zig");
pub const User = @import("Auth/User.zig");

const Auth = @This();

var disabled_auth: Auth = .{ .vtable = .failing };
pub const disabled: *Auth = &disabled_auth;

pub fn mtls(comptime vt: *const VTable) Auth {
    return .{
        .vtable = &.{
            .authenticate = authenticate,
            .valid = vt.valid,
            .lookupUser = vt.lookupUser,
            .createSession = vt.createSession,
            .getUserToken = vt.getUserToken,
        },
    };
}

pub const VTable = struct {
    valid: ?ValidFn,
    lookupUser: ?LookupUserFn,

    getUserCookie: ?UserCookieFn,
    // UserToken API is currently unstable
    getUserToken: ?UserTokenFn,

    authenticate: ?AuthenticateFn,
    createSession: ?CreateSessionFn,

    pub const ValidFn = *const fn (*const Auth, *const User) bool;
    pub const LookupUserFn = *const fn (*const Auth, []const u8) Error!User;

    pub const UserCookieFn = *const fn (*const Auth, User) Error!?RequestCookie;
    pub const UserTokenFn = *const fn (*Auth, User, Timestamp) Error![]const u8;

    /// Mutable to allow session or metadata tracking during authentication valid
    pub const AuthenticateFn = *const fn (*Auth, *const Headers, Timestamp) Error!User;
    /// Mutable to enable stateful session creation
    pub const CreateSessionFn = *const fn (*Auth, *User, Timestamp) Error!void;

    pub const empty: *const VTable = &.{
        .authenticate = null,
        .lookupUser = null,
        .valid = null,
        .createSession = null,
        .getUserCookie = null,
        .getUserToken = null,
    };

    pub const failing: *const VTable = &.{
        .authenticate = Invalid.authenticate,
        .lookupUser = Invalid.lookupUser,
        .valid = Invalid.valid,
        .createSession = Invalid.createSession,
        .getUserCookie = Invalid.getCookie,
        .getUserToken = Invalid.getToken,
    };

    const Invalid = struct {
        fn authenticate(_: *const Auth, _: *const Headers, _: Timestamp) Error!User {
            return error.UnknownUser;
        }
        fn createSession(_: *const Auth, _: *const User, _: Timestamp) Error!void {
            return error.Unauthenticated;
        }
        fn getToken(_: *Auth, _: User, _: Timestamp) Error![]const u8 {
            return error.Unauthenticated;
        }
        fn getCookie(_: *const Auth, _: User) Error!?RequestCookie {
            return error.Unauthenticated;
        }
        fn valid(_: *const Auth, _: *const User) bool {
            return false;
        }
        fn lookupUser(_: *const Auth, _: []const u8) Error!User {
            return error.UnknownUser;
        }
    };
};

pub const Error = error{
    InvalidAuth,
    NoSpaceLeft,
    NotProvided,
    OutOfMemory,
    TokenExpired,
    Unauthenticated,
    UnknownUser,
};

pub fn authenticate(auth: *Auth, headers: *const Headers, now: Timestamp) Error!User {
    if (auth.vtable.authenticate) |func| {
        return try @call(.auto, func, .{ auth, headers, now });
    }

    return error.NotProvided;
}

pub fn valid(auth: *const Auth, user: *const User) bool {
    if (auth.vtable.valid) |func| {
        return @call(.auto, func, .{ auth, user });
    }

    return false;
}

/// TODO document the implications of non consttime function
pub fn lookupUser(auth: *const Auth, user_id: []const u8) Error!User {
    if (auth.vtable.lookupUser) |func| {
        return try @call(.auto, func, .{ auth, user_id });
    }

    return error.NotProvided;
}

pub fn createSession(auth: *Auth, user: *User, now: Timestamp) Error!void {
    if (auth.vtable.createSession) |func| {
        return try @call(.auto, func, .{ auth, user, now });
    }

    return error.NotProvided;
}

/// Note getCookie will return `null` instead of an error when no function is
/// provided.
pub fn getUserToken(auth: *const Auth, user: User, now: Timestamp) Error![]const u8 {
    if (auth.vtable.getUserToken) |func| {
        return @call(.auto, func, .{ auth, user, now });
    }

    return null;
}

/// Note getCookie will return `null` instead of an error when no function is
/// provided.
pub fn getUserCookie(auth: *const Auth, user: User) Error!?RequestCookie {
    if (auth.vtable.getUserCookie) |func| {
        return @call(.auto, func, .{ auth, user });
    }

    return null;
}

test Auth {
    var p: Auth = .{ .vtable = .empty };

    try std.testing.expectError(error.NotProvided, p.authenticate(undefined, undefined));
    try std.testing.expectEqual(false, p.valid(undefined));
    try std.testing.expectError(error.NotProvided, p.lookupUser(undefined));
    try std.testing.expectError(error.NotProvided, p.createSession(undefined, undefined));
    try std.testing.expectEqual(null, p.getUserCookie(undefined));
}

pub const Testing = struct {
    auth: Auth = .{
        .vtable = &.{
            .valid = valid_,
            .lookupUser = Testing.lookupUser,
            .authenticate = null,
            .createSession = null,
            .getUserCookie = null,
            .getUserToken = null,
        },
    },

    pub fn init() Testing {
        return .{};
    }

    pub fn getValidUser(ta: *const Testing) User {
        return .{
            .auth_ptr = &ta.auth,
            .unique_id = "_force_valid_user",
            .user_ptr = @ptrCast(@constCast("_force_valid_user")),
            .authenticated = true,
        };
    }

    pub fn lookupUser(ptr: *const Auth, user_id: []const u8) Error!User {
        const ta: *const Testing = @fieldParentPtr("auth", ptr);
        _ = ta;
        // Using std.mem.eql in this way is not a safe implementation for any
        // reasonable authentication system. The specific constant time
        // comparison you should use depends strongly on the auth source.
        if (unsafe.eql(u8, "12345", user_id)) {
            return .{ .unique_id = null };
        } else return error.UnknownUser;
    }

    pub fn valid_(_: *const Auth, u: *const User) bool {
        return (unsafe.eql(u8, u.unique_id orelse return false, "_force_valid_user") and
            unsafe.eql(u8, @as(*const [17:0]u8, @ptrCast(u.user_ptr orelse return false)), "_force_valid_user"));
    }
};

test Testing {
    const expected_user: Auth.User = .invalid_user;

    var t = Testing{};
    const user = t.auth.lookupUser("12345");
    try std.testing.expectEqualDeep(expected_user, user);
    const erruser = t.auth.lookupUser("123456");
    try std.testing.expectError(error.UnknownUser, erruser);
}

test {
    _ = std.testing.refAllDecls(MTLS);
    _ = std.testing.refAllDecls(cookie);
    _ = std.testing.refAllDecls(User);
    _ = &Testing;
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Timestamp = std.Io.Timestamp;

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
