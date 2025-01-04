//! Verse: The framework.
//!
pub const RequestData = @import("request_data.zig");
const cookies = @import("cookies.zig");
pub const template = @import("template.zig");
const errors = @import("errors.zig");

pub const Frame = @import("frame.zig");
pub const Server = @import("server.zig");
pub const Request = @import("request.zig");
pub const ContentType = @import("content-type.zig");
pub const Headers = @import("headers.zig");

pub const Cookie = cookies.Cookie;

pub const ServerError = errors.ServerError;
pub const ClientError = errors.ClientError;
pub const NetworkError = errors.NetworkError;
pub const Error = errors.Error;

pub const auth = @import("auth.zig");
pub const routing = @import("routing.zig");

test "verse" {
    @import("std").testing.refAllDecls(@This());
}
