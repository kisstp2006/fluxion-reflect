// SPDX-License-Identifier: BSL-1.0

//! What a type descriptor holds. Every struct here is `extern`, so C reads the
//! same bytes through `include/fluxion_reflect.h`, and a descriptor made by one
//! binary reads the same in another built against this version.

const std = @import("std");

const generate = @import("generate.zig");
const attr = @import("attr.zig");
const schema = @import("schema.zig");
const path = @import("path.zig");

pub const Kind = enum(u8) {
    void,
    bool,
    int,
    float,
    pointer,
    slice,
    array,
    vector,
    @"struct",
    @"enum",
    @"union",
    optional,
    error_union,
    error_set,
    function,
    @"opaque",
    /// A `*const Type`: how a `type` is kept once it has to exist at run time.
    type,
    noreturn,
};

/// Text with its length and a zero after it, so C can use it as it is.
pub const Str = extern struct {
    ptr: [*:0]const u8,
    len: usize,

    pub fn of(bytes: [:0]const u8) Str {
        return .{ .ptr = bytes.ptr, .len = bytes.len };
    }

    pub fn slice(self: Str) [:0]const u8 {
        return self.ptr[0..self.len :0];
    }

    pub fn eql(self: Str, bytes: []const u8) bool {
        return std.mem.eql(u8, self.slice(), bytes);
    }

    pub fn format(self: Str, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll(self.slice());
    }
};

/// A read-only run of `T` as C spells one: a pointer and a count.
pub fn List(comptime T: type) type {
    return extern struct {
        ptr: [*]const T,
        len: usize,

        const Self = @This();

        pub const empty: Self = .{ .ptr = @ptrFromInt(@alignOf(T)), .len = 0 };

        pub fn of(items: []const T) Self {
            return if (items.len == 0) empty else .{ .ptr = items.ptr, .len = items.len };
        }

        pub fn slice(self: Self) []const T {
            return self.ptr[0..self.len];
        }
    };
}

/// A value attached to a type, field, member or method, found by its type.
pub const Attribute = extern struct {
    type: *const Type,
    value: *const anyopaque,

    pub fn as(self: Attribute, comptime T: type) ?*const T {
        if (!self.type.is(T)) return null;
        return @ptrCast(@alignCast(self.value));
    }
};

fn findAttribute(list: List(Attribute), comptime T: type) ?*const T {
    for (list.slice()) |a| if (a.as(T)) |value| return value;
    return null;
}

/// A struct's field or a union's arm.
pub const Field = extern struct {
    name: Str,
    type: *const Type,
    /// Bytes from the start of the container. For a bit field, the byte that
    /// holds its lowest bit.
    offset: usize,
    /// The declared default, or for a comptime field its value.
    default: ?*const anyopaque,
    attributes: List(Attribute),
    /// Bits from the lowest bit of a packed container.
    bit_offset: u16,
    is_comptime: bool,
    is_bit_field: bool,

    pub fn attribute(self: *const Field, comptime T: type) ?*const T {
        return findAttribute(self.attributes, T);
    }
};

/// One of an enum's named values.
pub const Member = extern struct {
    name: Str,
    /// Two's complement, sign-extended when the tag type is signed.
    value: u64,
    attributes: List(Attribute),

    pub fn attribute(self: *const Member, comptime T: type) ?*const T {
        return findAttribute(self.attributes, T);
    }
};

/// Calls the function whose pointer is kept at `function`, with `args[i]`
/// pointing at the i-th argument, and writes what it returns to `result`.
pub const Invoke = fn (function: *const anyopaque, args: [*]const *anyopaque, result: ?*anyopaque) callconv(.c) void;

/// A function a type declares and lists in `reflect_methods`, or one added to
/// a `Registry`.
pub const Method = extern struct {
    name: Str,
    /// A `.function` type.
    type: *const Type,
    /// Where the function pointer is kept, which is what `invoke` takes.
    function: *const anyopaque,
    invoke: ?*const Invoke,
    attributes: List(Attribute),

    pub fn attribute(self: *const Method, comptime T: type) ?*const T {
        return findAttribute(self.attributes, T);
    }

    /// Whether the first parameter is `owner` or a pointer to it: a method of
    /// it rather than a function beside it.
    pub fn takesSelf(self: *const Method, owner: *const Type) bool {
        const params = self.type.info.function.params.slice();
        if (params.len == 0) return false;
        const first = params[0].type;
        if (first.same(owner)) return true;
        return first.kind == .pointer and first.info.pointer.size == .one and first.info.pointer.child.same(owner);
    }

    /// The names `attr.Params` gave the parameters, without `self`, or null if
    /// it was not used.
    pub fn paramNames(self: *const Method) ?[]const []const u8 {
        const params = self.attribute(attr.Params) orelse return null;
        return params.names;
    }
};

