const Auth = @This();

pub const Provider = @import("auth/provider.zig");
pub const User = @import("auth/user.zig");

pub const Error = error{
    InvalidAuth,
    NotProvided,
    Unauthenticated,
    UnknownUser,
};

/// Fails closed: the provider used may return an error which will be caught and
/// returned as false.
//pub fn valid(a: Auth) bool {
//    return a.provider.valid() catch false;
//}

/// Unauthenticated is the only error this is able to return as the correct
/// definition for an HTTP 401
//pub fn requireValid(a: Auth) error{Unauthenticated}!void {
//    if (a.current_user == null or !a.valid()) return error.Unauthenticated;
//}

pub const MTLS = struct {
    base: ?Provider = null,

    pub fn authenticatePtr(ptr: *anyopaque, headers: *const Headers) Error!User {
        const self: *MTLS = @ptrCast(@alignCast(ptr));
        return self.authenticate(headers);
    }

    pub fn authenticate(mtls: *MTLS, headers: *const Headers) Error!User {
        var success: bool = false;
        if (headers.get("MTLS_ENABLED")) |enabled| {
            if (enabled.value_list.next) |_| return error.InvalidAuth;
            if (std.mem.eql(u8, enabled.value_list.value, "SUCCESS")) {
                success = true;
            }
        }

        if (!success) return error.UnknownUser;

        if (mtls.base) |base| {
            if (headers.get("MTLS_FINGERPRINT")) |enabled| {
                if (enabled.value_list.next != null) return error.InvalidAuth;
                return base.lookupUser(enabled.value_list.value);
            }
        }
        return .{ .user_ptr = null };
    }

    pub fn valid(_: *MTLS, _: *const User) bool {
        return false;
    }

    fn validPtr(ptr: *anyopaque, user: *const User) bool {
        const self: *MTLS = @ptrCast(@alignCast(ptr));
        return self.valid(user);
    }

    pub fn lookupUser(_: *MTLS, _: []const u8) Error!User {
        return error.UnknownUser;
    }

    pub fn lookupUserPtr(ptr: *anyopaque, user_id: []const u8) Error!User {
        const self: *MTLS = @ptrCast(@alignCast(ptr));
        return self.lookupUser(user_id);
    }

    pub fn provider(mtls: *MTLS) Provider {
        return Provider{
            .ctx = mtls,
            .vtable = .{
                .authenticate = authenticatePtr,
                .valid = validPtr,
                .lookup_user = lookupUserPtr,
            },
        };
    }
};

test MTLS {
    const a = std.testing.allocator;
    var mtls = MTLS{};
    var provider = mtls.provider();

    var headers = Headers.init(a);
    defer headers.raze();
    try headers.add("MTLS_ENABLED", "SUCCESS");
    try headers.add("MTLS_FINGERPRINT", "LOLTOTALLYVALID");

    const user = try provider.authenticate(&headers);

    try std.testing.expectEqual(null, user.user_ptr);

    try headers.add("MTLS_ENABLED", "SUCCESS");
    const err = provider.authenticate(&headers);
    try std.testing.expectError(error.InvalidAuth, err);

    headers.raze();
    headers = Headers.init(a);

    try headers.add("MTLS_ENABLED", "FAILURE!");
    const err2 = provider.authenticate(&headers);
    try std.testing.expectError(error.UnknownUser, err2);
    // TODO there's likely a few more error states we should validate;
}

pub const InvalidAuth = struct {
    pub fn provider() Provider {
        return Provider{
            .ctx = undefined,
            .vtable = .{
                .authenticate = null, // TODO write invalid
                .valid = valid,
                .lookup_user = lookupUser,
            },
        };
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
            },
        };
    }
};

test Provider {
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

const std = @import("std");
const Allocator = std.mem.Allocator;
const Headers = @import("headers.zig");
