//! Verse: The framework.
//!
pub const auth = @import("auth.zig");
pub const abx = @import("antibiotic.zig");
pub const template = @import("template.zig");

pub const ContentType = @import("content-type.zig");
pub const Frame = @import("frame.zig");
pub const Headers = @import("headers.zig");
pub const Request = @import("request.zig");
pub const RequestData = @import("request-data.zig");
pub const Router = @import("router.zig");
pub const Server = @import("server.zig");

const cookies = @import("cookies.zig");
pub const Cookie = cookies.Cookie;

pub const fileOnDisk = @import("static-file.zig").fileOnDisk;

const endpoint = @import("endpoint.zig");
pub const Endpoints = endpoint.Endpoints;

const errors = @import("errors.zig");
pub const RoutingError = Router.RoutingError;
pub const ServerError = errors.ServerError;
pub const ClientError = errors.ClientError;
pub const NetworkError = errors.NetworkError;
pub const Error = errors.Error;

comptime {
    // Actually build docs
    _ = &@This();
}

test "verse" {
    std.testing.refAllDecls(@This());
}

const std = @import("std");
