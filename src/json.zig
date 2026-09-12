// SPDX-License-Identifier: BSL-1.0

//! Values as JSON and CBOR, through fluxion-json, for types known at run time.
//!
//! Spelt exactly as fluxion-json spells the Zig type - structs as objects,
//! enums by name, tagged unions as `{"arm": payload}`, `json_rename`,
//! `json_case`, `json_ignore` and `json_tag` honoured - so what one side
//! writes, the other reads. The declarations reach this code as attributes the
//! compiler attaches to the descriptor. What only compile time can do is
//! refused rather than done differently: a type with `toJson` or `fromJson`,
//! and a hash map.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = @import("fluxion_json");

const writing = @import("json/write.zig");
const reading = @import("json/read.zig");

/// The key a field, arm or member is written under, from `json_rename` or
/// `json_case`.
pub const Name = struct { text: []const u8 };
/// Never read or written: `json_ignore`.
pub const Ignored = struct {};
/// A union written as one object, `{"<key>": "arm", ...}`: `json_tag`.
pub const Tag = struct { key: []const u8 };
/// A `std.ArrayList`, written as its items.
pub const Items = struct {};
/// A type with `toJson` or `fromJson`, which only compile time can call.
pub const Hooked = struct {};
/// A string-keyed standard library map, which only compile time can walk.
pub const Map = struct {};

pub const WriteError = json.Writer.Error || error{Unsupported};
pub const ReadError = json.Error || error{Unsupported};

pub const ReadOptions = struct {
    /// Where strings, slices and pointed-at values go. What a failed read
    /// allocated is not given back: read into an arena.
    allocator: Allocator,
    syntax: json.Syntax = .json,
    format: ?json.Format = null,
    max_depth: u16 = 512,
    unknown_fields: json.UnknownFields = .ignore,
    /// Keep what a field the text leaves out held, where fluxion-json would
    /// give it its default, or refuse when it has none.
    patch: bool = false,
    diagnostics: ?*json.Diagnostics = null,
};

pub const write = writing.write;
pub const stringify = writing.stringify;
pub const parse = reading.parse;
pub const read = reading.read;
