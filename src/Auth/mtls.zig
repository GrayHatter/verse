//! Mutual TLS authentication.
//!
//! Implements mTLS authentication, with cert/key verification done by a reverse
//! proxy (nginx verified and supported, with an example configuration provided
//! in contrib/)
//!
//! mTLS can provide a higher level of security and authenticity than other or
//! more common methods. Because mTLS exchange targets a lower, it can be
//! chained with other auth methods (e.g. cookie or session auth) to provide a
//! higher level of security. Or, mTLS can be used to provide a 2nd factor auth.
//! Used in this way, mTLS can be used to verify both the device using mTLS, and
//! then the user via different credentials.
//!
//! See https://srctree.gr.ht/repo/srctree for an example of mTLS auth in use.

auth: Auth = .{
    .vtable = &.{
        .authenticate = authenticate,
        .valid = null,
        .lookupUser = null,
        .createSession = null,
        .getUserToken = null,
        .getUserCookie = null,
    },
},

const MTLS = @This();

pub fn authenticate(ptr: *Auth, headers: *const Headers, _: Timestamp) Error!User {
    if (headers.getCustomValue("MTLS_ENABLED")) |enabled| {
        // MTLS validation as currently supported here is done by the
        // reverse proxy. Constant time compare would provide no security
        // benefits here.
        if (!std.mem.eql(u8, enabled, "SUCCESS"))
            return error.UnknownUser;
    } else |_| {
        log.debug("MTLS not enabled", .{});
        return error.InvalidAuth;
    }

    var user: ?User = null;
    if (headers.getCustomValue("MTLS_FINGERPRINT")) |enabled| {
        user = try ptr.lookupUser(enabled);
        if (user) |*u| {
            u.authenticated = true;
            u.auth_ptr = ptr;
            return u.*;
        }
    } else |err| switch (err) {
        error.Missing => log.warn("MTLS fingerprint missing", .{}),
        // Verse does not specify an order for which is valid so it is
        // an error if there is ever more than a single value for the
        // mTLS fingerprint
        error.MultipleValues => return error.InvalidAuth,
    }

    // The MTLS proxy asserts the user has a valid cert, but we were unable to
    // find the user specified. We return an invalid user here to let userspace
    // decide how to enforce this behavior.
    return .invalid_user;
}

test MTLS {
    const a = std.testing.allocator;
    const now: Timestamp = Clock.real.now(std.testing.io);
    var mtls = MTLS{};

    var headers: Headers = .empty;
    defer headers.raze(a);
    try headers.addCustom(a, "MTLS_ENABLED", "SUCCESS");
    try headers.addCustom(a, "MTLS_FINGERPRINT", "LOLTOTALLYVALID");

    const user = mtls.auth.authenticate(&headers, now) catch undefined;

    try std.testing.expectEqual(null, user.user_ptr);
    try std.testing.expectEqual(false, mtls.auth.valid(&user));

    try headers.addCustom(a, "MTLS_ENABLED", "SUCCESS");
    const err = mtls.auth.authenticate(&headers, now);
    try std.testing.expectError(error.InvalidAuth, err);

    headers.raze(a);
    headers = .empty;

    try headers.addCustom(a, "MTLS_ENABLED", "FAILURE!");
    const err2 = mtls.auth.authenticate(&headers, now);
    try std.testing.expectError(error.UnknownUser, err2);

    {
        var iv_user: User = .invalid_user;
        try std.testing.expectEqual(false, iv_user.authenticated);
        try std.testing.expectEqual(false, mtls.auth.valid(&iv_user));

        if (comptime @import("builtin").mode != .Debug) {
            try std.testing.expectEqual(false, iv_user.valid());
        }

        iv_user.auth_ptr = &mtls.auth;
        try std.testing.expectEqual(false, iv_user.valid());
    }

    // TODO there's likely a few more error states we should validate;

}

const std = @import("std");
const log = std.log.scoped(.verse);
const User = @import("User.zig");
const Auth = @import("../Auth.zig");
const Error = Auth.Error;
const Headers = @import("../headers.zig");

const Clock = std.Io.Clock;
const Timestamp = std.Io.Timestamp;
