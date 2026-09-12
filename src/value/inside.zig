// SPDX-License-Identifier: BSL-1.0

//! Into a `Value`: a struct's fields, a union's arms, the items of arrays,
//! slices, vectors and tuples, what a pointer points at, and what an
//! optional or an error union holds. `Value` names each public function here
//! as one of its methods.

const std = @import("std");

const bits = @import("../bits.zig");
const model = @import("../model.zig");
const value = @import("../value.zig");

const Type = model.Type;
const Field = model.Field;
const Value = value.Value;
const Error = value.Error;
const writable = value.writable;

// -------------------------------------------------------------------------
// Fields and arms
// -------------------------------------------------------------------------

/// A struct's field or a tagged union's live arm, through a pointer to one
/// as Zig goes through it.
pub fn field(self: Value, name: []const u8) Error!Value {
    const target = try throughPointer(self);
    const i = target.type.fieldIndex(name) orelse return error.NoSuchField;
    return fieldAt(target, i);
}

pub fn fieldAt(self: Value, position: usize) Error!Value {
    const target = try throughPointer(self);
    const t = target.type;
    const fields = t.fields();
    if (position >= fields.len) return error.IndexOutOfBounds;
    const f = &fields[position];
    return switch (t.kind) {
        .@"struct" => structField(target, f),
        .@"union" => arm(target, position),
        else => error.TypeMismatch,
    };
}

fn structField(self: Value, f: *const Field) Error!Value {
    if (f.is_comptime) return .initConst(f.type, f.default.?);
    if (f.is_bit_field) return bitField(self, f, f.bit_offset);
    return .{ .type = f.type, .ptr = offset(self.ptr, f.offset), .is_const = self.is_const };
}

fn bitField(self: Value, f: *const Field, bit: u16) Error!Value {
    if (f.type.bit_size > 128) return error.Unsupported;
    if (self.is_bit_field) {
        const total = @as(usize, self.bit_offset) + bit;
        return .{
            .type = f.type,
            .ptr = @ptrCast(bits.step(@ptrCast(self.ptr), total / 8)),
            .bit_offset = @intCast(total % 8),
            .is_bit_field = true,
            .is_const = self.is_const,
        };
    }
    return .{
        .type = f.type,
        .ptr = offset(self.ptr, f.offset),
        .bit_offset = @intCast(bit % 8),
        .is_bit_field = true,
        .is_const = self.is_const,
    };
}

fn arm(self: Value, position: usize) Error!Value {
    const u = self.type.info.@"union";
    const f = &u.arms.slice()[position];
    if (u.ops) |ops| {
        const live = ops.active orelse return error.InactiveArm;
        if (live(self.ptr) != position) return error.InactiveArm;
        return .{ .type = f.type, .ptr = ops.payload(self.ptr, @intCast(position)), .is_const = self.is_const };
    }
    if (f.is_bit_field) return bitField(self, f, 0);
    return .{ .type = f.type, .ptr = self.ptr, .is_const = self.is_const };
}

/// The tagged union's live arm.
pub fn active(self: Value) ?*const Field {
    const i = activeIndex(self) orelse return null;
    return &self.type.fields()[i];
}

pub fn activeIndex(self: Value) ?usize {
    if (self.type.kind != .@"union") return null;
    const ops = self.type.info.@"union".ops orelse return null;
    const live = ops.active orelse return null;
    return live(self.ptr);
}

/// The live arm's payload.
pub fn payload(self: Value) Error!Value {
    const i = activeIndex(self) orelse return error.InactiveArm;
    return fieldAt(self, i);
}

/// Make an arm the live one, holding its default, and give its payload.
pub fn activate(self: Value, name: []const u8) Error!Value {
    const i = self.type.fieldIndex(name) orelse return error.NoSuchField;
    return activateAt(self, i);
}

pub fn activateAt(self: Value, position: usize) Error!Value {
    if (self.type.kind != .@"union") return error.TypeMismatch;
    try writable(self);
    const u = self.type.info.@"union";
    const arms = u.arms.slice();
    if (position >= arms.len) return error.IndexOutOfBounds;
    if (u.ops) |ops| {
        ops.activate(self.ptr, @intCast(position));
        return .{ .type = arms[position].type, .ptr = ops.payload(self.ptr, @intCast(position)) };
    }
    const view = try arm(self, position);
    if (arms[position].type.default) |initial| try view.copyFrom(.initConst(arms[position].type, initial));
    return view;
}

// -------------------------------------------------------------------------
// Items
// -------------------------------------------------------------------------

