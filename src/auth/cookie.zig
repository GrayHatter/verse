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

/// Default cookie based auth constructor. Turns the provided HMAC signature
/// code into a session token to confirm a user's identity. Verification and
/// authorization are not provided by this module, and are the responsibility of
/// the caller. The most common usecase would be calling app would verify a
/// user's identity using it's own user credential verification and then store
/// that confirmed authentication as a cookie using this CookieAuth provider.
pub fn CookieAuth(HMAC: type) type {
    return struct {
        base: ?Provider,
        // TODO consider expanding key memory safety here. The costs associated
        // with lock locking, or zeroing the memory seem high for the security
        // improvements, but this may not always be the case.
        server_secret_key: []const u8,
        /// Max age in seconds a session cookie is valid for.
        max_age: i64,
        cookie_name: []const u8,

        /// this session buffer API is unstable and may be replaced
        session_buffer: [ibuf_size]u8 = [_]u8{0} ** ibuf_size,
        alloc: ?Allocator,
        const ibuf_size = b64_enc.calcSize(HMAC.mac_length * 8);

        pub const Self = @This();

        pub const Token = struct {
            version: i8,
            time: [8]u8 align(8),
            userid: []const u8,
            extra_data: ?[]const u8,
            mac: [HMAC.mac_length]u8,

            /// Negative version numbers are reserved for users
            pub const Version: i8 = 0;

            pub fn expired(t: Token, max_age: i64) bool {
                const time = littleToNative(i64, @as(*const i64, @ptrCast(&t.time)).*);
                if (time > std.time.timestamp() + max_age) return true;
                return false;
            }
        };

        pub fn init(opts: struct {
            server_secret_key: []const u8,
            alloc: ?Allocator = null,
            base: ?Provider = null,
            max_age: i64 = 86400 * 365,
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

        pub fn validateToken(hm: *HMAC, b64data: []const u8, user_buffer: []u8, maxage: i64) Error![]u8 {
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

            if (indexOfScalar(u8, payload, 0x00)) |i| {
                var t = Token{
                    .version = version,
                    .time = buffer[1..9].*,
                    .userid = payload[0..i],
                    .extra_data = if (indexOfScalar(u8, payload[i + 1 ..], 0x00)) |ed| payload[1 + ed ..] else null,
                    .mac = mac,
                };

                var our_hash: [HMAC.mac_length]u8 = undefined;
                hm.update(t.time[0..]);
                hm.update(t.userid);
                if (t.extra_data) |ed| hm.update(ed);
                hm.final(our_hash[0..]);
                if (timing_safe.eql([HMAC.mac_length]u8, t.mac, our_hash)) {
                    if (t.expired(maxage)) return error.TokenExpired;
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

                if (headers.getCustom("Cookie")) |cookies| {
                    // This actually isn't technically invalid, it's only
                    // currently not implemented.
                    if (cookies.list.len > 1) return error.InvalidAuth;
                    const cookie = cookies.list[0];
                    var itr = tokenizeSequence(u8, cookie, "; ");
                    while (itr.next()) |tkn| {
                        if (startsWith(u8, tkn, ca.cookie_name)) {
                            var un_buf: [64]u8 = undefined;
                            var hmac = HMAC.init(ca.server_secret_key);
                            const user_id = try validateToken(
                                &hmac,
                                tkn[ca.cookie_name.len + 1 ..],
                                un_buf[0..],
                                ca.max_age,
                            );

                            return base.lookupUser(user_id);
                        }
                    }
                }
            }

            return error.UnknownUser;
        }

        pub fn valid(ptr: *const anyopaque, user: *const User) bool {
            const ca: *const Self = @ptrCast(@alignCast(ptr));
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

            if (user.unique_id) |uid| {
                if (uid.len > b.len - HMAC.mac_length - 1) return error.NoSpaceLeft;
                hm.update(uid);
                @memcpy(b[0..uid.len], uid);
                b[uid.len] = 0x00;
                b = b[uid.len + 1 ..];
            } else return error.UnknownUser;

            if (user.session_extra_data) |ed| {
                if (ed.len > b.len - HMAC.mac_length - 1) return error.NoSpaceLeft;
                hm.update(ed);
                @memcpy(b[0..ed.len], ed);
                b[ed.len] = 0x00;
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

            const prefix_len: usize = (if (user.unique_id) |u| u.len + 1 else 0) +
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
    var ath = Cookie.init(.{
        .alloc = a,
        .server_secret_key = "This may surprise you; but this secret_key is more secure than most of the secret keys in prod use",
    });
    const provider = ath.provider();

    var user = User{
        .unique_id = "testing user",
    };

    try provider.createSession(&user);

    try std.testing.expect(user.session_next != null);
    const cookie = try provider.getCookie(user);

    try std.testing.expect(cookie != null);
    try std.testing.expectStringStartsWith(cookie.?.value, user.session_next.?);
    try std.testing.expectEqual(12 + 18 + 42, cookie.?.value.len);
    try std.testing.expectStringStartsWith(cookie.?.value[9..], "AAAdGVzdGluZyB1c2VyA");
    var dec_buf: [88]u8 = undefined;
    const len = try b64_dec.calcSizeForSlice(cookie.?.value);
    try b64_dec.decode(dec_buf[0..len], cookie.?.value);
    const decoded = dec_buf[0..len];
    try std.testing.expectStringStartsWith(decoded[9..], "testing user\x00");
}

test "Cookie ExtraData" {
    const a = std.testing.allocator;
    var ath = Cookie.init(.{
        .alloc = a,
        .server_secret_key = "This may surprise you; but this secret_key is more secure than most of the secret keys in prod use",
    });
    const provider = ath.provider();

    var user = User{
        .unique_id = "testing user",
        .session_extra_data = "extra data",
    };

    try provider.createSession(&user);

    try std.testing.expect(user.session_next != null);
    const cookie = try provider.getCookie(user);

    try std.testing.expect(cookie != null);
    try std.testing.expectStringStartsWith(cookie.?.value, user.session_next.?);
    try std.testing.expectEqual(12 + 18 + 16 + 42, cookie.?.value.len);
    try std.testing.expectStringStartsWith(cookie.?.value[9..], "AAAdGVzdGluZyB1c2VyAGV4dHJhIGRhdGE");

    var dec_buf: [89]u8 = undefined;
    const len = try b64_dec.calcSizeForSlice(cookie.?.value);
    try b64_dec.decode(dec_buf[0..len], cookie.?.value);
    const decoded = dec_buf[0..len];
    try std.testing.expectStringStartsWith(decoded[9..], "testing user\x00");
    try std.testing.expectStringStartsWith(decoded[22..], "extra data\x00");
}

test "Cookie token" {
    const a = std.testing.allocator;
    var ath = Cookie.init(.{
        .alloc = a,
        .server_secret_key = "This may surprise you; but this secret_key is more secure than most of the secret keys in prod use",
    });
    const provider = ath.provider();

    var user = User{ .unique_id = "testing user" };

    try provider.createSession(&user);

    try std.testing.expect(user.session_next != null);
    const cookie = try provider.getCookie(user);

    try std.testing.expect(cookie != null);
    try std.testing.expectStringStartsWith(cookie.?.value[9..], "AAAdGVzdGluZyB1c2VyA");

    var uid_buf: [64]u8 = undefined;
    var hm = Hmac.sha2.HmacSha256.init(ath.server_secret_key);
    const valid = try Cookie.validateToken(&hm, cookie.?.value, uid_buf[0..], 2);
    try std.testing.expectEqualStrings(user.unique_id.?, valid);

    hm = Hmac.sha2.HmacSha256.init(ath.server_secret_key);
    const expired = Cookie.validateToken(&hm, cookie.?.value, uid_buf[0..], -100);
    try std.testing.expectError(error.TokenExpired, expired);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const Hmac = std.crypto.auth.hmac;
const nativeToLittle = std.mem.nativeToLittle;
const littleToNative = std.mem.littleToNative;
const indexOfScalar = std.mem.indexOfScalar;
const tokenizeSequence = std.mem.tokenizeSequence;
const startsWith = std.mem.startsWith;
const toBytes = std.mem.toBytes;

const b64_enc = std.base64.url_safe.Encoder;
const b64_dec = std.base64.url_safe.Decoder;

const auth = @import("../auth.zig");
const Provider = @import("Provider.zig");
const User = @import("user.zig");
const Error = auth.Error;
const Headers = @import("../headers.zig");
const ReqCookie = @import("../cookies.zig").Cookie;
const unsafe = auth.unsafe;
const timing_safe = auth.timing_safe;
