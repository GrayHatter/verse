const Auth = @This();

pub const Provider = @import("auth/provider.zig");
pub const User = @import("auth/user.zig");

pub const Error = error{
    InvalidAuth,
    NotProvided,
    Unauthenticated,
    UnknownUser,
};

/// TODO document
pub const MTLS = struct {
    base: ?Provider = null,

    pub fn authenticate(ptr: *anyopaque, headers: *const Headers) Error!User {
        const mtls: *MTLS = @ptrCast(@alignCast(ptr));
        var success: bool = false;
        if (headers.get("MTLS_ENABLED")) |enabled| {
            if (enabled.value_list.next) |_| return error.InvalidAuth;
            // MTLS validation as currently supported here is done by the
            // reverse proxy. Constant time compare would provide no security
            // benefits here.
            if (std.mem.eql(u8, enabled.value_list.value, "SUCCESS")) {
                success = true;
            }
        }

        if (!success) return error.UnknownUser;

        if (mtls.base) |base| {
            if (headers.get("MTLS_FINGERPRINT")) |enabled| {
                // Verse does not specify an order for which is valid so it is
                // an error if there is ever more than a single value for the
                // mTLS fingerprint
                if (enabled.value_list.next != null) return error.InvalidAuth;
                return base.lookupUser(enabled.value_list.value);
            }
        }
        return .{ .user_ptr = null };
    }

    fn valid(ptr: *anyopaque, user: *const User) bool {
        const mtls: *MTLS = @ptrCast(@alignCast(ptr));
        if (mtls.base) |base| return base.valid(user);
        return false;
    }

    pub fn lookupUser(ptr: *anyopaque, user_id: []const u8) Error!User {
        const mtls: *MTLS = @ptrCast(@alignCast(ptr));
        if (mtls.base) |base| return base.lookupUser(user_id);
        return error.UnknownUser;
    }

    pub fn provider(mtls: *MTLS) Provider {
        return Provider{
            .ctx = mtls,
            .vtable = .{
                .authenticate = authenticate,
                .valid = valid,
                .lookup_user = lookupUser,
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

// Auth requires strong security guarantees so to prevent ambiguity do not
// reduce the namespace for any stdlb functions. e.g. std.mem.eql is not a
// constant time cmp function, and while not every cmp needs constant time it
// should be explicit which is being used.
const std = @import("std");
const Allocator = std.mem.Allocator;
const Headers = @import("headers.zig");
