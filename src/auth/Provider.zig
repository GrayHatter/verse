//! Verse Authentication Provider
//! Similar to the Allocator interface Provider exposes a consistent API that
//! can be reused across all the verse authentication modules. Any object that
//! exposes a Provider, can be plugged into Verse and used to provide
//! authentication or authorization. E.g. providing user lookup.
ctx: *anyopaque,
vtable: VTable,

const Provider = @This();

pub const VTable = struct {
    authenticate: ?AuthenticateFn,
    lookupUser: ?LookupUserFn,
    valid: ?ValidFn,
    createSession: ?CreateSessionFn,
    getCookie: ?GetCookieFn,

    pub const AuthenticateFn = *const fn (*anyopaque, *const Headers) Error!User;
    pub const LookupUserFn = *const fn (*anyopaque, []const u8) Error!User;
    pub const ValidFn = *const fn (*const anyopaque, *const User) bool;
    pub const CreateSessionFn = *const fn (*anyopaque, *User) Error!void;
    pub const GetCookieFn = *const fn (*anyopaque, User) Error!?RequestCookie;

    pub const empty: VTable = .{
        .authenticate = null,
        .lookupUser = null,
        .valid = null,
        .createSession = null,
        .getCookie = null,
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
    if (self.vtable.lookupUser) |func| {
        return try func(self.ctx, user_id);
    }

    return error.NotProvided;
}

pub fn createSession(self: *const Provider, user: *User) Error!void {
    if (self.vtable.createSession) |func| {
        return try func(self.ctx, user);
    }

    return error.NotProvided;
}

/// Note getCookie will return `null` instead of an error when no function is
/// provided.
pub fn getCookie(self: *const Provider, user: User) Error!?RequestCookie {
    if (self.vtable.getCookie) |func| {
        return try func(self.ctx, user);
    }

    return null;
}

test "Provider" {
    const std = @import("std");
    const p = Provider{
        .ctx = undefined,
        .vtable = .empty,
    };

    try std.testing.expectError(error.NotProvided, p.authenticate(undefined));
    try std.testing.expectEqual(false, p.valid(undefined));
    try std.testing.expectError(error.NotProvided, p.lookupUser(undefined));
    try std.testing.expectError(error.NotProvided, p.createSession(undefined));
    try std.testing.expectEqual(null, p.getCookie(undefined));
}

pub const invalid: Provider = .{
    .ctx = undefined,
    .vtable = .{
        .authenticate = Invalid.authenticate,
        .valid = Invalid.valid,
        .lookupUser = Invalid.lookupUser,
        .createSession = Invalid.createSession,
        .getCookie = Invalid.getCookie,
    },
};

pub const Invalid = struct {
    fn authenticate(_: *const anyopaque, _: *const Headers) Error!User {
        return error.UnknownUser;
    }
    fn createSession(_: *const anyopaque, _: *const User) Error!void {
        return error.Unauthenticated;
    }
    fn getCookie(_: *const anyopaque, _: User) Error!?RequestCookie {
        return error.Unauthenticated;
    }
    fn valid(_: *const anyopaque, _: *const User) bool {
        return false;
    }
    fn lookupUser(_: *const anyopaque, _: []const u8) Error!User {
        return error.UnknownUser;
    }
};

const Auth = @import("../auth.zig");
const Error = Auth.Error;
const Headers = @import("../headers.zig");
const RequestCookie = @import("../cookies.zig").Cookie;
const User = @import("user.zig");
