//! Provides a basic example of a rest api using verse.

/// The Verse router can support more complex routing patterns and can
/// route different request methods to separate functions so you can easily
/// expose a custom REST interface/API.
const routes = Router.Routes(&[_]Router.Match{
    Router.GET("users", users),
    Router.POST("users", addUser),
    Router.DELETE("users", deleteUser),
});

const Role = enum {
    user,
    admin,
};

const User = struct {
    id: u32,
    name: []const u8,
    age: u8,
    role: Role,
    active: bool,
};

const CreateUserRequest = struct {
    name: []const u8,
    age: u8,
    role: Role,
    active: bool,
};

var user_list: ArrayListUnmanaged(User) = undefined;
var alloc: std.mem.Allocator = undefined;

/// Returns the list of users.
fn users(frame: *verse.Frame) !void {
    try frame.sendJSON(.ok, user_list.items);
}

/// Adds a new user to the list.
fn addUser(frame: *verse.Frame) !void {
    // validate that the post data is in the expected format
    const request = verse.Request.Data.Validate(CreateUserRequest).init(frame.request.data) catch {
        try frame.sendJSON(.bad_request, .{ .message = "bad request data" });
        return;
    };

    var id: u32 = 1;
    if (user_list.items.len > 0) {
        id = user_list.items[user_list.items.len - 1].id + 1;
    }

    const user = User{
        .id = id,
        .name = try alloc.dupe(u8, request.name),
        .age = request.age,
        .role = request.role,
        .active = request.active,
    };

    try user_list.append(alloc, user);

    try frame.sendJSON(.created, user);
}

/// Deletes a user from the list.
fn deleteUser(frame: *verse.Frame) !void {
    _ = frame.uri.next(); // skip /users

    const id_str = frame.uri.next(); // get the id from the url, if null then the caller didn't provide one
    if (id_str == null) {
        try frame.sendJSON(.bad_request, .{ .message = "missing id" });
        return;
    }

    const id = std.fmt.parseInt(u32, id_str.?, 10) catch {
        try frame.sendJSON(.bad_request, .{ .message = "invalid id" });
        return;
    };

    var found = false;
    for (0..user_list.items.len) |i| {
        const user = user_list.items[i];
        if (user.id == id) {
            _ = user_list.swapRemove(i);
            found = true;
            break;
        }
    }

    if (!found) {
        try frame.sendJSON(.not_found, .{ .message = "user not found" });
        return;
    }

    try frame.sendJSON(.ok, .{ .message = "success" });
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    alloc = gpa.allocator();

    user_list = ArrayListUnmanaged(User){};

    try user_list.append(alloc, .{ .id = 0, .name = "John Doe", .age = 23, .role = .user, .active = true });
    try user_list.append(alloc, .{ .id = 1, .name = "Billy Joe", .age = 25, .role = .user, .active = false });
    try user_list.append(alloc, .{ .id = 2, .name = "Jane Smith", .age = 28, .role = .admin, .active = true });
    defer user_list.deinit(alloc);

    var server = try verse.Server.init(&routes, .default);

    server.serve(alloc) catch |err| {
        std.debug.print("error: {any}", .{err});
        std.process.exit(1);
    };
}

const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;
const verse = @import("verse");
const Router = verse.Router;
