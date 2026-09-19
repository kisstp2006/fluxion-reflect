// SPDX-License-Identifier: BSL-1.0

//! Descriptors for Zig types, made at compile time.
//!
//! `typeOf(T)` is the address of a `const` in a struct made for `T` alone, so
//! a descriptor is data in the binary: nothing is registered or allocated, and
//! asking twice gives the same pointer. A type that points at itself, like a
//! list node's `?*Node`, closes into a cycle rather than an endless compile,
//! because the address of a `const` with a declared type is known before its
//! value is.

const std = @import("std");
const native_endian = @import("builtin").cpu.arch.endian();
const hashing = @import("fluxion_hash");

const model = @import("model.zig");
pub const declarations = @import("generate/declarations.zig");
const defaults = @import("generate/defaults.zig");
const thunks = @import("generate/thunks.zig");

const Type = model.Type;
const Kind = model.Kind;
const Str = model.Str;
const Field = model.Field;
const Member = model.Member;
const Param = model.Param;
const List = model.List;

pub const initialValue = defaults.initialValue;
pub const Storage = thunks.Storage;

pub fn typeOf(comptime T: type) *const Type {
    return &Descriptor(T).descriptor;
}

fn Descriptor(comptime T: type) type {
    return struct {
        const descriptor: Type = make(T);
    };
}

fn make(comptime T: type) Type {
    @setEvalBranchQuota(1_000_000);
    declarations.check(T);
    const name = nameOf(T);
    return .{
        .name = .of(name),
        .id = hashing.hashBytes(name),
        .size = if (hasNoSize(T)) 0 else @sizeOf(T),
        .default = defaults.defaultOf(T),
        .attributes = declarations.typeAttributes(T),
        .methods = declarations.methodsOf(T),
        .alignment = if (hasNoSize(T)) 1 else @alignOf(T),
        .bit_size = if (hasNoSize(T)) 0 else @bitSizeOf(T),
        .kind = kindOf(T),
        .info = infoOf(T),
    };
}

pub fn refuse(comptime T: type, comptime why: []const u8) noreturn {
    @compileError("fluxion-reflect: " ++ @typeName(T) ++ ": " ++ why);
}

pub fn hasDecl(comptime T: type, comptime name: []const u8) bool {
    return switch (@typeInfo(T)) {
        .@"struct", .@"union", .@"enum", .@"opaque" => @hasDecl(T, name),
        else => false,
    };
}

pub fn isOpaque(comptime T: type) bool {
    return hasDecl(T, "reflect_opaque") and T.reflect_opaque;
}

pub fn hasNoSize(comptime T: type) bool {
    return switch (@typeInfo(T)) {
        .@"fn", .@"opaque", .noreturn => true,
        else => false,
    };
}

/// `@typeName`, except that a type made from others is named from their
/// names, so that a `reflect_name` carries through: `[]const Player`, not
/// `[]const game.entities.Player`. That is also the name a `Registry` gives
/// the same type when it builds it, which is what makes the two the `same`.
fn nameOf(comptime T: type) [:0]const u8 {
    if (hasDecl(T, "reflect_name")) return T.reflect_name;
    const print = std.fmt.comptimePrint;
    return comptime switch (@typeInfo(T)) {
        .optional => |o| print("?{s}", .{nameOf(o.child)}),
        .array => |a| if (a.sentinel_ptr == null)
            print("[{d}]{s}", .{ a.len, nameOf(a.child) })
        else if (isZero(a.child, a.sentinel_ptr.?))
            print("[{d}:0]{s}", .{ a.len, nameOf(a.child) })
        else
            @typeName(T),
        .vector => |v| print("@Vector({d}, {s})", .{ v.len, nameOf(v.child) }),
        .error_union => |e| print("{s}!{s}", .{ nameOf(e.error_set), nameOf(e.payload) }),
        .pointer => |p| blk: {
            if (p.is_volatile or p.is_allowzero or p.alignment != null or p.address_space != .generic) break :blk @typeName(T);
            const zero = if (p.sentinel_ptr) |s| isZero(p.child, s) else false;
            if (p.sentinel_ptr != null and !zero) break :blk @typeName(T);
            const prefix = switch (p.size) {
                .one => "*",
                .many => if (zero) "[*:0]" else "[*]",
                .slice => if (zero) "[:0]" else "[]",
                .c => "[*c]",
            };
            break :blk print("{s}{s}{s}", .{ prefix, if (p.is_const) "const " else "", nameOf(p.child) });
        },
        else => @typeName(T),
    };
}