pub const Int = extern struct {
    bits: u16,
    signed: bool,
};

pub const Float = extern struct {
    bits: u16,
};

pub const PointerSize = enum(u8) { one, many, c };

pub const Pointer = extern struct {
    child: *const Type,
    sentinel: ?*const anyopaque,
    size: PointerSize,
    is_const: bool,
    is_volatile: bool,
};

pub const RawSlice = extern struct {
    ptr: ?*anyopaque,
    len: usize,
};

pub const SliceOps = extern struct {
    get: *const fn (slice: *const anyopaque, out: *RawSlice) callconv(.c) void,
    set: *const fn (slice: *anyopaque, raw: *const RawSlice) callconv(.c) void,
};

pub const Slice = extern struct {
    child: *const Type,
    sentinel: ?*const anyopaque,
    /// Null for a slice laid out as C would write one: the pointer, then the
    /// length.
    ops: ?*const SliceOps,
    is_const: bool,
};

pub const Array = extern struct {
    child: *const Type,
    len: usize,
    sentinel: ?*const anyopaque,
};

pub const ElementOps = extern struct {
    get: *const fn (vector: *const anyopaque, index: usize, out: *anyopaque) callconv(.c) void,
    set: *const fn (vector: *anyopaque, index: usize, in: *const anyopaque) callconv(.c) void,
};

pub const Vector = extern struct {
    child: *const Type,
    len: usize,
    ops: *const ElementOps,
};

pub const Layout = enum(u8) { auto, @"extern", @"packed" };

pub const Struct = extern struct {
    fields: List(Field),
    /// The integer a packed struct's fields are packed into.
    backing: ?*const Type,
    layout: Layout,
    is_tuple: bool,
};

pub const Enum = extern struct {
    tag: *const Type,
    members: List(Member),
    is_exhaustive: bool,
};

pub const UnionOps = extern struct {
    /// Which arm is live. Null for an untagged union, which does not know.
    active: ?*const fn (u: *const anyopaque) callconv(.c) u32,
    /// Where an arm's payload is. Only for the live arm.
    payload: *const fn (u: *anyopaque, arm: u32) callconv(.c) *anyopaque,
    /// Make `arm` the live one, holding its default.
    activate: *const fn (u: *anyopaque, arm: u32) callconv(.c) void,
};

pub const Union = extern struct {
    arms: List(Field),
    /// The enum of a tagged union.
    tag: ?*const Type,
    /// Null when every arm starts at the first byte and none is known to be
    /// live, as in C.
    ops: ?*const UnionOps,
    layout: Layout,
};

pub const OptionalOps = extern struct {
    /// The payload, or null when there is none.
    payload: *const fn (o: *anyopaque) callconv(.c) ?*anyopaque,
    set_null: *const fn (o: *anyopaque) callconv(.c) void,
    /// Make one holding the payload's default, and say where it is.
    set_some: *const fn (o: *anyopaque) callconv(.c) *anyopaque,
};

pub const Optional = extern struct {
    child: *const Type,
    ops: *const OptionalOps,
};

pub const ErrorUnionOps = extern struct {
    /// The payload, or null when it holds an error.
    payload: *const fn (e: *anyopaque) callconv(.c) ?*anyopaque,
    /// The error's number, or 0 when it holds a payload.
    code: *const fn (e: *const anyopaque) callconv(.c) u32,
    set_code: *const fn (e: *anyopaque, code: u32) callconv(.c) void,
    set_payload: *const fn (e: *anyopaque) callconv(.c) *anyopaque,
};

pub const ErrorUnion = extern struct {
    error_set: *const Type,
    payload: *const Type,
    ops: *const ErrorUnionOps,
};

pub const ErrorSet = extern struct {
    names: List(Str),
    /// Numbers are this binary's own: another program numbers the same
    /// errors differently. The names are what travel.
    codes: List(u32),
    /// `anyerror`, which has no list.
    is_any: bool,
};

pub const CallingConvention = enum(u8) { auto, c, other };

pub const Param = extern struct {
    type: *const Type,
    is_noalias: bool,
};

pub const Function = extern struct {
    params: List(Param),
    return_type: *const Type,
    /// Calls a pointer to a function of this type. Null where nothing could
    /// be generated for it: a variadic function, or one described from C.
    invoke: ?*const Invoke,
    calling_convention: CallingConvention,
    is_var_args: bool,
};

