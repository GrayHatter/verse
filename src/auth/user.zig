//! This is a default User provided by Verse. This is almost certainly not what
//! you want.
user_ptr: ?*anyopaque,

/// deprecated do not use
username: []const u8 = undefined,

const User = @This();

pub fn valid(_: *User) bool {
    return false;
}
