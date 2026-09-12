// SPDX-License-Identifier: BSL-1.0

//! Types by name: the ones a program registers, the primitives, and any made
//! from those the way Zig writes them - `[]const Vec2`, `?*Player`, `[4]f32` -
//! built the first time they are asked for. Also where a type described from
//! C is built, and where functions are kept by name.
//!
//! Build it up at startup and read it from anywhere afterwards: the tables are
//! not locked, and lookups change nothing except `resolve`, which may build.

const std = @import("std");
const Allocator = std.mem.Allocator;
const fuzzy = @import("fluxion_text").fuzzy;

const model = @import("model.zig");
const generate = @import("generate.zig");
const make = @import("Registry/make.zig");
const Type = model.Type;
const Method = model.Method;
const typeOf = generate.typeOf;

const Registry = @This();

gpa: Allocator,
/// Everything built here: descriptors, their names and lists.
arena: std.heap.ArenaAllocator,
list: std.ArrayList(*const Type) = .empty,
by_name: std.StringHashMapUnmanaged(*const Type) = .empty,
by_id: std.AutoHashMapUnmanaged(u64, *const Type) = .empty,
made: std.StringHashMapUnmanaged(*const Type) = .empty,
functions: std.StringArrayHashMapUnmanaged(*const Method) = .empty,

pub const Error = error{
    /// Another type has that name, or another function.
    NameTaken,
    /// A described layout that cannot be: a field past the end, one out of
    /// its alignment, a name given twice.
    InvalidLayout,
    /// A name no type has.
    UnknownType,
    /// A type expression that does not read.
    Syntax,
    /// A type that cannot be made at run time: an optional of anything but a
    /// pointer, whose layout only the compiler knows.
    Unsupported,
    OutOfMemory,
};

pub fn init(gpa: Allocator) Registry {
    return .{ .gpa = gpa, .arena = .init(gpa) };
}

pub fn deinit(self: *Registry) void {
    self.list.deinit(self.gpa);
    self.by_name.deinit(self.gpa);
    self.by_id.deinit(self.gpa);
    self.made.deinit(self.gpa);
    self.functions.deinit(self.gpa);
    self.arena.deinit();
    self.* = undefined;
}

/// Register `T` under its name: `@typeName(T)`, or its `reflect_name`.
pub fn add(self: *Registry, comptime T: type) Error!*const Type {
    const t = typeOf(T);
    try self.addType(t);
    return t;
}

pub fn addAll(self: *Registry, comptime list: anytype) Error!void {
    inline for (list) |T| _ = try self.add(T);
}

/// Register a descriptor from somewhere else: C, another binary, `define*`.
/// It has to outlive the registry. Adding the same type again does nothing.
pub fn addType(self: *Registry, t: *const Type) Error!void {
    const name = t.name.slice();
    if (self.by_name.get(name)) |held| {
        if (held.same(t)) return;
        return error.NameTaken;
    }
    if (self.by_id.get(t.id)) |held| if (!held.same(t)) return error.NameTaken;
    try self.list.ensureUnusedCapacity(self.gpa, 1);
    try self.by_id.ensureUnusedCapacity(self.gpa, 1);
    try self.by_name.put(self.gpa, name, t);
    self.by_id.putAssumeCapacity(t.id, t);
    self.list.appendAssumeCapacity(t);
}

/// A registered type or a primitive, by name. `resolve` also builds types
/// from these.
pub fn find(self: *const Registry, name: []const u8) ?*const Type {
    return self.by_name.get(name) orelse builtin(name);
}

pub fn findId(self: *const Registry, id: u64) ?*const Type {
    return self.by_id.get(id);
}

/// Every registered type, in the order they came.
pub fn types(self: *const Registry) []const *const Type {
    return self.list.items;
}

/// The registered name nearest to `name`, for "did you mean".
pub fn suggest(self: *const Registry, name: []const u8) ?[:0]const u8 {
    const budget = @max(2, name.len / 3);
    var best: ?[:0]const u8 = null;
    var distance: usize = budget + 1;
    for (self.list.items) |t| {
        const d = (fuzzy.editDistance(name, t.name.slice(), budget) catch continue) orelse continue;
        if (d < distance) {
            distance = d;
            best = t.name.slice();
        }
    }
    return best;
}

/// A type from its Zig spelling: a registered or primitive name, or one
/// made from those with `?`, `*`, `*const`, `[*]`, `[*:0]`, `[*c]`, `[]`,
/// `[:0]` and `[N]`. Built ones are kept, and take the name and id the
/// compiler's own descriptor of that type has, so the two are the `same`.
pub fn resolve(self: *Registry, expression: []const u8) Error!*const Type {
    const trimmed = std.mem.trim(u8, expression, " \t");
    if (self.find(trimmed)) |t| return t;
    if (self.made.get(trimmed)) |t| return t;
    const t = try make.fromSpelling(self, trimmed);
    if (self.made.get(t.name.slice()) == null) {
        try self.made.put(self.gpa, t.name.slice(), t);
    }
    return t;
}

// -------------------------------------------------------------------------
// Primitives
// -------------------------------------------------------------------------