fn isZero(comptime T: type, comptime sentinel: *const anyopaque) bool {
    return switch (@typeInfo(T)) {
        .int => @as(*const T, @ptrCast(@alignCast(sentinel))).* == 0,
        else => false,
    };
}

fn kindOf(comptime T: type) Kind {
    if (T == *const Type) return .type;
    if (isOpaque(T)) return .@"opaque";
    return switch (@typeInfo(T)) {
        .void => .void,
        .bool => .bool,
        .noreturn => .noreturn,
        .int => .int,
        .float => .float,
        .pointer => |p| if (p.size == .slice) .slice else .pointer,
        .array => .array,
        .vector => .vector,
        .@"struct" => .@"struct",
        .@"enum" => .@"enum",
        .@"union" => .@"union",
        .optional => .optional,
        .error_union => .error_union,
        .error_set => .error_set,
        .@"fn" => .function,
        .@"opaque" => .@"opaque",
        else => refuse(T, "it exists only at compile time, so there is nothing of it to describe at run time"),
    };
}

fn layoutOf(comptime layout: std.builtin.Type.ContainerLayout) model.Layout {
    return switch (layout) {
        .auto => .auto,
        .@"extern" => .@"extern",
        .@"packed" => .@"packed",
    };
}

/// Built a field at a time into zeroed memory: a `bool` in a comptime union,
/// copied in whole, is lowered with seven undefined bits beside it, which C
/// reads as a byte that is neither true nor false.
fn infoArm(comptime name: []const u8, value: @FieldType(model.Info, name)) model.Info {
    var info = std.mem.zeroes(model.Info);
    inline for (@typeInfo(@TypeOf(value)).@"struct".fields) |f| {
        @field(@field(info, name), f.name) = @field(value, f.name);
    }
    return info;
}

fn infoOf(comptime T: type) model.Info {
    if (T == *const Type or isOpaque(T)) return std.mem.zeroes(model.Info);
    return switch (@typeInfo(T)) {
        .int => |i| infoArm("int", .{ .bits = i.bits, .signed = i.signedness == .signed }),
        .float => |f| infoArm("float", .{ .bits = f.bits }),
        .pointer => |p| if (p.size == .slice) infoArm("slice", .{
            .child = typeOf(p.child),
            .sentinel = p.sentinel_ptr,
            .ops = &thunks.SliceOps(T).ops,
            .is_const = p.is_const,
        }) else infoArm("pointer", .{
            .child = typeOf(p.child),
            .sentinel = p.sentinel_ptr,
            .size = switch (p.size) {
                .one => .one,
                .many => .many,
                .c => .c,
                .slice => unreachable,
            },
            .is_const = p.is_const,
            .is_volatile = p.is_volatile,
        }),
        .array => |a| infoArm("array", .{ .child = typeOf(a.child), .len = a.len, .sentinel = a.sentinel_ptr }),
        .vector => |v| infoArm("vector", .{ .child = typeOf(v.child), .len = v.len, .ops = &thunks.VectorOps(T).ops }),
        .@"struct" => |s| infoArm("struct", .{
            .fields = structFields(T),
            .backing = if (s.backing_integer) |B| typeOf(B) else null,
            .layout = layoutOf(s.layout),
            .is_tuple = s.is_tuple,
        }),
        .@"enum" => |e| infoArm("enum", .{
            .tag = typeOf(e.tag_type),
            .members = enumMembers(T),
            .is_exhaustive = e.is_exhaustive,
        }),
        .@"union" => |u| infoArm("union", .{
            .arms = unionArms(T),
            .tag = if (u.tag_type) |Tag| typeOf(Tag) else null,
            .ops = if (u.layout == .auto and u.fields.len > 0) &thunks.UnionOps(T).ops else null,
            .layout = layoutOf(u.layout),
        }),
        .optional => |o| infoArm("optional", .{ .child = typeOf(o.child), .ops = &thunks.OptionalOps(T).ops }),
        .error_union => |e| infoArm("error_union", .{
            .error_set = typeOf(e.error_set),
            .payload = typeOf(e.payload),
            .ops = &thunks.ErrorUnionOps(T).ops,
        }),
        .error_set => |set| infoArm("error_set", .{
            .names = errorNames(T),
            .codes = errorCodes(T),
            .is_any = set == null,
        }),
        .@"fn" => |f| blk: {
            if (f.is_generic) refuse(T, "a generic function has no one type to be called through");
            break :blk infoArm("function", .{
                .params = params(T),
                .return_type = typeOf(f.return_type.?),
                .invoke = if (f.is_var_args or f.calling_convention == .@"inline") null else &thunks.Invoker(T).invoke,
                .calling_convention = callingConvention(f.calling_convention),
                .is_var_args = f.is_var_args,
            });
        },
        else => std.mem.zeroes(model.Info),
    };
}

