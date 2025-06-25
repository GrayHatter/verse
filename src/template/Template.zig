pub const Template = @This();

name: []const u8 = "undefined",
blob: []const u8,
parent: ?*const Template = null,

pub fn pageOf(self: Template, comptime Kind: type, data: Kind) PageRuntime(Kind) {
    return PageRuntime(Kind).init(.{ .name = self.name, .blob = self.blob }, data);
}

pub fn format(t: Template, comptime _: []const u8, _: anytype, out: anytype) !void {
    return try out.print("VerseTemplate{{ name = {s}, blob length = {}}}", .{ t.name, t.blob.len });
}

const PageRuntime = @import("page.zig").PageRuntime;
