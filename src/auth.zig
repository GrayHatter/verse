pub const AuthZ = @import("authorization.zig");
pub const AuthN = @import("authentication.zig");

const std = @import("std");
const Allocator = std.mem.Allocator;

pub const Auth = @This();
pub const User = @import("auth/user.zig");

provider: AnyAuth,
current_user: ?User = null,

pub const Error = error{
    UnknownUser,
    Unauthenticated,
    NotProvided,
};

pub fn valid(a: Auth) bool {
    return a.provider.valid();
}

pub fn requireValid(a: Auth) !void {
    if (a.user == null or !a.provider.valid()) return error.Unauthenticated;
}

pub fn Provider(T: type) type {
    return struct {
        const Self = @This();
        ctx: T,

        pub fn init(ctx: T) Self {
            return .{
                .ctx = ctx,
            };
        }

        /// TODO document the implications of non consttime function
        pub fn lookupUser(self: *const Self, user_id: []const u8) Error!User {
            return try self.ctx.lookupUser(user_id);
        }

        pub fn any(self: *const Self) AnyAuth {
            return .{
                .ctx = self,
                .lookup_user = lookupUserUntyped,
            };
        }

        fn lookupUserUntyped(self: *const anyopaque, user_id: []const u8) Error!User {
            const typed: *const T = @ptrCast(self);
            return typed.lookupUser(user_id);
        }
    };
}

/// Type Erased Version of an auth provider
pub const AnyAuth = struct {
    ctx: *const anyopaque,
    lookup_user: ?LookupUserFn = null,

    pub const LookupUserFn = *const fn (*const anyopaque, []const u8) Error!User;

    pub fn lookupUser(self: AnyAuth, user_id: []const u8) Error!User {
        if (self.lookup_user) |lookup_fn| {
            return try lookup_fn(self.ctx, user_id);
        } else return error.NotProvided;
    }
};

pub const InvalidProvider = struct {
    pub fn empty() AnyAuth {
        const P = Provider(This);
        const t = This{};
        return P.init(t).any();
    }
    pub const This = struct {
        fn lookupUser(_: @This(), _: []const u8) Error!User {
            return error.NotProvided;
        }
    };
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

    pub fn any(self: *const TestingAuth) AnyAuth {
        return .{
            .ctx = self,
            .lookup_user = lookupUserUntyped,
        };
    }
};

test Provider {
    const expected_user = User{
        .username = "testing",
    };

    const ProvidedAuth = Provider(TestingAuth);
    const p = ProvidedAuth.init(TestingAuth{});
    const user = p.lookupUser("12345");
    try std.testing.expectEqualDeep(expected_user, user);
    const erruser = p.lookupUser("123456");
    try std.testing.expectError(error.UnknownUser, erruser);
}

test AnyAuth {
    const expected_user = User{
        .username = "testing",
    };

    var provided = TestingAuth.init().any();

    const user = provided.lookupUser("12345");
    try std.testing.expectEqualDeep(expected_user, user);
    const erruser = provided.lookupUser("123456");
    try std.testing.expectError(error.UnknownUser, erruser);
}
