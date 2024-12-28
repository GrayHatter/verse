provider: Provider,
current_user: ?User = null,

pub const Auth = @This();
pub const User = @import("auth/user.zig");
pub const Provider = @import("auth/provider.zig");

pub const Error = error{
    UnknownUser,
    Unauthenticated,
    NotProvided,
};

/// Fails closed: the provider used may return an error which will be caught and
/// returned as false.
pub fn valid(a: Auth) bool {
    return a.provider.valid() catch false;
}

/// Unauthenticated is the only error this is able to return as the correct
/// definition for an HTTP 401
pub fn requireValid(a: Auth) error{Unauthenticated}!void {
    if (a.current_user == null or !a.valid()) return error.Unauthenticated;
}

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

    pub fn valid(mtls: *MTLS) bool {
        _ = mtls;
        return false;
    }

    fn validPtr(ptr: *anyopaque) bool {
        const self: *MTLS = @ptrCast(ptr);
        return self.valid();
    }

    pub fn lookupUser(mtls: *MTLS, user_id: []const u8) Error!User {
        _ = mtls;
        _ = user_id;
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
            .vtable = Provider.VTable.DefaultEmpty,
        };
    }

    fn lookupUser(_: @This(), _: []const u8) Error!User {
        return error.NotProvided;
    }
};

const TestingAuth = struct {
    pub fn init() TestingAuth {
        return .{};
    }

    pub fn lookupUser(_: *const TestingAuth, user_id: []const u8) Error!User {
        // Do not use
        if (std.mem.eql(u8, "12345", user_id)) {
            return User{
                .username = "testing",
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
        .username = "testing",
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
pub const AuthZ = @import("authorization.zig");
pub const AuthN = @import("authentication.zig");
