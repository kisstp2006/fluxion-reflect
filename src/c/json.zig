// SPDX-License-Identifier: BSL-1.0

//! `include/fluxion_reflect/json.h`: values as JSON or CBOR, through
//! fluxion-json.

const std = @import("std");
const fluxion_json = @import("fluxion_json");

const reflect_json = @import("../json.zig");
const base = @import("base.zig");
const Value = @import("../value.zig").Value;
const Status = base.Status;
const done = base.done;

pub const Options = extern struct {
    indent: u8 = 0,
    sort_keys: bool = false,
    skip_defaults: bool = false,
    skip_nulls: bool = false,
    cbor: bool = false,
};

export fn fxr_value_to_json(v: *const Value, options: ?*const Options, buffer: ?[*]u8, capacity: usize, needed: ?*usize) Status {
    const o: Options = if (options) |given| given.* else .{};
    var clip: base.Clip = .init(buffer, capacity);
    var w: fluxion_json.Writer = .init(&clip.writer, .{
        .indent = o.indent,
        .sort_keys = o.sort_keys,
        .skip_defaults = o.skip_defaults,
        .skip_nulls = o.skip_nulls,
        .format = if (o.cbor) .cbor else .json,
    });
    const status = done(reflect_json.write(&w, v.*));
    const total = if (o.cbor) clip.total else clip.finish();
    if (needed) |n| n.* = total;
    return status;
}

export fn fxr_value_from_json(v: *const Value, source: ?[*]const u8, len: usize, arena: ?*std.heap.ArenaAllocator) Status {
    const a = arena orelse return .null;
    const bytes = if (source) |s| s[0..len] else "";
    return done(reflect_json.parse(v.*, bytes, .{ .allocator = a.allocator() }));
}
