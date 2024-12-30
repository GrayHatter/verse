pub const Template = @This();

name: []const u8 = "undefined",
blob: []const u8,
parent: ?*const Template = null,

pub fn pageOf(self: Template, comptime Kind: type, data: Kind) PageRuntime(Kind) {
    return PageRuntime(Kind).init(.{ .name = self.name, .blob = self.blob }, data);
}

pub fn format(_: Template, comptime _: []const u8, _: anytype, _: anytype) !void {
    comptime unreachable;
}

const PageRuntime = @import("page.zig").PageRuntime;
