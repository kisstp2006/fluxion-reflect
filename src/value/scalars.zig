// SPDX-License-Identifier: BSL-1.0

//! Numbers, truth and text in a `Value`, converted between kinds, and the
//! raw bits under them. `Value` names each public function here as one of
//! its methods.

const std = @import("std");

const bits = @import("../bits.zig");
const model = @import("../model.zig");
const value = @import("../value.zig");

const Type = model.Type;
const Value = value.Value;
const Error = value.Error;
const writable = value.writable;

// -------------------------------------------------------------------------
// Read, converted
// -------------------------------------------------------------------------

/// A whole number: an integer, an enum's tag, a bool as 0 or 1, or a float
/// with nothing after the point. Null when it is none of those or does not
/// fit `I`.
pub fn toInt(self: Value, comptime I: type) ?I {
    return std.math.cast(I, self.wideInt() orelse return null);
}

pub fn toFloat(self: Value, comptime F: type) ?F {
    return switch (self.type.kind) {
        .float => bits.toFloat(self.raw(), self.type.info.float.bits, F),
        .int => @floatCast(bits.wideToFloat(self.wideInt() orelse return null)),
        else => null,
    };
}

pub fn toBool(self: Value) ?bool {
    if (self.type.kind != .bool) return null;
    return self.raw() & 1 != 0;
}

/// Text: the bytes of a `u8` slice, array or C string, an enum member's
/// name, an error's name, a type's name.
pub fn toString(self: Value) ?[]const u8 {
    const t = self.type;
    switch (t.kind) {
        .slice => {
            if (!t.isString()) return null;
            const raw_slice = self.sliceRaw();
            const start: [*]const u8 = @ptrCast(raw_slice.ptr orelse return "");
            return start[0..raw_slice.len];
        },
        .array => {
            if (!t.isString() or self.is_bit_field) return null;
            const start: [*]const u8 = @ptrCast(self.ptr);
            return start[0..t.info.array.len];
        },
        .pointer => {
            if (!t.isString()) return null;
            const where = self.address();
            if (where == 0) return null;
            const p = t.info.pointer;
            if (p.size == .one) return @as([*]const u8, @ptrFromInt(where))[0..p.child.info.array.len];
            const end: u8 = if (p.sentinel) |s| @as(*const u8, @ptrCast(s)).* else 0;
            const start: [*]const u8 = @ptrFromInt(where);
            var n: usize = 0;
            while (start[n] != end) n += 1;
            return start[0..n];
        },
        .@"enum" => {
            const m = t.memberOf(@truncate(bits.fromWide(self.wideInt().?))) orelse return null;
            return m.name.slice();
        },
        .error_set, .error_union => return self.errorName(),
        .type => return if (self.asType()) |described| described.name.slice() else null,
        else => return null,
    }
}

/// The type a `.type` value names.
pub fn asType(self: Value) ?*const Type {
    if (self.type.kind != .type) return null;
    const where = self.address();
    return if (where == 0) null else @ptrFromInt(where);
}

// -------------------------------------------------------------------------
// Written, converted
// -------------------------------------------------------------------------

/// Write a whole number into an integer, a float, an enum (whose members it
/// must name unless the enum is non-exhaustive) or a bool (0 or 1).
pub fn setInt(self: Value, number: anytype) Error!void {
    return setWide(self, number);
}

fn setWide(self: Value, number: i129) Error!void {
    try writable(self);
    const t = self.type;
    switch (t.kind) {
        .int => {
            const info = t.info.int;
            if (info.bits > 128) return error.Unsupported;
            if (!bits.fits(number, info.bits, info.signed)) return error.OutOfRange;
            self.storeRaw(bits.fromWide(number));
        },
        .float => self.storeRaw(bits.fromFloat(bits.wideToFloat(number), t.info.float.bits)),
        .@"enum" => {
            const e = t.info.@"enum";
            const tag = e.tag.info.int;
            if (!bits.fits(number, tag.bits, tag.signed)) return error.OutOfRange;
            if (e.is_exhaustive and t.memberOf(@truncate(bits.fromWide(number))) == null) return error.NoSuchMember;
            self.storeRaw(bits.fromWide(number));
        },
        .bool => {
            if (number != 0 and number != 1) return error.OutOfRange;
            self.storeRaw(@intCast(number));
        },
        else => return error.TypeMismatch,
    }
}

/// Write a number into a float, or into an integer when it is whole.
pub fn setFloat(self: Value, number: anytype) Error!void {
    return setWideFloat(self, number);
}

fn setWideFloat(self: Value, number: f128) Error!void {
    try writable(self);
    switch (self.type.kind) {
        .float => self.storeRaw(bits.fromFloat(number, self.type.info.float.bits)),
        .int => {
            const whole = bits.floatToWide(number) orelse return error.OutOfRange;
            return setWide(self, whole);
        },
        else => return error.TypeMismatch,
    }
}

pub fn setBool(self: Value, truth: bool) Error!void {
    try writable(self);
    if (self.type.kind != .bool) return error.TypeMismatch;
    self.storeRaw(@intFromBool(truth));
}