/// How many items: an array's, a vector's, a slice's, a tuple's, or a
/// sentinel-terminated pointer's up to the sentinel.
pub fn len(self: Value) Error!usize {
    const target = try throughPointer(self);
    const t = target.type;
    return switch (t.kind) {
        .array => t.info.array.len,
        .vector => t.info.vector.len,
        .slice => sliceRaw(target).len,
        .@"struct" => if (t.info.@"struct".is_tuple) t.fields().len else error.TypeMismatch,
        .pointer => sentinelLen(target),
        else => error.TypeMismatch,
    };
}

fn sentinelLen(self: Value) Error!usize {
    const p = self.type.info.pointer;
    const end = p.sentinel orelse {
        if (p.size == .c and self.type.isString()) return (self.toString() orelse return error.Null).len;
        return error.TypeMismatch;
    };
    const where = self.address();
    if (where == 0) return error.Null;
    const size = p.child.size;
    if (size == 0) return error.Unsupported;
    const want: [*]const u8 = @ptrCast(end);
    var at: [*]const u8 = @ptrFromInt(where);
    var n: usize = 0;
    while (!std.mem.eql(u8, at[0..size], want[0..size])) : (n += 1) at += size;
    return n;
}

/// An item of an array, slice, vector or tuple, through a pointer to one.
pub fn index(self: Value, i: usize) Error!Value {
    const target = try throughPointer(self);
    const t = target.type;
    switch (t.kind) {
        .array => {
            const a = t.info.array;
            if (i >= a.len) return error.IndexOutOfBounds;
            if (target.is_bit_field) return error.NotAddressable;
            return .{ .type = a.child, .ptr = offset(target.ptr, i * a.child.size), .is_const = target.is_const };
        },
        .slice => {
            const s = t.info.slice;
            const items = sliceRaw(target);
            if (i >= items.len) return error.IndexOutOfBounds;
            return .{ .type = s.child, .ptr = offset(items.ptr.?, i * s.child.size), .is_const = s.is_const };
        },
        .vector => {
            const v = t.info.vector;
            if (i >= v.len) return error.IndexOutOfBounds;
            if (target.is_bit_field or !byteSized(v.child)) return error.NotAddressable;
            return .{ .type = v.child, .ptr = offset(target.ptr, i * v.child.size), .is_const = target.is_const };
        },
        .@"struct" => {
            if (!t.info.@"struct".is_tuple) return error.TypeMismatch;
            return fieldAt(target, i);
        },
        else => return error.TypeMismatch,
    }
}

/// Copy one item of a vector out into `out`, which must be of its item type:
/// every vector can do this, addressable or not.
pub fn getElement(self: Value, i: usize, out: Value) Error!void {
    const v = try vectorInfo(self, i);
    if (!out.type.same(v.child)) return error.TypeMismatch;
    if (out.is_bit_field) return error.NotAddressable;
    try writable(out);
    v.ops.get(self.ptr, i, out.ptr);
}

pub fn setElement(self: Value, i: usize, in: Value) Error!void {
    const v = try vectorInfo(self, i);
    if (!in.type.same(v.child)) return error.TypeMismatch;
    if (in.is_bit_field) return error.NotAddressable;
    try writable(self);
    v.ops.set(self.ptr, i, in.ptr);
}

fn vectorInfo(self: Value, i: usize) Error!model.Vector {
    if (self.type.kind != .vector or self.is_bit_field) return error.TypeMismatch;
    const v = self.type.info.vector;
    if (i >= v.len) return error.IndexOutOfBounds;
    return v;
}

/// Point a slice at `count` items starting at `items`. They have to be of its
/// item type, end in its sentinel if it has one, and outlive it.
pub fn setSliceRaw(self: Value, items: ?*anyopaque, count: usize) Error!void {
    try writable(self);
    if (self.type.kind != .slice) return error.TypeMismatch;
    const s = self.type.info.slice;
    if (items == null and count > 0) return error.Null;
    if (s.sentinel) |end| if (items) |start| {
        const size = s.child.size;
        const at: [*]const u8 = @ptrCast(start);
        if (!std.mem.eql(u8, at[count * size ..][0..size], @as([*]const u8, @ptrCast(end))[0..size])) {
            return error.MissingSentinel;
        }
    };
    const raw_slice: model.RawSlice = .{ .ptr = items, .len = count };
    if (s.ops) |ops| {
        ops.set(self.ptr, &raw_slice);
    } else {
        @as(*model.RawSlice, @ptrCast(@alignCast(self.ptr))).* = raw_slice;
    }
}

