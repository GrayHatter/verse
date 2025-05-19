//! MTLS auth Provider. Implements mTLS authentication, with verification done by
//! a rproxy (example configuration provided in contrib/), providing a higher
//! level of security and authenticity than other, more common methods of
//! authentication. If you need exceptionally high security, you may wish to
//! combine this authentication system, with another such as a cookie based
//! authentication to provide 2fa or password verification on top of mTLS.
//! Allowing you to verify both the device using mTLS, the user via credentials,
//! 2FA via any token based credential.
base: ?Provider = null,

pub const MTLS = @This();

/// TODO document misuse of default without a base provider
pub fn authenticate(ptr: *anyopaque, headers: *const Headers) Error!User {
    const mtls: *MTLS = @ptrCast(@alignCast(ptr));
    var success: bool = false;
    if (headers.getCustom("MTLS_ENABLED")) |enabled| {
        if (enabled.list.len > 1) return error.InvalidAuth;
        // MTLS validation as currently supported here is done by the
        // reverse proxy. Constant time compare would provide no security
        // benefits here.
        if (std.mem.eql(u8, enabled.list[0], "SUCCESS")) {
            success = true;
        }
    } else log.debug("MTLS not enabled", .{});

    if (!success) return error.UnknownUser;

    if (mtls.base) |base| {
        if (headers.getCustom("MTLS_FINGERPRINT")) |enabled| {
            // Verse does not specify an order for which is valid so it is
            // an error if there is ever more than a single value for the
            // mTLS fingerprint
            if (enabled.list.len > 1) return error.InvalidAuth;
            return base.lookupUser(enabled.list[0]);
        } else log.debug("MTLS fingerprint missing", .{});
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

    try headers.addCustom(a, "MTLS_ENABLED", "SUCCESS");
    const err = provider_.authenticate(&headers);
    try std.testing.expectError(error.InvalidAuth, err);

    headers.raze(a);
    headers = Headers.init();

    try headers.addCustom(a, "MTLS_ENABLED", "FAILURE!");
    const err2 = provider_.authenticate(&headers);
    try std.testing.expectError(error.UnknownUser, err2);
    // TODO there's likely a few more error states we should validate;
}

const std = @import("std");
const log = std.log.scoped(.verse);
const Provider = @import("provider.zig");
const User = @import("user.zig");
const Error = @import("../auth.zig").Error;
const Headers = @import("../headers.zig");
