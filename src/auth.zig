pub const Auth = @This();
pub const User = @import("auth/user.zig");

provider: AnyAuth,
current_user: ?User = null,

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
                .vtable = .{
                    .valid = null,
                    .lookup_user = lookupUserUntyped,
                },
            };
        }

        fn lookupUserUntyped(self: *const anyopaque, user_id: []const u8) Error!User {
            const typed: *const T = @ptrCast(self);
            return typed.lookupUser(user_id);
        }
    };
}

/// Auth VTable
pub const VTable = struct {
    lookup_user: ?LookupUserFn,
    valid: ?ValidFn,

    pub const LookupUserFn = *const fn (*const anyopaque, []const u8) Error!User;
    pub const ValidFn = *const fn (*const anyopaque) Error!bool;
    pub const DefaultEmpty = .{
        .lookup_user = null,
        .valid = null,
    };
};

/// Type Erased Version of an auth provider
pub const AnyAuth = struct {
    ctx: *const anyopaque,
    vtable: VTable,

    pub fn valid(self: AnyAuth) Error!bool {
        if (self.vtable.valid) |v| {
            return try v(self.ctx);
        } else return error.NotProvided;
    }

    pub fn lookupUser(self: AnyAuth, user_id: []const u8) Error!User {
        if (self.vtable.lookup_user) |lookup_fn| {
            return try lookup_fn(self.ctx, user_id);
        } else return error.NotProvided;
    }
};

pub const MTLSAuth = struct {};

pub const InvalidProvider = struct {
    pub fn empty() AnyAuth {
        const P = Provider(@This());
        return P.init(@This(){}).any();
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

    pub fn any(self: *const TestingAuth) AnyAuth {
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

const std = @import("std");
const Allocator = std.mem.Allocator;
pub const AuthZ = @import("authorization.zig");
pub const AuthN = @import("authentication.zig");
