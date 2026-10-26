//! Verse: The framework.
//!
pub const Auth = @import("Auth.zig");
pub const Stats = @import("Stats.zig");
pub const template = @import("template.zig");

pub const Antibiotic = @import("Antibiotic");
pub const ContentType = @import("ContentType.zig");
pub const Frame = @import("Frame.zig");
pub const Headers = @import("Headers.zig");
pub const Request = @import("Request.zig");
pub const Robots = @import("Robots.zig");
pub const Router = @import("Router.zig");
pub const Server = @import("Server.zig");
pub const Session = @import("Session.zig");
pub const Uri = @import("Uri.zig");

pub const Cookie = cookies.Cookie;
pub const Endpoints = endpoint.Endpoints;
pub const fileOnDisk = @import("static-file.zig").fileOnDisk;

pub const RoutingError = Router.RoutingError;
pub const ServerError = errors.ServerError;
pub const ClientError = errors.ClientError;
pub const NetworkError = errors.NetworkError;
pub const Error = errors.Error;

pub const testing = @import("testing.zig");

test {
    std.testing.refAllDecls(@This());
    _ = &testing;
    _ = &Frame;
    _ = &Uri;
    _ = &Session;
}

comptime {
    _ = &@This(); // Actually build docs
}

const std = @import("std");
const cookies = @import("cookies.zig");
const endpoint = @import("endpoint.zig");
const errors = @import("errors.zig");
