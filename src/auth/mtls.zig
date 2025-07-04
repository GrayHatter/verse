//! MTLS auth Provider. Implements mTLS authentication, with verification done by
//! a rproxy (example configuration provided in contrib/), providing a higher
//! level of security and authenticity than other, more common methods of
//! authentication. If you need exceptionally high security, you may wish to
//! combine this authentication system, with another such as a cookie based
//! authentication to provide 2fa or password verification on top of mTLS.
//! Allowing you to verify both the device using mTLS, the user via credentials,
//! 2FA via any token based credential.
base: ?Provider = null,

const MTLS = @This();

/// TODO document misuse of default without a base provider
pub fn authenticate(ptr: *anyopaque, headers: *const Headers) Error!User {
    const mtls: *MTLS = @ptrCast(@alignCast(ptr));

    if (headers.getCustom("MTLS_ENABLED")) |enabled| {
        if (enabled.list.len > 1) return error.InvalidAuth;
        // MTLS validation as currently supported here is done by the
        // reverse proxy. Constant time compare would provide no security
        // benefits here.
        if (!std.mem.eql(u8, enabled.list[0], "SUCCESS"))
            return error.UnknownUser;
    } else {
        log.debug("MTLS not enabled", .{});
        return error.InvalidAuth;
    }

    if (mtls.base) |base| {
        var user: ?User = null;
        if (headers.getCustom("MTLS_FINGERPRINT")) |enabled| {
            // Verse does not specify an order for which is valid so it is
            // an error if there is ever more than a single value for the
            // mTLS fingerprint
            if (enabled.list.len > 1) return error.InvalidAuth;
            user = try base.lookupUser(enabled.list[0]);
            if (user) |*u| {
                u.authenticated = true;
                u.origin_provider = @ptrCast(@alignCast(ptr));
                return u.*;
            }
        } else {
            log.warn("MTLS fingerprint missing", .{});
        }
    }

    // The MTLS proxy asserts the user has a valid cert, but we were unable to
    // find the user specified. We return an invalid user here to let userspace
    // decide how to enforce this behavior.
    return .invalid_user;
}

fn valid(ptr: *const anyopaque, user: *const User) bool {
    const mtls: *const MTLS = @ptrCast(@alignCast(ptr));
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
            .create_session = null,
            .get_cookie = null,
        },
    };
}

test MTLS {
    const a = std.testing.allocator;
    var mtls = MTLS{};
    var provider_ = mtls.provider();

    var headers = Headers.init();
    defer headers.raze(a);
    try headers.addCustom(a, "MTLS_ENABLED", "SUCCESS");
    try headers.addCustom(a, "MTLS_FINGERPRINT", "LOLTOTALLYVALID");

    const user = try provider_.authenticate(&headers);

    try std.testing.expectEqual(null, user.user_ptr);
    try std.testing.expectEqual(false, provider_.valid(&user));

    try headers.addCustom(a, "MTLS_ENABLED", "SUCCESS");
    const err = provider_.authenticate(&headers);
    try std.testing.expectError(error.InvalidAuth, err);

    headers.raze(a);
    headers = Headers.init();

    try headers.addCustom(a, "MTLS_ENABLED", "FAILURE!");
    const err2 = provider_.authenticate(&headers);
    try std.testing.expectError(error.UnknownUser, err2);

    {
        // authenticate will return .invalid_user when the mTLS proxy is able to
        // validate the cert/key, but we're unable to find/lookup the given
        // user. We defer to userspace here but require that the default user
        // can not be considered valid.
        var iv_user: User = .invalid_user;
        try std.testing.expectEqual(false, iv_user.authenticated);
        try std.testing.expectEqual(false, provider_.valid(&iv_user));

        if (comptime @import("builtin").mode != .Debug) {
            try std.testing.expectEqual(false, iv_user.valid());
        }

        iv_user.origin_provider = &provider_;
        try std.testing.expectEqual(false, iv_user.valid());
    }

    // TODO there's likely a few more error states we should validate;

}

const std = @import("std");
const log = std.log.scoped(.verse);
const Provider = @import("Provider.zig");
const User = @import("user.zig");
const Error = @import("../auth.zig").Error;
const Headers = @import("../headers.zig");
