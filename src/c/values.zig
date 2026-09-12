// SPDX-License-Identifier: BSL-1.0

//! `include/fluxion_reflect/values.h`: values made, walked into, read,
//! written, compared, and turned into Zig syntax and back.

const std = @import("std");

const model = @import("../model.zig");
const path = @import("../path.zig");
const base = @import("base.zig");
const Type = model.Type;
const Value = @import("../value.zig").Value;
const Status = base.Status;
const allocator = base.allocator;
const statusOf = base.statusOf;
const done = base.done;
const into = base.into;
const span = base.span;

export fn fxr_value_create(t: *const Type, out: *Value) Status {
    return into(out, Value.create(allocator, t));
}

export fn fxr_value_destroy(v: *const Value) void {
    v.destroy(allocator);
}

export fn fxr_value_field(v: *const Value, name: [*:0]const u8, out: *Value) Status {
    return into(out, v.field(span(name)));
}

export fn fxr_value_field_at(v: *const Value, index: usize, out: *Value) Status {
    return into(out, v.fieldAt(index));
}

export fn fxr_value_index(v: *const Value, index: usize, out: *Value) Status {
    return into(out, v.index(index));
}

export fn fxr_value_len(v: *const Value, out: *usize) Status {
    out.* = v.len() catch |err| return statusOf(err);
    return .ok;
}

export fn fxr_value_path(v: *const Value, spec: [*:0]const u8, out: *Value) Status {
    return into(out, v.path(span(spec)));
}

export fn fxr_value_explain_path(v: *const Value, spec: [*:0]const u8, buffer: ?[*]u8, capacity: usize) usize {
    var clip: base.Clip = .init(buffer, capacity);
    path.explain(v.*, span(spec), &clip.writer) catch {};
    return clip.finish();
}

export fn fxr_value_deref(v: *const Value, out: *Value) Status {
    return into(out, v.deref());
}

export fn fxr_value_is_null(v: *const Value) bool {
    return v.isNull();
}

export fn fxr_value_set_null(v: *const Value) Status {
    return done(v.setNull());
}

export fn fxr_value_unwrap(v: *const Value, out: *Value) Status {
    out.* = v.unwrap() orelse return .null;
    return .ok;
}

export fn fxr_value_unwrap_or_init(v: *const Value, out: *Value) Status {
    return into(out, v.unwrapOrInit());
}

export fn fxr_value_active(v: *const Value) ?*const model.Field {
    return v.active();
}

export fn fxr_value_activate(v: *const Value, arm: [*:0]const u8, out: ?*Value) Status {
    const payload = v.activate(span(arm)) catch |err| return statusOf(err);
    if (out) |o| o.* = payload;
    return .ok;
}

fn missing(v: *const Value) Status {
    return if (v.wideInt() != null or v.type.kind == .float) .out_of_range else .type_mismatch;
}

export fn fxr_value_get_i64(v: *const Value, out: *i64) Status {
    out.* = v.toInt(i64) orelse return missing(v);
    return .ok;
}

export fn fxr_value_get_u64(v: *const Value, out: *u64) Status {
    out.* = v.toInt(u64) orelse return missing(v);
    return .ok;
}

export fn fxr_value_get_f64(v: *const Value, out: *f64) Status {
    out.* = v.toFloat(f64) orelse return .type_mismatch;
    return .ok;
}

export fn fxr_value_get_bool(v: *const Value, out: *bool) Status {
    out.* = v.toBool() orelse return .type_mismatch;
    return .ok;
}

pub const Bytes = extern struct {
    ptr: [*]const u8,
    len: usize,
};

export fn fxr_value_get_string(v: *const Value, out: *Bytes) Status {
    const bytes = v.toString() orelse return .type_mismatch;
    out.* = .{ .ptr = bytes.ptr, .len = bytes.len };
    return .ok;
}

export fn fxr_value_set_i64(v: *const Value, x: i64) Status {
    return done(v.setInt(x));
}

export fn fxr_value_set_u64(v: *const Value, x: u64) Status {
    return done(v.setInt(x));
}

export fn fxr_value_set_f64(v: *const Value, x: f64) Status {
    return done(v.setFloat(x));
}

export fn fxr_value_set_bool(v: *const Value, x: bool) Status {
    return done(v.setBool(x));
}

export fn fxr_value_set_string(v: *const Value, bytes: ?[*]const u8, len: usize) Status {
    const start = bytes orelse return if (len == 0) done(v.setString("")) else .null;
    return done(v.setString(start[0..len]));
}

export fn fxr_value_set_c_string(v: *const Value, bytes: [*:0]const u8) Status {
    return done(v.setStringZ(std.mem.span(bytes)));
}

export fn fxr_value_set_error(v: *const Value, name: [*:0]const u8) Status {
    return done(v.setError(span(name)));
}

export fn fxr_value_error_name(v: *const Value) ?[*:0]const u8 {
    return if (v.errorName()) |name| name.ptr else null;
}

export fn fxr_value_copy(to: *const Value, from: *const Value) Status {
    return done(to.copyFrom(from.*));
}

export fn fxr_value_convert(to: *const Value, from: *const Value) Status {
    return done(to.convertFrom(from.*));
}

export fn fxr_value_eql(a: *const Value, b: *const Value) bool {
    return a.eql(b.*);
}

export fn fxr_value_hash(v: *const Value) u64 {
    return v.hash();
}

export fn fxr_value_format(v: *const Value, buffer: ?[*]u8, capacity: usize) usize {
    var clip: base.Clip = .init(buffer, capacity);
    v.format(&clip.writer) catch {};
    return clip.finish();
}

export fn fxr_value_parse(v: *const Value, source: ?[*]const u8, len: usize, arena: ?*std.heap.ArenaAllocator) Status {
    const bytes = if (source) |s| s[0..len] else "";
    return done(v.parse(bytes, .{ .allocator = if (arena) |a| a.allocator() else null }));
}

export fn fxr_arena_create() ?*std.heap.ArenaAllocator {
    const arena = allocator.create(std.heap.ArenaAllocator) catch return null;
    arena.* = .init(allocator);
    return arena;
}

export fn fxr_arena_destroy(arena: ?*std.heap.ArenaAllocator) void {
    const a = arena orelse return;
    a.deinit();
    allocator.destroy(a);
}
