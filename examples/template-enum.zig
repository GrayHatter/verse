//! Example of a comptime template using the extended (non-stable) syntax
const ExampleEnumPage = PageData("templates/example-enum.html");
var global_number: u8 = 1; // Wanted to write 2, but off by one errors are common

fn index(frame: *verse.Frame) Router.Error!void {
    defer global_number = (global_number + 1) % 5;
    var page = ExampleEnumPage.init(.{
        .enum_name = switch (global_number) {
            0 => .settings,
            1 => .admin,
            2 => .thingy,
            3 => .example,
            4 => .nullish,
            else => unreachable,
        },
    });

    try frame.sendPage(&page);
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var server = try verse.Server.init(alloc, routes, .{
        .mode = .{ .http = .{ .port = 8082 } },
    });

    server.serve() catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

const routes = Router.Routes(&[_]Router.Match{
    Router.GET("", index),
});

const std = @import("std");
const verse = @import("verse");
const PageData = verse.template.PageData;
const Router = verse.Router;
