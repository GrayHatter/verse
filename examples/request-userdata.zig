const Endpoints = verse.Endpoints(.{
    struct {
        pub const verse_name = .root;
        pub fn index(frame: *verse.Frame) !void {
            try frame.quickStart();
            try frame.sendRawSlice("hello world");
        }
    },
});

pub fn main() !void {
    var endpoints = Endpoints.init(std.heap.page_allocator);
    endpoints.serve(.{
        .mode = .{ .http = .{ .port = 8084 } },
    }) catch |err| {
        std.log.err("Unable to serve endpoints! err: [{}]", .{err});
        @panic("endpoint error");
    };
}

const std = @import("std");
const verse = @import("verse");
