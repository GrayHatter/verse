//! Verse Authentication Provider
//! TODO document!
ctx: *anyopaque,
vtable: VTable,

const Provider = @This();

pub const VTable = struct {
    authenticate: ?AuthenticateFn,
    lookup_user: ?LookupUserFn,
    valid: ?ValidFn,

    pub const AuthenticateFn = *const fn (*anyopaque, *const Headers) Auth.Error!Auth.User;
    pub const LookupUserFn = *const fn (*anyopaque, []const u8) Auth.Error!Auth.User;
    pub const ValidFn = *const fn (*anyopaque, *const User) bool;

    pub const Empty = .{
        .authenticate = null,
        .lookup_user = null,
        .valid = null,
    };
};

pub fn authenticate(self: *const Provider, headers: *const Headers) Auth.Error!Auth.User {
    if (self.vtable.authenticate) |func| {
        return try func(self.ctx, headers);
    }

    return error.NotProvided;
}

pub fn valid(self: *const Provider, user: *const User) bool {
    if (self.vtable.valid) |func| {
        return func(self.ctx, user);
    }

    return false;
}

/// TODO document the implications of non consttime function
pub fn lookupUser(self: *const Provider, user_id: []const u8) Auth.Error!Auth.User {
    if (self.vtable.lookup_user) |func| {
        return try func(self.ctx, user_id);
    }

    return error.NotProvided;
}

const Auth = @import("../auth.zig");
const Headers = @import("../headers.zig");
const User = @import("user.zig");
