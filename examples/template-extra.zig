//! Example of a comptime template using the extended (non-stable) syntax

const ExampleExtraPage = PageData("templates/example-extra.html");

var global_number: usize = 1; // Wanted to write 2, but off by one errors are common

const dangerous_string =
    \\<img src="/" =_=" title="onerror='prompt(1)'">
;

fn one(frame: *verse.Frame) Router.Error!void {
    defer global_number +%= 1;
    var page = ExampleExtraPage.init(.{
        .example_switch = .{
            .one = .{
                .data_a = "Yo', I heard Verse got that hot new thing? It's called Switch!",
            },
        },
        .dangerous_content = .abx(dangerous_string),
    });

    try frame.sendPage(&page);
}

fn two(frame: *verse.Frame) Router.Error!void {
    defer global_number +%= 1;
    var page = ExampleExtraPage.init(.{
        .example_switch = .{
            .two = .{
                .data_b = "Don't you wish your Case was hot like me?!",
            },
        },
        .dangerous_content = .abx(dangerous_string),
    });

    try frame.sendPage(&page);
}
fn three(frame: *verse.Frame) Router.Error!void {
    defer global_number +%= 1;
    var page = ExampleExtraPage.init(.{
        .example_switch = .{
            .three = .{
                .data_c = "She's got me swiiiichin'",
                .data_d = "Oh, Switchin' all your Cases on me, on-on me, on me",
            },
        },
        .dangerous_content = .abx(dangerous_string),
    });

    try frame.sendPage(&page);
}

pub fn main(init: std.process.Init) !void {
    const alloc = init.arena.allocator();

    var server = try verse.Server.init(&routes, .default);

    server.serve(alloc) catch |err| {
        std.debug.print("error: {any}", .{err});
        std.process.exit(1);
    };
}

const routes = Router.Routes(&[_]Router.Match{
    Router.GET("", one),
    Router.GET("one", one),
    Router.GET("two", two),
    Router.GET("three", three),
});

const std = @import("std");
const verse = @import("verse");
const PageData = verse.template.PageData;
const Router = verse.Router;
pub const Abx = verse.abx;
