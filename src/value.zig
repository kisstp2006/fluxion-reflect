// SPDX-License-Identifier: BSL-1.0

//! A value whose type is known only at run time: a descriptor and a place.
//!
//! Most methods are written in `value/` and named here with a `pub const`:
//! method-call syntax needs only a declaration whose first parameter is the
//! type, wherever the function lives.

const std = @import("std");
const Allocator = std.mem.Allocator;

const model = @import("model.zig");
const generate = @import("generate.zig");
const call_mod = @import("call.zig");
const text = @import("text.zig");
const path_mod = @import("path.zig");
const hash_mod = @import("hash.zig");
const scalars = @import("value/scalars.zig");
const inside = @import("value/inside.zig");

const Type = model.Type;
const Kind = model.Kind;

pub const Error = error{
    /// Not of the type asked for, or a kind of value this does not apply to.
    TypeMismatch,
    NoSuchField,
    NoSuchMember,
    NoSuchMethod,
    /// An error name the value's error set does not have.
    NoSuchError,
    IndexOutOfBounds,
    /// Reached through a `*const`: a constant, a default, an attribute, or a
    /// comptime field.
    ReadOnly,
    /// A null pointer, or an optional holding nothing.
    Null,
    /// A bit field, or an element of a vector of odd-sized items, which has no
    /// address of its own.
    NotAddressable,
    /// A number the type cannot hold: too big, too small, or not whole where
    /// it has to be.
    OutOfRange,
    /// Another arm of a tagged union is live, or it is a bare union, which
    /// does not say which is.
    InactiveArm,
    /// A variadic function, or one described from C without a way to call it.
    NotCallable,
    ArgumentCount,
    /// An argument that is not, and cannot be made into, the parameter's type.
    ArgumentType,
    /// Memory that does not end in the sentinel its type promises.
    MissingSentinel,
    /// The type has no default to start from.
    NoDefault,
    /// Text that does not read: a path, a number, a literal.
    Syntax,
    OutOfMemory,
    Unsupported,
};