const primitives = .{
    void,         bool,             u8,          u16,               u32,          u64,           u128,
    usize,        i8,               i16,         i32,               i64,          i128,          isize,
    f16,          f32,              f64,         f80,               f128,         c_char,        c_short,
    c_ushort,     c_int,            c_uint,      c_long,            c_ulong,      c_longlong,    c_ulonglong,
    c_longdouble, anyopaque,        anyerror,    []const u8,        [:0]const u8, [*:0]const u8, [*c]const u8,
    *anyopaque,   *const anyopaque, ?*anyopaque, ?*const anyopaque, *const Type,
};

/// C's names for the primitives, so a C header's field types can be written
/// as they are there.
const c_names = .{
    .{ "char", u8 },               .{ "signed char", i8 },          .{ "unsigned char", u8 },
    .{ "short", c_short },         .{ "unsigned short", c_ushort }, .{ "int", c_int },
    .{ "unsigned", c_uint },       .{ "unsigned int", c_uint },     .{ "long", c_long },
    .{ "unsigned long", c_ulong }, .{ "long long", c_longlong },    .{ "unsigned long long", c_ulonglong },
    .{ "float", f32 },             .{ "double", f64 },              .{ "long double", c_longdouble },
    .{ "_Bool", bool },            .{ "int8_t", i8 },               .{ "uint8_t", u8 },
    .{ "int16_t", i16 },           .{ "uint16_t", u16 },            .{ "int32_t", i32 },
    .{ "uint32_t", u32 },          .{ "int64_t", i64 },             .{ "uint64_t", u64 },
    .{ "size_t", usize },          .{ "ptrdiff_t", isize },         .{ "intptr_t", isize },
    .{ "uintptr_t", usize },
};

fn builtin(name: []const u8) ?*const Type {
    inline for (primitives) |P| {
        if (std.mem.eql(u8, name, @typeName(P))) return typeOf(P);
    }
    inline for (c_names) |entry| {
        if (std.mem.eql(u8, name, entry[0])) return typeOf(entry[1]);
    }
    if (std.mem.eql(u8, name, "type")) return typeOf(*const Type);
    return null;
}

// -------------------------------------------------------------------------
// Types described from C, or anything else without a Zig type:
// Registry/make.zig
// -------------------------------------------------------------------------

pub const FieldSpec = make.FieldSpec;
pub const StructSpec = make.StructSpec;
pub const MemberSpec = make.MemberSpec;
pub const EnumSpec = make.EnumSpec;
pub const ArmSpec = make.ArmSpec;
pub const UnionSpec = make.UnionSpec;

pub const defineStruct = make.defineStruct;
pub const defineEnum = make.defineEnum;
pub const defineUnion = make.defineUnion;

// -------------------------------------------------------------------------
// Functions
// -------------------------------------------------------------------------

/// Keep `function` by name, to be found with `function` and called with
/// `reflect.call`.
pub fn addFunction(self: *Registry, name: []const u8, comptime f: anytype) Error!*const Method {
    const F = @TypeOf(f);
    const t = typeOf(F);
    return self.addMethod(.{
        .name = undefined,
        .type = t,
        .function = @ptrCast(&generate.Storage(f).pointer),
        .invoke = t.info.function.invoke,
        .attributes = .empty,
    }, name);
}

pub const FunctionSpec = struct {
    name: []const u8,
    params: []const *const Type,
    return_type: *const Type,
    /// Where the function pointer is kept: handed to `invoke` as it is.
    function: *const anyopaque,
    invoke: *const model.Invoke,
};

/// A function that has no Zig type to describe it - one written in C - with
/// the `invoke` that calls it.
pub fn defineFunction(self: *Registry, spec: FunctionSpec) Error!*const Method {
    const a = self.arena.allocator();
    const params = try a.alloc(model.Param, spec.params.len);
    for (spec.params, params) |p, *out| out.* = .{ .type = p, .is_noalias = false };

    var name: std.Io.Writer.Allocating = .init(self.gpa);
    defer name.deinit();
    const w = &name.writer;
    w.writeAll("fn (") catch return error.OutOfMemory;
    for (spec.params, 0..) |p, i| w.print("{s}{s}", .{ if (i > 0) ", " else "", p.name.slice() }) catch return error.OutOfMemory;
    w.print(") callconv(.c) {s}", .{spec.return_type.name.slice()}) catch return error.OutOfMemory;

    const t = try make.newType(self, name.written());
    t.kind = .function;
    t.info = .{ .function = .{
        .params = .of(params),
        .return_type = spec.return_type,
        .invoke = null,
        .calling_convention = .c,
        .is_var_args = false,
    } };
    return self.addMethod(.{
        .name = undefined,
        .type = t,
        .function = spec.function,
        .invoke = spec.invoke,
        .attributes = .empty,
    }, spec.name);
}

fn addMethod(self: *Registry, method: Method, name: []const u8) Error!*const Method {
    if (self.functions.contains(name)) return error.NameTaken;
    const a = self.arena.allocator();
    const kept = try a.create(Method);
    kept.* = method;
    const owned = try a.dupeZ(u8, name);
    kept.name = .of(owned);
    try self.functions.put(self.gpa, owned, kept);
    return kept;
}

pub fn function(self: *const Registry, name: []const u8) ?*const Method {
    return self.functions.get(name);
}
