//! Verse Authentication Provider
//! TODO document!
ctx: *anyopaque,
vtable: VTable,

const Provider = @This();

pub const VTable = struct {
    authenticate: ?AuthenticateFn,
    lookup_user: ?LookupUserFn,
    valid: ?ValidFn,
    create_session: ?CreateSessionFn,

    pub const AuthenticateFn = *const fn (*anyopaque, *const Headers) Error!User;
    pub const LookupUserFn = *const fn (*anyopaque, []const u8) Error!User;
    pub const ValidFn = *const fn (*anyopaque, *const User) bool;
    pub const CreateSessionFn = *const fn (*anyopaque, *const User) Error!void;

    pub const Empty = .{
        .authenticate = null,
        .lookup_user = null,
        .valid = null,
        .create_session = null,
    };
};

pub fn authenticate(self: *const Provider, headers: *const Headers) Error!User {
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
pub fn lookupUser(self: *const Provider, user_id: []const u8) Error!User {
    if (self.vtable.lookup_user) |func| {
        return try func(self.ctx, user_id);
    }

    return error.NotProvided;
}

pub fn createSession(self: *const Provider, user: *User) Error!void {
    if (self.vtable.create_session) |func| {
        return try func(self.ctx, user);
    }

    return error.NotProvided;
}

test "Provider" {
    const std = @import("std");
    const p = Provider{
        .ctx = undefined,
        .vtable = VTable.Empty,
    };

    try std.testing.expectError(error.NotProvided, p.authenticate(undefined));
    try std.testing.expectEqual(false, p.valid(undefined));
    try std.testing.expectError(error.NotProvided, p.lookupUser(undefined));
    try std.testing.expectError(error.NotProvided, p.createSession(undefined));
}

const Auth = @import("../auth.zig");
pub const Error = Auth.Error;
const Headers = @import("../headers.zig");
const User = @import("user.zig");
