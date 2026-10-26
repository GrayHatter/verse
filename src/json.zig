//! The stdlib version of json has some features and design decisions that make
//! it incompatible with untrusted user input. Verse will eventually provide a
//! hardened version. For now, it's a thin shim into std.json.

pub const Value = stdjson.Value;
pub const fmt = stdjson.fmt;
pub const parseFromSlice = stdjson.parseFromSlice;

pub const stdjson = std.json;

const std = @import("std");
