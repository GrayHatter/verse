//! Auth.User is a thick user wrapper used within Auth.Provider and the other
//! default authentication providers within Verse. Many of the fields here are
//! provided here for convenience and aren't (currently) used within the
//! Providers.

/// Managed by callers, may be used by Verse assumed to be globally unique
/// Verse auth Providers will use unique_id as the primary user lookup
/// identifier. In many cases if a username can never be altered by the user,
/// unique_id can be set to the username. Verse will not do this on it's own
/// because the security implications can be nuanced.
/// `unique_id` may not contain a \0 char within the slice when used with Verse
/// auth Providers or token modules.
unique_id: ?[]const u8,

/// Reserved for callers, Unused by Verse
username: ?[]const u8 = null,

// The following fields may be modified by Verse

/// User has authenticated successfully. Verse assumes this to be true IFF the
/// user has provided valid credentials for the currently active session. And
/// false when this user was created by an admin lookup function.
authenticated: bool = false,

/// The **currently** active session for the user. The session that was used to
/// create the object. Often or likely included with the current user request.
/// May be the same as session_next. See also: next_session
session_current: ?[]const u8 = null,

/// Newly created, and assumed to be the session used with the next request
/// (when possible). e.g. during a reauth. See also: session_current
session_next: ?[]const u8 = null,

/// session_extra_data is embedded within the session token which is returned in
/// clear text back to client
session_extra_data: ?[]const u8 = null,

/// Reserved for callers. Unused by Verse
user_ptr: ?*anyopaque = null,

/// Provider used to create this User, or the Provider that should be used to
/// validate or look up details about this User.
origin_provider: ?*const Provider = null,

const User = @This();

pub const invalid_user: User = .{
    .unique_id = null,
};

pub fn valid(u: *const User) bool {
    if (comptime builtin.mode == .Debug) {
        if (u.origin_provider == null)
            @panic("It is IB to call user.valid() without an origin_provider");
    }
    if (u.unique_id == null) return false;
    if (u.origin_provider) |provider| return provider.valid(u);
    return false;
}

const Provider = @import("Provider.zig");
const builtin = @import("builtin");
