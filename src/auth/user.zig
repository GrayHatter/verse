//! Auth.User is a thick user wrapper used within Auth.Provider and the other
//! default authentication providers within Verse. Many of the fields here are
//! provided here for convenience and aren't (currently) used within the
//! Providers.

/// Reserved for callers. Never modified by any Verse Provider.
user_ptr: ?*anyopaque = null,
/// Reserved for callers.
/// Verse auth Providers will use unique_id as the primary user lookup
/// identifier. In many cases if a username can never be altered by the user,
/// unique_id can be set to the username. Verse will not do this on it's own
/// because the security implications can be nuanced.
/// unique_id may not contain a \0 char within the slice when used with Verse
/// auth Providers or token modules.
unique_id: ?[]const u8 = null,
/// Reserved for callers.
username: ?[]const u8 = null,

// The following fields are used and modified by Verse Providers.

/// The **currently* active session for the user. The session that was used to
/// create the object. Often or likely included with the current user request.
/// May be the same as session_next.
/// See also: next_session
session_current: ?[]const u8 = null,
/// Newly created, and expected to be the session used with the next request
/// (when possible).
/// See also: session_current
session_next: ?[]const u8 = null,

/// session_extra_data is embedded within the session token which is returned in
/// clear text back to client
session_extra_data: ?[]const u8 = null,

const User = @This();

pub fn valid(_: *User) bool {
    return false;
}
