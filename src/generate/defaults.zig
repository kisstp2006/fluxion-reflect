// SPDX-License-Identifier: BSL-1.0

//! A type's default, and the other values made at compile time that a
//! descriptor points at - a comptime field's value, an attribute - each
//! given a place in the binary to live.

const std = @import("std");

const model = @import("../model.zig");
const generate = @import("../generate.zig");

const Type = model.Type;
const typeOf = generate.typeOf;

// -------------------------------------------------------------------------
// Values that exist only at compile time, given a place to live
// -------------------------------------------------------------------------

pub const Held = struct {
    type: *const Type,
    value: *const anyopaque,
};

pub fn Static(comptime T: type, comptime value: T) type {
    return struct {
        pub const held: T = value;
    };
}

pub fn hold(comptime T: type, comptime value: T) Held {
    return .{ .type = typeOf(T), .value = @ptrCast(&Static(T, value).held) };
}

/// A comptime field's or an attribute's value, as something with an address:
/// a number as the narrowest of `i64`, `u64`, `i128` and `u128` it fits, a
/// float as `f64`, an enum literal as its name, a type as its descriptor.
pub fn materialize(comptime T: type, comptime ptr: *const T) Held {
    return switch (@typeInfo(T)) {
        .comptime_int => hold(IntFor(ptr.*), ptr.*),
        .comptime_float => hold(f64, ptr.*),
        .enum_literal => hold([:0]const u8, @tagName(ptr.*)),
        .type => hold(*const Type, typeOf(ptr.*)),
        .null => hold(?*const anyopaque, null),
        .@"fn" => hold(*const T, ptr),
        else => .{ .type = typeOf(T), .value = @ptrCast(ptr) },
    };
}

fn IntFor(comptime value: comptime_int) type {
    inline for (.{ i64, u64, i128, u128 }) |I| {
        if (value >= std.math.minInt(I) and value <= std.math.maxInt(I)) return I;
    }
    @compileError(std.fmt.comptimePrint("fluxion-reflect: {d} is wider than 128 bits", .{value}));
}

// -------------------------------------------------------------------------
// Defaults
// -------------------------------------------------------------------------

pub fn defaultOf(comptime T: type) ?*const anyopaque {
    if (generate.hasNoSize(T) or T == *const Type or generate.isOpaque(T)) return null;
    const maybe = comptime initialValue(T);
    const value = maybe orelse return null;
    return @ptrCast(&Static(T, value).held);
}

/// What a `T` starts as when nothing says otherwise: declared field defaults,
/// then zero, false, null, empty, an enum's first member and a union's first
/// arm that has a default. Null when a part of it has none, such as a
/// pointer that may not be null.
pub fn initialValue(comptime T: type) ?T {
    return switch (@typeInfo(T)) {
        .void => {},
        .bool => false,
        .int, .float => 0,
        .optional => null,
        .pointer => |p| if (p.size == .slice) emptySlice(T) else null,
        .array => |a| if (initialValue(a.child)) |d| @as(T, @splat(d)) else null,
        .vector => |v| if (initialValue(v.child)) |d| @as(T, @splat(d)) else null,
        .@"struct" => |s| blk: {
            var out: T = undefined;
            for (s.fields) |f| {
                if (f.is_comptime) continue;
                @field(out, f.name) = f.defaultValue() orelse (initialValue(f.type) orelse break :blk null);
            }
            break :blk out;
        },
        .@"enum" => |e| if (!e.is_exhaustive) @enumFromInt(0) else if (e.fields.len > 0) @field(T, e.fields[0].name) else null,
        .@"union" => |u| blk: {
            for (u.fields) |f| if (initialValue(f.type)) |d| break :blk @unionInit(T, f.name, d);
            break :blk null;
        },
        .error_union => |e| if (initialValue(e.payload)) |d| @as(T, d) else null,
        else => null,
    };
}

fn emptySlice(comptime S: type) ?S {
    const p = @typeInfo(S).pointer;
    if (p.alignment) |a| if (a > @alignOf(p.child)) return null;
    if (p.sentinel()) |s| {
        if (!p.is_const) return null;
        return &Static([0:s]p.child, .{}).held;
    }
    return &.{};
}

pub fn fill(comptime T: type) T {
    return comptime initialValue(T) orelse undefined;
}