pub const Value = extern struct {
    type: *const Type,
    ptr: *anyopaque,
    /// For a bit field, which bit of the byte at `ptr` it starts at.
    bit_offset: u8 = 0,
    /// A field of a packed struct: read and written a bit at a time, and with
    /// no address of its own.
    is_bit_field: bool = false,
    /// Reached through a `*const`: readable, not writable.
    is_const: bool = false,

    /// The value `pointer` points at. Through a `*const T` it is read-only.
    pub fn of(pointer: anytype) Value {
        const info = @typeInfo(@TypeOf(pointer)).pointer;
        if (info.size != .one) @compileError("fluxion-reflect: Value.of takes a pointer to one value, as in Value.of(&player)");
        if (info.is_volatile) @compileError("fluxion-reflect: a volatile value has to be read and written as one");
        return .{
            .type = generate.typeOf(info.child),
            .ptr = @ptrCast(@constCast(pointer)),
            .is_const = info.is_const,
        };
    }

    pub fn init(t: *const Type, ptr: *anyopaque) Value {
        return .{ .type = t, .ptr = ptr };
    }

    pub fn initConst(t: *const Type, ptr: *const anyopaque) Value {
        return .{ .type = t, .ptr = @constCast(ptr), .is_const = true };
    }

    /// A new value of type `t` on the heap, holding its default. Give it back
    /// with `destroy`.
    pub fn create(gpa: Allocator, t: *const Type) Error!Value {
        const initial = t.default orelse return error.NoDefault;
        const memory = gpa.rawAlloc(@max(t.size, 1), .fromByteUnits(t.alignment), @returnAddress()) orelse
            return error.OutOfMemory;
        @memcpy(memory[0..t.size], @as([*]const u8, @ptrCast(initial))[0..t.size]);
        return .{ .type = t, .ptr = memory };
    }

    /// Free a value made on the heap - by `create`, or by whoever made it
    /// with the type's size and alignment - after its type's `reflect_drop`
    /// lets go of what it holds.
    pub fn destroy(self: Value, gpa: Allocator) void {
        if (self.type.drop) |drop| drop(self.ptr, &gpa);
        const memory: [*]u8 = @ptrCast(self.ptr);
        gpa.rawFree(memory[0..@max(self.type.size, 1)], .fromByteUnits(self.type.alignment), @returnAddress());
    }

    pub fn kind(self: Value) Kind {
        return self.type.kind;
    }

    pub fn readOnly(self: Value) Value {
        var copy = self;
        copy.is_const = true;
        return copy;
    }

    // ---------------------------------------------------------------------
    // As a Zig type
    // ---------------------------------------------------------------------

    /// The value as a `*T`, when it is a `T`, writable and has an address.
    pub fn as(self: Value, comptime T: type) ?*T {
        if (self.is_const or self.is_bit_field or !self.type.is(T)) return null;
        return @ptrCast(@alignCast(self.ptr));
    }

    pub fn asConst(self: Value, comptime T: type) ?*const T {
        if (self.is_bit_field or !self.type.is(T)) return null;
        return @ptrCast(@alignCast(self.ptr));
    }

    /// A copy of the value, when it is a `T`.
    pub fn get(self: Value, comptime T: type) ?T {
        if (!self.type.is(T)) return null;
        if (self.is_bit_field) {
            if (comptime @bitSizeOf(T) <= 128) return fromRaw(T, self.raw());
            unreachable;
        }
        return @as(*const T, @ptrCast(@alignCast(self.ptr))).*;
    }

    pub fn set(self: Value, comptime T: type, value: T) Error!void {
        if (!self.type.is(T)) return error.TypeMismatch;
        try writable(self);
        if (self.is_bit_field) {
            if (comptime @bitSizeOf(T) <= 128) return self.storeRaw(toRaw(T, value));
            unreachable;
        }
        @as(*T, @ptrCast(@alignCast(self.ptr))).* = value;
    }

    // ---------------------------------------------------------------------
    // Numbers, truth and text, converted between kinds: value/scalars.zig
    // ---------------------------------------------------------------------

    pub const toInt = scalars.toInt;
    pub const toFloat = scalars.toFloat;
    pub const toBool = scalars.toBool;
    pub const toString = scalars.toString;
    pub const asType = scalars.asType;
    pub const setInt = scalars.setInt;
    pub const setFloat = scalars.setFloat;
    pub const setBool = scalars.setBool;
    pub const setString = scalars.setString;
    pub const setStringZ = scalars.setStringZ;
    pub const convertFrom = scalars.convertFrom;
    pub const copyFrom = scalars.copyFrom;
    pub const raw = scalars.raw;
    pub const storeRaw = scalars.storeRaw;
    pub const address = scalars.address;
    pub const wideInt = scalars.wideInt;

    // ---------------------------------------------------------------------
    // Inside - fields, arms, items, pointers, optionals, error unions:
    // value/inside.zig
    // ---------------------------------------------------------------------

    pub const field = inside.field;
    pub const fieldAt = inside.fieldAt;
    pub const active = inside.active;
    pub const activeIndex = inside.activeIndex;
    pub const payload = inside.payload;
    pub const activate = inside.activate;
    pub const activateAt = inside.activateAt;
    pub const len = inside.len;
    pub const index = inside.index;
    pub const getElement = inside.getElement;
    pub const setElement = inside.setElement;
    pub const setSliceRaw = inside.setSliceRaw;
    pub const sliceRaw = inside.sliceRaw;
    pub const deref = inside.deref;
    pub const isNull = inside.isNull;
    pub const unwrap = inside.unwrap;
    pub const unwrapOrInit = inside.unwrapOrInit;
    pub const setNull = inside.setNull;
    pub const errorName = inside.errorName;
    pub const setError = inside.setError;

    // ---------------------------------------------------------------------
    // Whole values
    // ---------------------------------------------------------------------

    /// Walk from here: fields by name, `[i]` to index, `.?` to unwrap, `.*`
    /// to dereference, and pointers followed on the way, as in Zig -
    /// `"inventory[2].name"`. `path.explain` says why one failed.
    pub fn path(self: Value, spec: []const u8) Error!Value {
        return path_mod.walk(self, spec);
    }

    /// Whether two values hold the same data: field by field, slices by what
    /// is in them, single pointers by what they point at, floats by their
    /// bits. `hash` agrees with it.
    pub fn eql(self: Value, other: Value) bool {
        return hash_mod.eql(self, other);
    }

    /// The same number `fluxion-hash`'s `hashValue` gives the Zig value.
    pub fn hash(self: Value) u64 {
        return hash_mod.hash(self);
    }

    /// Zig syntax, as ZON writes it: `.{ .hp = 100, .name = "Ada" }`.
    pub fn format(self: Value, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return text.write(self, w);
    }

    /// Read the Zig syntax `format` writes into this value. Fields left out
    /// keep what they held.
    pub fn parse(self: Value, source: []const u8, options: text.ParseOptions) Error!void {
        return text.parse(self, source, options);
    }

    /// Call a method of this value's type, with this value as its first
    /// argument, taken by pointer when the method wants a pointer.
    pub fn call(self: Value, name: []const u8, args: []const Value, result: ?Value) Error!void {
        return call_mod.callMethod(self, name, args, result);
    }

    /// Call the function a function pointer points at.
    pub fn callPointer(self: Value, args: []const Value, result: ?Value) Error!void {
        return call_mod.callPointer(self, args, result);
    }
};

pub fn writable(v: Value) Error!void {
    if (v.is_const) return error.ReadOnly;
}

fn fromRaw(comptime T: type, raw_bits: u128) T {
    return switch (@typeInfo(T)) {
        .bool => raw_bits & 1 != 0,
        .@"enum" => |e| @enumFromInt(@as(e.tag_type, @bitCast(@as(std.meta.Int(.unsigned, @bitSizeOf(e.tag_type)), @truncate(raw_bits))))),
        .pointer => @ptrFromInt(@as(usize, @truncate(raw_bits))),
        else => @bitCast(@as(std.meta.Int(.unsigned, @bitSizeOf(T)), @truncate(raw_bits))),
    };
}

fn toRaw(comptime T: type, value: T) u128 {
    return switch (@typeInfo(T)) {
        .bool => @intFromBool(value),
        .@"enum" => |e| @as(std.meta.Int(.unsigned, @bitSizeOf(e.tag_type)), @bitCast(@intFromEnum(value))),
        .pointer => @intFromPtr(value),
        else => @as(std.meta.Int(.unsigned, @bitSizeOf(T)), @bitCast(value)),
    };
}
