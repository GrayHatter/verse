name: []const u8 = "undefined",
blob: []const u8,
parent: ?*const Template = null,

const Template = @This();

pub fn nameStruct(t: Template, buffer: []u8) []u8 {
    //return nameSlice(std.mem.cutSuffix(u8, t.name, ".html") orelse t.name, buffer);
    return nameSlice(t.name, buffer);
}

pub fn nameStructAlloc(t: Template, a: std.mem.Allocator) ![]u8 {
    var sn_b: [0xff]u8 = undefined;
    const name = t.nameStruct(&sn_b);
    return try a.dupe(u8, name);
}

fn intToWord(in: u8) []const u8 {
    return switch (in) {
        '0' => "Zero",
        '1' => "One",
        '2' => "Two",
        '3' => "Three",
        '4' => "Four",
        '5' => "Five",
        '6' => "Six",
        '7' => "Seven",
        '8' => "Eight",
        '9' => "Nine",
        else => unreachable,
    };
}

pub fn nameSlice(in: []const u8, buffer: []u8) []u8 {
    var name = in;
    if (std.mem.find(u8, in, "/")) |i| {
        name = name[i..];
    }

    var i: usize = 0;
    var next_upper = true;
    for (name) |chr| {
        switch (chr) {
            'a'...'z', 'A'...'Z' => {
                if (next_upper) {
                    buffer[i] = chr & 0b1101_1111;
                } else {
                    buffer[i] = chr;
                }
                next_upper = false;
                i += 1;
            },
            inline '0'...'9' => |x| {
                for (intToWord(x)) |cchr| {
                    buffer[i] = cchr;
                    i += 1;
                }
            },
            '-', '_', '.' => {
                next_upper = true;
            },
            else => {},
        }
    }

    return buffer[0..i];
}

pub fn fieldSlice(in: []const u8, out: []u8) []u8 {
    var i: usize = 0;
    for (in) |chr| {
        switch (chr) {
            'a'...'z' => {
                out[i] = chr;
                i += 1;
            },
            'A'...'Z' => {
                if (i != 0) {
                    out[i] = '_';
                    i += 1;
                }
                out[i] = chr | 0b0010_0000;
                i += 1;
            },
            '0'...'9' => for (intToWord(chr)) |cchr| {
                out[i] = cchr;
                i += 1;
            },
            '-', '_', '.' => {
                out[i] = '_';
                i += 1;
            },
            else => {},
        }
    }

    return out[0..i];
}

const std = @import("std");
const findLast = std.mem.findLast;