pub fn sliceRaw(self: Value) model.RawSlice {
    var out: model.RawSlice = undefined;
    if (self.type.info.slice.ops) |ops| {
        ops.get(self.ptr, &out);
    } else {
        out = @as(*const model.RawSlice, @ptrCast(@alignCast(self.ptr))).*;
    }
    return out;
}

/// Whether a vector of `T` is laid out like an array of it: items of whole
/// bytes, each where an array would put it.
fn byteSized(t: *const Type) bool {
    return t.size > 0 and t.bit_size == t.size * 8;
}

// -------------------------------------------------------------------------
// Pointers, optionals and error unions
// -------------------------------------------------------------------------

/// What a pointer points at. A function pointer is not dereferenced but
/// called: see `callPointer`.
pub fn deref(self: Value) Error!Value {
    const t = self.type;
    if (t.kind != .pointer) return error.TypeMismatch;
    const p = t.info.pointer;
    if (p.size == .many or p.child.kind == .function) return error.TypeMismatch;
    const where = self.address();
    if (where == 0) return error.Null;
    return .{ .type = p.child, .ptr = @ptrFromInt(where), .is_const = p.is_const };
}

fn throughPointer(self: Value) Error!Value {
    if (self.type.kind == .pointer and self.type.info.pointer.size == .one) return deref(self);
    return self;
}

/// Whether an optional holds nothing or a C pointer is null.
pub fn isNull(self: Value) bool {
    return switch (self.type.kind) {
        .optional => self.type.info.optional.ops.payload(self.ptr) == null,
        .pointer => self.type.info.pointer.size == .c and self.address() == 0,
        else => false,
    };
}

/// An optional's payload or an error union's; null when there is none.
pub fn unwrap(self: Value) ?Value {
    const t = self.type;
    const found = switch (t.kind) {
        .optional => t.info.optional.ops.payload(self.ptr),
        .error_union => t.info.error_union.ops.payload(self.ptr),
        else => null,
    };
    return .{ .type = t.child().?, .ptr = found orelse return null, .is_const = self.is_const };
}

/// The payload of an optional or error union, first made from its default
/// when there is none.
pub fn unwrapOrInit(self: Value) Error!Value {
    if (unwrap(self)) |held| return held;
    try writable(self);
    const t = self.type;
    const made = switch (t.kind) {
        .optional => t.info.optional.ops.set_some(self.ptr),
        .error_union => t.info.error_union.ops.set_payload(self.ptr),
        else => return error.TypeMismatch,
    };
    return .{ .type = t.child().?, .ptr = made };
}

pub fn setNull(self: Value) Error!void {
    try writable(self);
    switch (self.type.kind) {
        .optional => self.type.info.optional.ops.set_null(self.ptr),
        .pointer => {
            if (self.type.info.pointer.size != .c) return error.TypeMismatch;
            self.storeRaw(0);
        },
        else => return error.TypeMismatch,
    }
}

/// The error an error union holds, or an error set value's name. Error
/// numbers belong to one binary, so only a value made in this program has a
/// name here.
pub fn errorName(self: Value) ?[:0]const u8 {
    const code: u32 = switch (self.type.kind) {
        .error_union => self.type.info.error_union.ops.code(self.ptr),
        .error_set => @intCast(self.raw()),
        else => return null,
    };
    const Code = std.meta.Int(.unsigned, @bitSizeOf(anyerror));
    if (code == 0 or code > std.math.maxInt(Code)) return null;
    return @errorName(@errorFromInt(@as(Code, @intCast(code))));
}

/// Hold the error called `name`, with or without `error.` in front. It has
/// to be in the value's error set, and `anyerror` lists none.
pub fn setError(self: Value, name: []const u8) Error!void {
    try writable(self);
    const errors = switch (self.type.kind) {
        .error_union => self.type.info.error_union.error_set,
        .error_set => self.type,
        else => return error.TypeMismatch,
    };
    const code = codeOfError(errors, name) orelse return error.NoSuchError;
    switch (self.type.kind) {
        .error_union => self.type.info.error_union.ops.set_code(self.ptr, code),
        else => self.storeRaw(code),
    }
}

fn codeOfError(errors: *const Type, name: []const u8) ?u32 {
    const bare = if (std.mem.startsWith(u8, name, "error.")) name["error.".len..] else name;
    const e = errors.info.error_set;
    for (e.names.slice(), e.codes.slice()) |n, code| if (n.eql(bare)) return code;
    return null;
}

fn offset(ptr: *anyopaque, n: usize) *anyopaque {
    return @ptrCast(@as([*]u8, @ptrCast(ptr)) + n);
}