/// Text into a `u8` array (copied, the rest zeroed), a `[]const u8` (which
/// then points at `bytes`, so they have to outlive it), an enum (a member's
/// name) or an error set (an error's name).
pub fn setString(self: Value, bytes: []const u8) Error!void {
    try writable(self);
    const t = self.type;
    switch (t.kind) {
        .array => {
            if (!t.isString() or self.is_bit_field) return error.TypeMismatch;
            const n = t.info.array.len;
            if (bytes.len > n) return error.OutOfRange;
            const out: [*]u8 = @ptrCast(self.ptr);
            @memcpy(out[0..bytes.len], bytes);
            @memset(out[bytes.len..n], 0);
        },
        .slice => {
            const s = t.info.slice;
            if (!t.isString() or !s.is_const) return error.TypeMismatch;
            if (s.sentinel != null) return error.MissingSentinel;
            try self.setSliceRaw(@ptrCast(@constCast(bytes.ptr)), bytes.len);
        },
        .@"enum" => {
            const name = if (bytes.len > 0 and bytes[0] == '.') bytes[1..] else bytes;
            const m = t.member(name) orelse return error.NoSuchMember;
            self.storeRaw(m.value);
        },
        .error_set, .error_union => return self.setError(bytes),
        else => return error.TypeMismatch,
    }
}

/// Point a `[:0]const u8`, `[*:0]const u8` or `[*c]const u8` at text that
/// ends in a zero. The text has to outlive it.
pub fn setStringZ(self: Value, bytes: [:0]const u8) Error!void {
    try writable(self);
    const t = self.type;
    switch (t.kind) {
        .slice => {
            const s = t.info.slice;
            if (!t.isString() or !s.is_const) return error.TypeMismatch;
            try self.setSliceRaw(@ptrCast(@constCast(bytes.ptr)), bytes.len);
        },
        .pointer => {
            const p = t.info.pointer;
            if (!t.isString() or p.size == .one or !p.is_const) return error.TypeMismatch;
            if (p.sentinel) |s| if (@as(*const u8, @ptrCast(s)).* != 0) return error.MissingSentinel;
            self.storeRaw(@intFromPtr(bytes.ptr));
        },
        else => return setString(self, bytes),
    }
}

/// Copy another value in, converting between numbers, bools and enums as
/// `setInt` and `setFloat` do, and reading text into what `setString` takes.
pub fn convertFrom(self: Value, source: Value) Error!void {
    if (self.type.same(source.type)) return copyFrom(self, source);
    switch (source.type.kind) {
        .int, .bool => return setWide(self, source.wideInt() orelse return error.OutOfRange),
        .float => return setWideFloat(self, source.toFloat(f128).?),
        .@"enum" => {
            if (self.type.kind == .@"enum") return setString(self, source.toString() orelse return error.NoSuchMember);
            return setWide(self, source.wideInt().?);
        },
        else => {
            if (source.toString()) |bytes| return setString(self, bytes);
            return error.TypeMismatch;
        },
    }
}

/// Copy another value of the same type over this one. A slice or pointer in
/// it is copied as it is, so both then share what it points at.
pub fn copyFrom(self: Value, source: Value) Error!void {
    if (!self.type.same(source.type)) return error.TypeMismatch;
    try writable(self);
    if (self.is_bit_field or source.is_bit_field) return self.storeRaw(source.raw());
    const n = self.type.size;
    if (n == 0) return;
    const to: [*]u8 = @ptrCast(self.ptr);
    const from: [*]const u8 = @ptrCast(source.ptr);
    @memmove(to[0..n], from[0..n]);
}

// -------------------------------------------------------------------------
// The bits
// -------------------------------------------------------------------------

/// Up to 128 bits of a scalar: an integer, a float's bits, a bool, an enum's
/// tag, an error's number, a pointer's address.
pub fn raw(self: Value) u128 {
    return bits.load(place(self));
}

pub fn storeRaw(self: Value, word: u128) void {
    bits.store(place(self), word, isSigned(self));
}

pub fn address(self: Value) usize {
    if (self.is_bit_field) return @truncate(raw(self));
    return @as(*const usize, @ptrCast(@alignCast(self.ptr))).*;
}

pub fn wideInt(self: Value) ?i129 {
    const t = self.type;
    switch (t.kind) {
        .int => {
            const info = t.info.int;
            if (info.bits > 128) return null;
            return bits.toWide(raw(self), info.bits, info.signed);
        },
        .@"enum" => {
            const tag = t.info.@"enum".tag.info.int;
            return bits.toWide(raw(self), tag.bits, tag.signed);
        },
        .bool => return @intCast(raw(self) & 1),
        .float => return bits.floatToWide(toFloat(self, f128).?),
        else => return null,
    }
}

fn place(self: Value) bits.Place {
    return .{
        .ptr = @ptrCast(self.ptr),
        .size = self.type.size,
        .bit_offset = self.bit_offset,
        .is_bit_field = self.is_bit_field,
        .bit_size = self.type.bit_size,
    };
}

fn isSigned(self: Value) bool {
    return switch (self.type.kind) {
        .int => self.type.info.int.signed,
        .@"enum" => self.type.info.@"enum".tag.info.int.signed,
        else => false,
    };
}
