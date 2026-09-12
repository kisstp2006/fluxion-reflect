// SPDX-License-Identifier: BSL-1.0

//! Up to 128 bits of a scalar, wherever it sits: in whole bytes, or inside a
//! packed struct, where it can start partway through a byte.
//!
//! A bit field is found by the byte holding its lowest bit and the bit within
//! it. The bits above run on through the following bytes on a little-endian
//! machine and through the preceding ones on a big-endian machine, which is
//! how the backing integer of a packed struct is laid out on each.

const std = @import("std");
const native_endian = @import("builtin").cpu.arch.endian();

pub const Place = struct {
    ptr: [*]u8,
    size: usize,
    bit_offset: u8 = 0,
    is_bit_field: bool = false,
    bit_size: u32,
};

pub fn load(place: Place) u128 {
    if (place.is_bit_field) return loadBits(place.ptr, place.bit_offset, place.bit_size);
    return loadBytes(place.ptr, place.size) & mask(place.bit_size);
}

/// Writes the low `bit_size` bits of `value`. Whole bytes past them are
/// filled with the sign when `signed`, and with zero otherwise, so a `u24` in
/// four bytes never carries garbage in the fourth.
pub fn store(place: Place, value: u128, signed: bool) void {
    const bits = value & mask(place.bit_size);
    if (place.is_bit_field) return storeBits(place.ptr, place.bit_offset, place.bit_size, bits);
    const negative = signed and place.bit_size > 0 and place.bit_size <= 128 and
        (bits >> @intCast(place.bit_size - 1)) & 1 != 0;
    const extended = if (negative) bits | ~mask(place.bit_size) else bits;
    storeBytes(place.ptr, place.size, extended, if (negative) 0xff else 0);
}

/// The byte `index` bytes further into a bit field, counting from its lowest.
pub fn step(ptr: [*]u8, index: usize) [*]u8 {
    return switch (native_endian) {
        .little => ptr + index,
        .big => ptr - index,
    };
}

pub fn mask(bit_size: u32) u128 {
    if (bit_size >= 128) return std.math.maxInt(u128);
    return (@as(u128, 1) << @intCast(bit_size)) - 1;
}

fn loadBytes(ptr: [*]const u8, size: usize) u128 {
    const n = @min(size, 16);
    var buffer: [16]u8 = @splat(0);
    switch (native_endian) {
        .little => @memcpy(buffer[0..n], ptr[0..n]),
        .big => @memcpy(buffer[16 - n ..], ptr[size - n .. size]),
    }
    return std.mem.readInt(u128, &buffer, native_endian);
}

fn storeBytes(ptr: [*]u8, size: usize, value: u128, fill: u8) void {
    var buffer: [16]u8 = undefined;
    std.mem.writeInt(u128, &buffer, value, native_endian);
    const n = @min(size, 16);
    switch (native_endian) {
        .little => {
            @memcpy(ptr[0..n], buffer[0..n]);
            @memset(ptr[n..size], fill);
        },
        .big => {
            @memcpy(ptr[size - n .. size], buffer[16 - n ..]);
            @memset(ptr[0 .. size - n], fill);
        },
    }
}

fn loadBits(ptr: [*]u8, first: u8, count: u32) u128 {
    var value: u128 = 0;
    for (0..@min(count, 128)) |i| {
        const at = first + i;
        const byte = step(ptr, at / 8)[0];
        if ((byte >> @intCast(at % 8)) & 1 != 0) value |= @as(u128, 1) << @intCast(i);
    }
    return value;
}

fn storeBits(ptr: [*]u8, first: u8, count: u32, value: u128) void {
    for (0..@min(count, 128)) |i| {
        const at = first + i;
        const byte = &step(ptr, at / 8)[0];
        const bit = @as(u8, 1) << @intCast(at % 8);
        if ((value >> @intCast(i)) & 1 != 0) byte.* |= bit else byte.* &= ~bit;
    }
}

/// `raw` read as a number of `bit_size` bits.
pub fn toWide(raw: u128, bit_size: u32, signed: bool) i129 {
    if (bit_size == 0) return 0;
    const value = raw & mask(bit_size);
    if (!signed) return value;
    const shift: u7 = @intCast(128 - @min(bit_size, 128));
    return @as(i128, @bitCast(value << shift)) >> shift;
}

/// The bits a number is written as.
pub fn fromWide(value: i129) u128 {
    return @truncate(@as(u129, @bitCast(value)));
}

/// Whether `value` fits a `bit_size`-bit integer.
pub fn fits(value: i129, bit_size: u32, signed: bool) bool {
    if (bit_size == 0) return value == 0;
    if (bit_size > 128) return true;
    if (signed) {
        const limit = @as(i129, 1) << @intCast(bit_size - 1);
        return value >= -limit and value < limit;
    }
    return value >= 0 and value <= @as(i129, mask(bit_size));
}

