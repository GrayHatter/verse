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
pub const Cookie = CookieAuth(Hmac.sha2.HmacSha256);

pub const cookie_auth = struct {
    /// Why are you using sha1?
    pub const sha1 = CookieAuth(Hmac.HmacSha1);

    pub const sha2 = struct {
        pub const @"224" = CookieAuth(Hmac.sha2.HmacSha224);
        pub const @"256" = CookieAuth(Hmac.sha2.HmacSha256);
        pub const @"384" = CookieAuth(Hmac.sha2.HmacSha384);
        pub const @"512" = CookieAuth(Hmac.sha2.HmacSha512);
    };
};

/// TODO document
pub fn CookieAuth(HMAC: type) type {
    return struct {
        base: ?Provider,
        // TODO key safety
        server_secret_key: []const u8,
        /// Max age in seconds a session cookie is valid for.
        max_age: usize,
        cookie_name: []const u8,

        /// this session buffer API is unstable and may be replaced
        session_buffer: [ibuf_size]u8 = [_]u8{0} ** ibuf_size,
        alloc: ?Allocator,
        const ibuf_size = b64_enc.calcSize(HMAC.mac_length * 8);

        pub const Self = @This();

        pub const Token = struct {
            version: i8,
            time: [8]u8,
            userid: []const u8,
            extra_data: ?[]const u8,
            mac: [HMAC.mac_length]u8,

            /// Negative version numbers are reserved for users
            pub const Version: i8 = 0;
        };

        pub fn init(opts: struct {
            server_secret_key: []const u8,
            alloc: ?Allocator = null,
            base: ?Provider = null,
            max_age: usize = 86400 * 365,
            cookie_name: []const u8 = "verse_session_secret",
        }) Self {
            return .{
                .server_secret_key = opts.server_secret_key,
                .alloc = opts.alloc,
                .base = opts.base,
                .max_age = opts.max_age,
                .cookie_name = opts.cookie_name,
            };
        }

        pub fn validateToken(hm: *HMAC, b64data: []const u8, user_buffer: []u8) Error![]u8 {
            var buffer: [ibuf_size]u8 = undefined;
            const len = b64_dec.calcSizeForSlice(b64data) catch return error.InvalidAuth;
            if (len > ibuf_size) return error.InvalidAuth;
            b64_dec.decode(buffer[0..len], b64data) catch return error.InvalidAuth;
            const version: i8 = @bitCast(buffer[0]);
            if (version != 0) return error.InvalidAuth;

            var payload: []u8 = buffer[9..len];
            if (payload.len <= HMAC.mac_length) return error.InvalidAuth;
            const mac: [HMAC.mac_length]u8 = payload[payload.len - HMAC.mac_length ..][0..HMAC.mac_length].*;
            payload = payload[0 .. payload.len - HMAC.mac_length];

            if (indexOfScalar(u8, payload, ':')) |i| {
                var t = Token{
                    .version = version,
                    .time = buffer[1..9].*,
                    .userid = payload[0..i],
                    .extra_data = if (indexOfScalar(u8, payload[i + 1 ..], ':')) |ed| payload[1 + ed ..] else null,
                    .mac = mac,
                };

                var our_hash: [HMAC.mac_length]u8 = undefined;
                hm.update(t.time[0..]);
                hm.update(t.userid);
                if (t.extra_data) |ed| hm.update(ed);
                hm.final(our_hash[0..]);
                if (constTimeEql([HMAC.mac_length]u8, t.mac, our_hash)) {
                    if (user_buffer.len < t.userid.len) return error.NoSpaceLeft;
                    @memcpy(user_buffer[0..t.userid.len], t.userid);
                    return user_buffer[0..t.userid.len];
                }

                return error.InvalidAuth;
            } else return error.InvalidAuth;
            return error.InvalidAuth;
        }

        pub fn authenticate(ptr: *anyopaque, headers: *const Headers) Error!User {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| {
                // If base provider offers authenticate, we should defer to it
                if (base.vtable.authenticate) |_| {
                    return base.authenticate(headers);
                }

                if (headers.get("Cookie")) |cookies| {
                    // This actually isn't technically invalid, it's only
                    // currently not implemented.
                    if (cookies.value_list.next != null) return error.InvalidAuth;
                    const cookie = cookies.value_list.value;
                    std.debug.print("cookie: {s} \n", .{cookie});
                    var itr = tokenizeSequence(u8, cookie, "; ");
                    while (itr.next()) |tkn| {
                        if (startsWith(u8, tkn, ca.cookie_name)) {
                            var un_buf: [64]u8 = undefined;
                            var hmac = HMAC.init(ca.server_secret_key);
                            const username = try validateToken(
                                &hmac,
                                tkn[ca.cookie_name.len + 1 ..],
                                un_buf[0..],
                            );

                            return base.lookupUser(username);
                        }
                    }
                } else {
                    std.debug.print("no cookie\n{any}", .{headers});
                }
            }

            return error.UnknownUser;
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

        pub fn mkToken(hm: *HMAC, token: []u8, user: *const User) Error!usize {
            var buffer: [Self.ibuf_size]u8 = [_]u8{0} ** Self.ibuf_size;
            buffer[0] = Token.Version;
            var b: []u8 = buffer[1..];
            const time = toBytes(nativeToLittle(i64, std.time.timestamp()));
            hm.update(time[0..8]);
            @memcpy(b[0..8], time[0..8]);
            b = b[8..];

            if (user.username) |un| {
                if (un.len > b.len - HMAC.mac_length - 1) return error.NoSpaceLeft;
                hm.update(un);
                @memcpy(b[0..un.len], un);
                b[un.len] = ':';
                b = b[un.len + 1 ..];
            }

            if (user.session_extra_data) |ed| {
                if (ed.len > b.len - HMAC.mac_length - 1) return error.NoSpaceLeft;
                hm.update(ed);
                @memcpy(b[0..ed.len], ed);
                b[ed.len] = ':';
                b = b[ed.len + 1 ..];
            }
            hm.final(b[0..HMAC.mac_length]);
            b = b[HMAC.mac_length..];

            const final = buffer[0 .. buffer.len - b.len];
            if (token.len < b64_enc.calcSize(final.len)) return error.NoSpaceLeft;
            return b64_enc.encode(token, final).len;
        }

        pub fn createSession(ptr: *anyopaque, user: *User) Error!void {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| base.createSession(user) catch |e| switch (e) {
                error.NotProvided => {},
                else => return e,
            };

            const prefix_len: usize = (if (user.username) |u| u.len + 1 else 0) +
                if (user.session_extra_data) |ed| ed.len + 1 else 0;
            if (prefix_len > ca.session_buffer.len / 2) {
                if (ca.alloc == null) return error.NoSpaceLeft;
                return error.NoSpaceLeft;
            }

            var hmac = HMAC.init(ca.server_secret_key);
            const len = try mkToken(&hmac, ca.session_buffer[0..], user);
            user.session_next = ca.session_buffer[0..len];
        }

        pub fn getCookie(ptr: *anyopaque, user: User) Error!?ReqCookie {
            const ca: *Self = @ptrCast(@alignCast(ptr));
            if (ca.base) |base| if (base.vtable.get_cookie) |_| {
                return base.getCookie(user);
            };

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

test Cookie {
    const a = std.testing.allocator;
    var auth = Cookie.init(.{
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
    try std.testing.expectStringStartsWith(cookie.?.value[9..], "AAAdGVzdGluZyB1c2VyO");
    var dec_buf: [88]u8 = undefined;
    const len = try b64_dec.calcSizeForSlice(cookie.?.value);
    try b64_dec.decode(dec_buf[0..len], cookie.?.value);
    const decoded = dec_buf[0..len];
    try std.testing.expectStringStartsWith(decoded[9..], "testing user:");
}

test "Cookie ExtraData" {
    const a = std.testing.allocator;
    var auth = Cookie.init(.{
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
    try std.testing.expectStringStartsWith(cookie.?.value[9..], "AAAdGVzdGluZyB1c2VyOmV4dHJhIGRhdGE");

    var dec_buf: [89]u8 = undefined;
    const len = try b64_dec.calcSizeForSlice(cookie.?.value);
    try b64_dec.decode(dec_buf[0..len], cookie.?.value);
    const decoded = dec_buf[0..len];
    try std.testing.expectStringStartsWith(decoded[9..], "testing user:");
    try std.testing.expectStringStartsWith(decoded[22..], "extra data:");
}

test "Cookie token" {
    const a = std.testing.allocator;
    var auth = Cookie.init(.{
        .alloc = a,
        .server_secret_key = "This may surprise you; but this secret_key is more secure than most of the secret keys in prod use",
    });
    const provider = auth.provider();

    var user = User{ .username = "testing user" };

    try provider.createSession(&user);

    try std.testing.expect(user.session_next != null);
    const cookie = try provider.getCookie(user);

    try std.testing.expect(cookie != null);
    try std.testing.expectStringStartsWith(cookie.?.value[9..], "AAAdGVzdGluZyB1c2VyO");

    var username_buf: [64]u8 = undefined;
    var hm = Hmac.sha2.HmacSha256.init(auth.server_secret_key);
    const valid = try Cookie.validateToken(&hm, cookie.?.value, username_buf[0..]);
    try std.testing.expectEqualStrings(user.username.?, valid);
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

const std = @import("std");
const Allocator = std.mem.Allocator;
const toBytes = std.mem.toBytes;
const startsWith = std.mem.startsWith;
const nativeToLittle = std.mem.nativeToLittle;
const indexOfScalar = std.mem.indexOfScalar;
const tokenizeSequence = std.mem.tokenizeSequence;
const Hmac = std.crypto.auth.hmac;
const b64_enc = std.base64.url_safe.Encoder;
const b64_dec = std.base64.url_safe.Decoder;
const ReqCookie = @import("cookies.zig").Cookie;
const Headers = @import("headers.zig");
// Verse.Auth attempts to provide strong security guarantees where reasonable
// e.g. std.mem.eql faster, but doesn't work in constant time. In an effort to
// avoid confusion, the two comparison functions are given possibly misleading
// names to encourage closer inspection and annotation over which is being used,
// and how it's safe to do so.
const unsafeEql = std.mem.eql;
const constTimeEql = std.crypto.utils.timingSafeEql;