fn structFields(comptime T: type) List(Field) {
    return comptime blk: {
        const s = @typeInfo(T).@"struct";
        var out: [s.fields.len]Field = undefined;
        for (s.fields, 0..) |f, i| out[i] = fieldOf(T, f, s.layout == .@"packed");
        const final = out;
        break :blk .of(&final);
    };
}

fn fieldOf(comptime T: type, comptime f: std.builtin.Type.StructField, comptime in_packed: bool) Field {
    var out: Field = .{
        .name = .of(f.name),
        .type = undefined,
        .offset = 0,
        .default = f.default_value_ptr,
        .attributes = declarations.fieldAttributes(T, f.name),
        .bit_offset = 0,
        .is_comptime = f.is_comptime,
        .is_bit_field = false,
    };
    if (f.is_comptime) {
        const held = defaults.materialize(f.type, @ptrCast(@alignCast(f.default_value_ptr.?)));
        out.type = held.type;
        out.default = held.value;
    } else if (in_packed) {
        out.type = typeOf(f.type);
        out.bit_offset = @bitOffsetOf(T, f.name);
        out.offset = byteOfBit(T, @bitOffsetOf(T, f.name));
        out.is_bit_field = true;
    } else {
        out.type = typeOf(f.type);
        out.offset = @offsetOf(T, f.name);
    }
    return out;
}

/// The byte of a packed `T` holding bit `bit` of its backing integer.
fn byteOfBit(comptime T: type, comptime bit: usize) usize {
    return switch (native_endian) {
        .little => bit / 8,
        .big => @sizeOf(T) - 1 - bit / 8,
    };
}

fn enumMembers(comptime E: type) List(Member) {
    return comptime blk: {
        const e = @typeInfo(E).@"enum";
        if (@typeInfo(e.tag_type).int.bits > 64) refuse(E, "its tag is wider than the 64 bits a member's value is kept in");
        var out: [e.fields.len]Member = undefined;
        for (e.fields, 0..) |f, i| out[i] = .{
            .name = .of(f.name),
            .value = if (f.value < 0) @bitCast(@as(i64, f.value)) else f.value,
            .attributes = declarations.fieldAttributes(E, f.name),
        };
        const final = out;
        break :blk .of(&final);
    };
}

fn unionArms(comptime U: type) List(Field) {
    return comptime blk: {
        const u = @typeInfo(U).@"union";
        const in_packed = u.layout == .@"packed";
        var out: [u.fields.len]Field = undefined;
        for (u.fields, 0..) |f, i| out[i] = .{
            .name = .of(f.name),
            .type = typeOf(f.type),
            .offset = if (in_packed) byteOfBit(U, 0) else 0,
            .default = null,
            .attributes = declarations.fieldAttributes(U, f.name),
            .bit_offset = 0,
            .is_comptime = false,
            .is_bit_field = in_packed,
        };
        const final = out;
        break :blk .of(&final);
    };
}

fn errorNames(comptime E: type) List(Str) {
    const set = @typeInfo(E).error_set orelse return .empty;
    return comptime blk: {
        var out: [set.len]Str = undefined;
        for (set, 0..) |e, i| out[i] = .of(e.name);
        const final = out;
        break :blk .of(&final);
    };
}

fn errorCodes(comptime E: type) List(u32) {
    const set = @typeInfo(E).error_set orelse return .empty;
    return comptime blk: {
        var out: [set.len]u32 = undefined;
        for (set, 0..) |e, i| out[i] = @intFromError(@field(E, e.name));
        const final = out;
        break :blk .of(&final);
    };
}

fn params(comptime F: type) List(Param) {
    return comptime blk: {
        const f = @typeInfo(F).@"fn";
        var out: [f.params.len]Param = undefined;
        for (f.params, 0..) |p, i| out[i] = .{ .type = typeOf(p.type.?), .is_noalias = p.is_noalias };
        const final = out;
        break :blk .of(&final);
    };
}

fn callingConvention(comptime cc: std.builtin.CallingConvention) model.CallingConvention {
    if (cc == .auto) return .auto;
    if (std.meta.eql(cc, std.builtin.CallingConvention.c)) return .c;
    return .other;
}
