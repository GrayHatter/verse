const Auth = @This();

pub const Provider = @import("auth/provider.zig");
pub const User = @import("auth/user.zig");

pub const Error = error{
    InvalidAuth,
    NotProvided,
    Unauthenticated,
    UnknownUser,
    NoSpaceLeft,
    OutOfMemory,
};

/// TODO document
pub const MTLS = struct {
    base: ?Provider = null,

    /// TODO document misuse of default without a base provider
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
                .create_session = null,
                .get_cookie = null,
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

/// Default CookieAuth Helper uses Sha256 as the HMAC primitive.
pub const CookieAuth = cookieAuth(hmac.sha2.HmacSha256);

pub const cookie_auth = struct {
    /// Why are you using sha1?
    pub const sha1 = cookieAuth(hmac.HmacSha1);

    pub const sha2 = struct {
        pub const @"224" = cookieAuth(hmac.sha2.HmacSha224);
        pub const @"256" = cookieAuth(hmac.sha2.HmacSha256);
        pub const @"384" = cookieAuth(hmac.sha2.HmacSha384);
        pub const @"512" = cookieAuth(hmac.sha2.HmacSha512);
    };
};

/// TODO document
pub fn cookieAuth(Hmac: type) type {
    return struct {
        hmac: ?Hmac,
        base: ?Provider,
        // we don't currently store the key, but we may need to because it's not
        // stored within hmac after init
        //server_secret_key: []const u8,
        /// Max age in seconds a session cookie is valid for.
        max_age: usize,
        cookie_name: []const u8 = "verse_session_secret",

        /// this session buffer API is unstable and may be replaced
        session_buffer: [ibuf_size]u8 = [_]u8{0} ** ibuf_size,
        alloc: ?Allocator,
        const ibuf_size = b64_enc.calcSize(Hmac.mac_length * 8);

        pub const Self = @This();

        pub fn init(opts: struct {
            alloc: ?Allocator = null,
            base: ?Provider = null,
            server_secret_key: []const u8,
            max_age: usize = 86400 * 365,
        }) Self {
            return .{
                .hmac = Hmac.init(opts.server_secret_key),
                .base = opts.base,
                .max_age = opts.max_age,
                .alloc = opts.alloc,
            };
        }

        pub fn authenticate(ptr: *anyopaque, headers: *const Headers) Error!User {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| {
                if (headers.get("Cookie")) |cookies| {
                    if (cookies.value_list.next != null) return error.InvalidAuth;
                    const cookie = cookies.value_list.value;
                    std.debug.print("cookie: {s} \n", .{cookie});
                    if (std.mem.indexOf(u8, cookie, ca.cookie_name)) |i| {
                        return base.lookupUser(cookie[i..]);
                    }
                }
            }
            return .{ .user_ptr = null };
        }

        pub fn valid(ptr: *anyopaque, user: *const User) bool {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| return base.valid(user);
            return false;
        }

        pub fn lookupUser(ptr: *anyopaque, user_id: []const u8) Error!User {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| return base.lookupUser(user_id);
            return error.UnknownUser;
        }

        pub fn mkToken(hm: *Hmac, token: []u8, user: *const User) Error!usize {
            const time = toBytes(nativeToLittle(i64, std.time.timestamp()));

            var buffer: [Self.ibuf_size]u8 = [_]u8{0} ** Self.ibuf_size;
            var b: []u8 = buffer[0..];
            hm.update(time[0..8]);
            @memcpy(b[0..8], time[0..8]);
            b = b[8..];

            if (user.username) |un| {
                hm.update(un);
                @memcpy(b[0..un.len], un);
                b[un.len] = ':';
                b = b[un.len + 1 ..];
            }
            if (user.session_extra_data) |ed| {
                hm.update(ed);
                @memcpy(b[0..ed.len], ed);
                b[ed.len] = ':';
                b = b[ed.len + 1 ..];
            }
            hm.final(b[0..Hmac.mac_length]);
            b = b[Hmac.mac_length..];

            const final = buffer[0 .. buffer.len - b.len];
            if (token.len < b64_enc.calcSize(final.len)) return error.NoSpaceLeft;
            return b64_enc.encode(token, final).len;
        }

        pub fn createSession(ptr: *anyopaque, user: *User) Error!void {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| try base.createSession(user);

            const prefix_len: usize = (if (user.username) |u| u.len + 1 else 0) +
                if (user.session_extra_data) |ed| ed.len + 1 else 0;
            if (prefix_len > ca.session_buffer.len / 2) {
                if (ca.alloc == null) return error.NoSpaceLeft;
                return error.NoSpaceLeft;
            }

            const len = try mkToken(&ca.hmac.?, ca.session_buffer[0..], user);
            user.session_next = ca.session_buffer[0..len];
        }

        pub fn getCookie(ptr: *anyopaque, user: User) Error!?Cookie {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| return base.getCookie(user);

            if (user.session_next) |next| {
                return .{
                    .name = "verse_session_secret",
                    .value = next,
                    .attr = .{
                        // TODO only set when HTTPS is enabled
                        .secure = true,
                        .same_site = .strict,
                    },
                };
            }
            return null;
        }

        pub fn provider(ca: *Self) Provider {
            return .{
                .ctx = ca,
                .vtable = .{
                    .authenticate = authenticate,
                    .valid = valid,
                    .lookup_user = lookupUser,
                    .create_session = createSession,
                    .get_cookie = getCookie,
                },
            };
        }
    };
}

test CookieAuth {
    const a = std.testing.allocator;
    {
        var auth = CookieAuth.init(.{
            .alloc = a,
            .server_secret_key = "This may surprise you; but this secret_key is more secure than most of the secret keys in prod use",
        });
        const provider = auth.provider();

        var user = User{
            .username = "testing user",
        };

        try provider.createSession(&user);

        try std.testing.expect(user.session_next != null);
        const cookie = try provider.getCookie(user);

        try std.testing.expect(cookie != null);
        try std.testing.expectStringStartsWith(cookie.?.value, user.session_next.?);
        try std.testing.expectEqual(12 + 18 + 42, cookie.?.value.len);
        try std.testing.expectStringStartsWith(cookie.?.value[8..], "AAB0ZXN0aW5nIHVzZXI6");
        var dec_buf: [88]u8 = undefined;
        const len = try b64_dec.calcSizeForSlice(cookie.?.value);
        try b64_dec.decode(dec_buf[0..len], cookie.?.value);
        const decoded = dec_buf[0..len];
        try std.testing.expectStringStartsWith(decoded[8..], "testing user:");
    }

    {
        var auth = CookieAuth.init(.{
            .alloc = a,
            .server_secret_key = "This may surprise you; but this secret_key is more secure than most of the secret keys in prod use",
        });
        const provider = auth.provider();

        var user = User{
            .username = "testing user",
            .session_extra_data = "extra data",
        };

        try provider.createSession(&user);

        try std.testing.expect(user.session_next != null);
        const cookie = try provider.getCookie(user);

        try std.testing.expect(cookie != null);
        try std.testing.expectStringStartsWith(cookie.?.value, user.session_next.?);
        try std.testing.expectEqual(12 + 18 + 16 + 42, cookie.?.value.len);
        try std.testing.expectStringStartsWith(cookie.?.value[8..], "AAB0ZXN0aW5nIHVzZXI6ZXh0cmEgZGF0YT");
        var dec_buf: [88]u8 = undefined;
        const len = try b64_dec.calcSizeForSlice(cookie.?.value);
        try b64_dec.decode(dec_buf[0..len], cookie.?.value);
        const decoded = dec_buf[0..len];
        try std.testing.expectStringStartsWith(decoded[8..], "testing user:");
        try std.testing.expectStringStartsWith(decoded[21..], "extra data:");
    }
}

pub const InvalidAuth = struct {
    pub fn provider() Provider {
        return Provider{
            .ctx = undefined,
            .vtable = .{
                .authenticate = null, // TODO write invalid
                .valid = valid,
                .lookup_user = lookupUser,
                .create_session = null,
                .get_cookie = null,
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
                .create_session = null,
                .get_cookie = null,
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
const toBytes = std.mem.toBytes;
const nativeToLittle = std.mem.nativeToLittle;
const hmac = std.crypto.auth.hmac;
const b64_enc = std.base64.url_safe.Encoder;
const b64_dec = std.base64.url_safe.Decoder;
const Cookie = @import("cookies.zig").Cookie;
const Headers = @import("headers.zig");
