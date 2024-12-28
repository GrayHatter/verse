//! Verse Authentication Provider
//! TODO document!
ctx: *anyopaque,
vtable: VTable,

const Provider = @This();

pub const VTable = struct {
    lookup_user: ?LookupUserFn,
    valid: ?ValidFn,

    pub const LookupUserFn = *const fn (*const anyopaque, []const u8) Auth.Error!Auth.User;
    pub const ValidFn = *const fn (*const anyopaque, *const User) bool;

    pub const DefaultEmpty = .{
        .lookup_user = null,
        .valid = null,
    };
};

pub fn valid(self: *const Provider, user: *const User) bool {
    if (self.vtable.valid) |valid_fn| {
        return valid_fn(self.ctx, user);
    } else false;
}

/// TODO document the implications of non consttime function
pub fn lookupUser(self: *const Provider, user_id: []const u8) Auth.Error!Auth.User {
    if (self.vtable.lookup_user) |lookup_fn| {
        return try lookup_fn(self.ctx, user_id);
    } else return error.NotProvided;
}

const Auth = @import("../auth.zig");
const User = @import("user.zig");