/// What a type's kind says about it. Read the arm `kind` names.
pub const Info = extern union {
    int: Int,
    float: Float,
    pointer: Pointer,
    slice: Slice,
    array: Array,
    vector: Vector,
    @"struct": Struct,
    @"enum": Enum,
    @"union": Union,
    optional: Optional,
    error_union: ErrorUnion,
    error_set: ErrorSet,
    function: Function,
};

pub const Type = extern struct {
    /// `@typeName`, or the type's `reflect_name`.
    name: Str,
    /// The name hashed: the same number in every build and on every machine.
    id: u64,
    size: usize,
    /// A value to start from, when the type has one.
    default: ?*const anyopaque,
    attributes: List(Attribute),
    methods: List(Method),
    alignment: u32,
    bit_size: u32,
    kind: Kind,
    info: Info,

    /// Whether this describes `T`. See `same`.
    pub fn is(self: *const Type, comptime T: type) bool {
        return self.same(generate.typeOf(T));
    }

    /// The same descriptor, or the same type described twice: by two copies
    /// of this library in one program, or by two binaries.
    pub fn same(self: *const Type, other: *const Type) bool {
        return self == other or (self.id == other.id and self.kind == other.kind and self.size == other.size);
    }

    /// A struct's fields or a union's arms; nothing for any other kind.
    pub fn fields(self: *const Type) []const Field {
        return switch (self.kind) {
            .@"struct" => self.info.@"struct".fields.slice(),
            .@"union" => self.info.@"union".arms.slice(),
            else => &.{},
        };
    }

    pub fn fieldIndex(self: *const Type, name: []const u8) ?usize {
        for (self.fields(), 0..) |f, i| if (f.name.eql(name)) return i;
        return null;
    }

    pub fn field(self: *const Type, name: []const u8) ?*const Field {
        const i = self.fieldIndex(name) orelse return null;
        return &self.fields()[i];
    }

    pub fn members(self: *const Type) []const Member {
        return if (self.kind == .@"enum") self.info.@"enum".members.slice() else &.{};
    }

    pub fn member(self: *const Type, name: []const u8) ?*const Member {
        for (self.members()) |*m| if (m.name.eql(name)) return m;
        return null;
    }

    pub fn memberOf(self: *const Type, value: u64) ?*const Member {
        for (self.members()) |*m| if (m.value == value) return m;
        return null;
    }

    pub fn method(self: *const Type, name: []const u8) ?*const Method {
        for (self.methods.slice()) |*m| if (m.name.eql(name)) return m;
        return null;
    }

    pub fn attribute(self: *const Type, comptime T: type) ?*const T {
        return findAttribute(self.attributes, T);
    }

    /// What a pointer, slice, array, vector or optional holds, or an error
    /// union's payload.
    pub fn child(self: *const Type) ?*const Type {
        return switch (self.kind) {
            .pointer => self.info.pointer.child,
            .slice => self.info.slice.child,
            .array => self.info.array.child,
            .vector => self.info.vector.child,
            .optional => self.info.optional.child,
            .error_union => self.info.error_union.payload,
            else => null,
        };
    }

    /// Whether this is a `u8` slice, array or C string: something `Value.toString`
    /// reads as text.
    pub fn isString(self: *const Type) bool {
        const c = self.child() orelse return false;
        const byte = c.kind == .int and c.info.int.bits == 8 and c.size == 1;
        return switch (self.kind) {
            .slice, .array => byte,
            .pointer => switch (self.info.pointer.size) {
                .one => c.kind == .array and c.isString(),
                .many => byte and self.info.pointer.sentinel != null,
                .c => byte,
            },
            else => false,
        };
    }

    /// The closest field, member or method name to `name`, for "did you
    /// mean".
    pub fn suggest(self: *const Type, name: []const u8) ?[:0]const u8 {
        return path.suggest(self, name);
    }

    /// What the value means, in fluxion-data's schema grammar: the text
    /// `fingerprint` hashes.
    pub fn describe(self: *const Type, w: *std.Io.Writer) std.Io.Writer.Error!void {
        return schema.describe(self, w);
    }

    /// Equal to fluxion-data's `schema.fingerprint` for every type that
    /// library writes, so a file's schema can be checked against a type
    /// known only at run time.
    pub fn fingerprint(self: *const Type) u64 {
        return schema.fingerprint(self);
    }

    pub fn format(self: *const Type, w: *std.Io.Writer) std.Io.Writer.Error!void {
        try w.writeAll(self.name.slice());
    }
};
