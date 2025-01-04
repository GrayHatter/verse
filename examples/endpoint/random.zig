pub const verse_name = .random;

var Random = std.Random.DefaultPrng.init(31337);
var random = Random.random();

pub const verse_routes = [_]Router.Match{
    Router.GET("number", number),
    Router.GET("quote", quote),
};

fn number(frame: *Frame) !void {
    try frame.quickStart();
    var buffer: [0xff]u8 = undefined;
    try frame.sendRawSlice(try std.fmt.bufPrint(&buffer, "{}", .{random.int(usize)}));
}

const quotes = enum {
    @"You can't take the sky from me",
    @"Curse your sudden but inevitable betrayal!",
    @"I swear by my pretty floral bonnet, I will end you!",
    @"I’m thinking you weren’t burdened with an overabundance of schooling",
    @"Well, look at this! Appears we got here just in the nick of time. What does that make us? -- Big damn heroes, sir.",
    @"It is, however, somewhat fuzzier on the subject of kneecaps",
    @"When you can't run anymore, you crawl... and when you can't do that -- You find someone to carry you.",
    @"My food is problematic!",
};

fn quote(frame: *Frame) !void {
    try frame.quickStart();
    const rand_quote = @tagName(random.enumValue(quotes));
    try frame.sendRawSlice("<p>");
    try frame.sendRawSlice(rand_quote);
    try frame.sendRawSlice("</p>");
}

const std = @import("std");
const verse = @import("verse");
const Frame = verse.Frame;
const Router = verse.routing.Router;
