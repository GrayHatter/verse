pub const Endpoint = struct {
    pub const verse_name = .@".well-known";

    pub const verse_routes = [_]Router.Match{
        Router.GET("atproto-did", atprotoDid),
        Router.GET("security.txt", security),
        Router.GET("traffic-advice", trafficAdvice),
    };

    fn atprotoDid(f: *Frame) Router.Error!void {
        return f.sendDefaultErrorPage(.not_found);
    }

    fn security(f: *Frame) Router.Error!void {
        f.status = .ok;
        f.content_type = .text;
        f.sendHeaders(.close);
        f.downstream.writer.writeAll("security.txt is not provided for this site.");
    }

    fn trafficAdvice(f: *Frame) Router.Error!void {
        return f.sendDefaultErrorPage(.not_found);
    }

    const std = @import("std");
    const Frame = @import("frame.zig");
    const Router = @import("router.zig");
};
