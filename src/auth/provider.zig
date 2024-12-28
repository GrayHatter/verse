//! Verse Authentication Provider
//! TODO document!
ctx: *anyopaque,
vtable: VTable,

const Provider = @This();

pub const VTable = struct {
    lookup_user: ?LookupUserFn,
    valid: ?ValidFn,

    pub const LookupUserFn = *const fn (*const anyopaque, []const u8) Auth.Error!Auth.User;
    pub const ValidFn = *const fn (*const anyopaque) Auth.Error!bool;

    pub const DefaultEmpty = .{
        .lookup_user = null,
        .valid = null,
    };
};

/// TODO document the implications of non consttime function
pub fn lookupUser(self: *const Provider, user_id: []const u8) Auth.Error!Auth.User {
    if (self.vtable.lookup_user) |lookup_fn| {
        return try lookup_fn(self.ctx, user_id);
    } else return error.NotProvided;
}

//pub fn any(self: *const ) AnyAuth {
//    return .{
//        .ctx = self,
//        .vtable = .{
//            .valid = null,
//            .lookup_user = lookupUserUntyped,
//        },
//    };
//}

const Auth = @import("../auth.zig");
