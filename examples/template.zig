const std = @import("std");
const verse = @import("verse");
const PageData = verse.template.PageData;
const Router = verse.Router;
const BuildFn = Router.BuildFn;

const routes = [_]Router.Match{
    Router.GET("", index),
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const alloc = gpa.allocator();

    var server = try verse.Server.init(alloc, .{
        .mode = .{ .http = .{ .port = 8082 } },
        .router = .{ .routefn = route },
    });

    server.serve() catch |err| {
        std.debug.print("error: {any}", .{err});
        std.posix.exit(1);
    };
}

fn route(frame: *verse.Frame) !BuildFn {
    return Router.router(frame, &routes);
}

// This page template is compiled/prepared at comptime.
const ExamplePage = PageData("templates/example.html");

fn index(frame: *verse.Frame) Router.Error!void {
    var page = ExamplePage.init(.{
        // Simple Variables
        .simple_variable = "This is a simple variable",
        //.required_but_missing = "Currently unused in the html",
        .required_and_provided = "The template requires this from the endpoint",

        // Customized Variables
        // When ornull is used the default null is provided, as the template
        // specifies it can be missing.
        //.null_variable = "Intentionally left blank",
        // The next var could be deleted as the HTML provides a default
        .default_provided = "This is the endpoint provided variable",
        // Commented so the HTML provided default can be used.
        //.default_missing = "This endpoint var could replaced the default",
        .positive_number = 1, // Wanted to write 2, but off by one errors are common

        // Logic based Variables.
        // A default isn't provided for .optional, because With statements, require
        // an explicit decision.
        .optional_with = null,
        .namespaced_with = .{
            .simple_variable = "This is a different variable from above",
        },

        .basic_loop = &.{
            .{ .color = "red", .text = "This color is red" },
            .{ .color = "blue", .text = "This color is blue" },
            .{ .color = "green", .text = "This color is green" },
        },

        .slices = &.{
            "This is simple ",
            "but very useful ",
            "for many types of ",
            "data generation patterns ",
        },

        .include_vars = .{
            .template_name = "<h1>This is the included html</h1>",
            .simple_variable = "This is the simple variable for the included html",
        },
        // Even if the included html has no variables, the field is still required here
        .empty_vars = .{},
    });

    try frame.sendPage(&page);
}