/// Through `i128` or `u128`, since no backend converts a 129-bit integer.
pub fn wideToFloat(value: i129) f128 {
    if (value < 0) return @floatFromInt(@as(i128, @intCast(value)));
    return @floatFromInt(@as(u128, @intCast(value)));
}

/// The whole number a float holds, or null when it has a fraction, is not
/// finite, or is past what 128 bits hold.
pub fn floatToWide(value: f128) ?i129 {
    if (!std.math.isFinite(value) or @trunc(value) != value) return null;
    if (value < 0) {
        if (value < -0x1p127) return null;
        return @as(i128, @intFromFloat(value));
    }
    if (value >= 0x1p128) return null;
    return @as(u128, @intFromFloat(value));
}

pub fn toFloat(raw: u128, bit_size: u16, comptime F: type) F {
    return switch (bit_size) {
        16 => @floatCast(@as(f16, @bitCast(@as(u16, @truncate(raw))))),
        32 => @floatCast(@as(f32, @bitCast(@as(u32, @truncate(raw))))),
        64 => @floatCast(@as(f64, @bitCast(@as(u64, @truncate(raw))))),
        80 => @floatCast(@as(f80, @bitCast(@as(u80, @truncate(raw))))),
        128 => @floatCast(@as(f128, @bitCast(raw))),
        else => std.math.nan(F),
    };
}

pub fn fromFloat(value: anytype, bit_size: u16) u128 {
    return switch (bit_size) {
        16 => @as(u16, @bitCast(@as(f16, @floatCast(value)))),
        32 => @as(u32, @bitCast(@as(f32, @floatCast(value)))),
        64 => @as(u64, @bitCast(@as(f64, @floatCast(value)))),
        80 => @as(u80, @bitCast(@as(f80, @floatCast(value)))),
        128 => @as(u128, @bitCast(@as(f128, @floatCast(value)))),
        else => 0,
    };
}

test "whole bytes: a u24 in four, a signed i12 in two" {
    var four: [4]u8 = @splat(0xaa);
    const u24_place: Place = .{ .ptr = &four, .size = 4, .bit_size = 24 };
    store(u24_place, 0x123456, false);
    try std.testing.expectEqual(@as(u128, 0x123456), load(u24_place));
    const as_int: *align(1) const u32 = @ptrCast(&four);
    try std.testing.expectEqual(@as(u32, 0x123456), as_int.*);

    var two: [2]u8 = undefined;
    const i12_place: Place = .{ .ptr = &two, .size = 2, .bit_size = 12 };
    store(i12_place, fromWide(-3), true);
    try std.testing.expectEqual(@as(i129, -3), toWide(load(i12_place), 12, true));
    const as_i16: *align(1) const i16 = @ptrCast(&two);
    try std.testing.expectEqual(@as(i16, -3), as_i16.*);
}

test "bit fields agree with the compiler's packed layout" {
    const Packed = packed struct(u32) { a: u3, b: bool, c: i12, d: u16 };
    var value: Packed = .{ .a = 5, .b = true, .c = -700, .d = 0xbeef };
    const base: [*]u8 = @ptrCast(&value);

    const offset_c = @bitOffsetOf(Packed, "c");
    const byte = switch (native_endian) {
        .little => offset_c / 8,
        .big => @sizeOf(Packed) - 1 - offset_c / 8,
    };
    const c_place: Place = .{ .ptr = base + byte, .size = 2, .bit_offset = offset_c % 8, .is_bit_field = true, .bit_size = 12 };
    try std.testing.expectEqual(@as(i129, -700), toWide(load(c_place), 12, true));

    store(c_place, fromWide(1234), true);
    try std.testing.expectEqual(@as(i12, 1234), value.c);
    try std.testing.expectEqual(@as(u3, 5), value.a);
    try std.testing.expect(value.b);
    try std.testing.expectEqual(@as(u16, 0xbeef), value.d);
}

test "numbers that fit and numbers that do not" {
    try std.testing.expect(fits(255, 8, false));
    try std.testing.expect(!fits(256, 8, false));
    try std.testing.expect(!fits(-1, 8, false));
    try std.testing.expect(fits(-128, 8, true));
    try std.testing.expect(!fits(128, 8, true));
    try std.testing.expect(fits(std.math.maxInt(u128), 128, false));
    try std.testing.expect(fits(std.math.minInt(i128), 128, true));
    try std.testing.expectEqual(@as(i129, std.math.minInt(i128)), toWide(fromWide(std.math.minInt(i128)), 128, true));
}
