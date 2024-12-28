pub const Auth = @This();

pub const Provider = @import("auth/provider.zig");

pub const AuthZ = @import("authorization.zig");
pub const AuthN = @import("authentication.zig");

pub const User = @import("auth/user.zig");

pub const Error = error{
    UnknownUser,
    Unauthenticated,
    NotProvided,
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
    pub fn provider(mtls: *MTLS) Provider {
        return Provider{
            .ctx = mtls,
            .vtable = .{
                .valid = validPtr,
                .lookup_user = lookupUserPtr,
            },
        };
    }

    pub fn valid(_: *MTLS, _: *const User) bool {
        return false;
    }

    fn validPtr(ptr: *anyopaque, user: *const User) bool {
        const self: *MTLS = @ptrCast(ptr);
        return self.valid(user);
    }

    pub fn lookupUser(_: *MTLS, _: []const u8) Error!User {
        return error.UnknownUser;
    }

    pub fn lookupUserPtr(ptr: *anyopaque, user_id: []const u8) Error!User {
        const self: *MTLS = @ptrCast(ptr);
        return self.lookupUser(user_id);
    }
};

test MTLS {
    //const a = std.testing.allocator;

}

pub const InvalidAuth = struct {
    pub fn provider() Provider {
        return Provider{
            .ctx = undefined,
            .vtable = .{
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
