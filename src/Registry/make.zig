// SPDX-License-Identifier: BSL-1.0

//! Descriptors made at run time, in a registry's arena: from a Zig spelling
//! for `Registry.resolve`, and from a layout C describes for
//! `Registry.defineStruct`, `defineEnum` and `defineUnion`.

const std = @import("std");
const hashing = @import("fluxion_hash");

const model = @import("../model.zig");
const bits = @import("../bits.zig");
const generate = @import("../generate.zig");
const Value = @import("../value.zig").Value;
const Registry = @import("../Registry.zig");

const Type = model.Type;
const Error = Registry.Error;
const typeOf = generate.typeOf;

// -------------------------------------------------------------------------
// Types written the way Zig writes them
// -------------------------------------------------------------------------

const Prefix = struct {
    kind: enum { optional, pointer, slice, array },
    size: model.PointerSize = .one,
    len: usize = 0,
    zero_sentinel: bool = false,
    is_const: bool = false,
    rest: []const u8,
};

pub fn fromSpelling(self: *Registry, expression: []const u8) Error!*const Type {
    const prefix = try readPrefix(expression);
    const child = try self.resolve(prefix.rest);
    return switch (prefix.kind) {
        .optional => optionalOf(self, child),
        .pointer => pointerTo(self, child, prefix.size, prefix.is_const, prefix.zero_sentinel),
        .slice => sliceOf(self, child, prefix.is_const, prefix.zero_sentinel),
        .array => arrayOf(self, child, prefix.len, prefix.zero_sentinel),
    };
}

fn readPrefix(expression: []const u8) Error!Prefix {
    if (expression.len == 0) return error.Syntax;
    if (expression[0] == '?') return .{ .kind = .optional, .rest = expression[1..] };
    if (expression[0] == '*') return constness(.{ .kind = .pointer, .rest = expression[1..] });
    if (expression[0] != '[') return error.UnknownType;
    const close = std.mem.indexOfScalar(u8, expression, ']') orelse return error.Syntax;
    const inside = expression[1..close];
    var prefix: Prefix = .{ .kind = .slice, .rest = expression[close + 1 ..] };
    if (std.mem.eql(u8, inside, "")) {
        prefix.kind = .slice;
    } else if (std.mem.eql(u8, inside, ":0")) {
        prefix.kind = .slice;
        prefix.zero_sentinel = true;
    } else if (std.mem.eql(u8, inside, "*")) {
        prefix = .{ .kind = .pointer, .size = .many, .rest = prefix.rest };
    } else if (std.mem.eql(u8, inside, "*:0")) {
        prefix = .{ .kind = .pointer, .size = .many, .zero_sentinel = true, .rest = prefix.rest };
    } else if (std.mem.eql(u8, inside, "*c")) {
        prefix = .{ .kind = .pointer, .size = .c, .rest = prefix.rest };
    } else {
        const colon = std.mem.indexOfScalar(u8, inside, ':');
        const digits = inside[0 .. colon orelse inside.len];
        if (colon) |at| if (!std.mem.eql(u8, inside[at..], ":0")) return error.Syntax;
        prefix.kind = .array;
        prefix.len = std.fmt.parseUnsigned(usize, digits, 10) catch return error.Syntax;
        prefix.zero_sentinel = colon != null;
        return prefix;
    }
    return constness(prefix);
}

fn constness(prefix: Prefix) Prefix {
    var out = prefix;
    const rest = std.mem.trimStart(u8, out.rest, " ");
    if (std.mem.startsWith(u8, rest, "const ")) {
        out.is_const = true;
        out.rest = rest["const ".len..];
    } else out.rest = rest;
    return out;
}

fn known(self: *const Registry, name: []const u8) ?*const Type {
    return self.find(name) orelse self.made.get(name);
}

fn sentinelFor(self: *Registry, child: *const Type) Error!*const anyopaque {
    if (child.kind != .int and child.kind != .bool and child.kind != .pointer) return error.Unsupported;
    return zeroes(self, child.size, child.alignment);
}

fn pointerTo(self: *Registry, child: *const Type, size: model.PointerSize, is_const: bool, zero_sentinel: bool) Error!*const Type {
    var name: std.Io.Writer.Allocating = .init(self.gpa);
    defer name.deinit();
    const w = &name.writer;
    w.writeAll(switch (size) {
        .one => "*",
        .many => if (zero_sentinel) "[*:0]" else "[*]",
        .c => "[*c]",
    }) catch return error.OutOfMemory;
    if (is_const) w.writeAll("const ") catch return error.OutOfMemory;
    w.writeAll(child.name.slice()) catch return error.OutOfMemory;
    if (known(self, name.written())) |t| return t;

    const t = try newType(self, name.written());
    t.kind = .pointer;
    t.size = @sizeOf(usize);
    t.alignment = @alignOf(usize);
    t.bit_size = @bitSizeOf(usize);
    if (size == .c) t.default = try zeroes(self, t.size, t.alignment);
    t.info = .{ .pointer = .{
        .child = child,
        .sentinel = if (zero_sentinel) try sentinelFor(self, child) else null,
        .size = size,
        .is_const = is_const,
        .is_volatile = false,
    } };
    return t;
}

fn sliceOf(self: *Registry, child: *const Type, is_const: bool, zero_sentinel: bool) Error!*const Type {
    const name = try std.fmt.allocPrint(self.gpa, "[{s}]{s}{s}", .{
        if (zero_sentinel) ":0" else "",
        if (is_const) "const " else "",
        child.name.slice(),
    });
    defer self.gpa.free(name);
    if (known(self, name)) |t| return t;

    const bytes = typeOf([]u8);
    const t = try newType(self, name);
    t.kind = .slice;
    t.size = bytes.size;
    t.alignment = bytes.alignment;
    t.bit_size = bytes.bit_size;
    t.info = .{ .slice = .{
        .child = child,
        .sentinel = if (zero_sentinel) try sentinelFor(self, child) else null,
        .ops = bytes.info.slice.ops,
        .is_const = is_const,
    } };
    if (!zero_sentinel) t.default = bytes.default;
    return t;
}

fn arrayOf(self: *Registry, child: *const Type, len: usize, zero_sentinel: bool) Error!*const Type {
    const name = try std.fmt.allocPrint(self.gpa, "[{d}{s}]{s}", .{ len, if (zero_sentinel) ":0" else "", child.name.slice() });
    defer self.gpa.free(name);
    if (known(self, name)) |t| return t;

    const count = len + @intFromBool(zero_sentinel);
    const t = try newType(self, name);
    t.kind = .array;
    t.size = count * child.size;
    t.alignment = child.alignment;
    t.bit_size = @intCast(t.size * 8);
    t.info = .{ .array = .{
        .child = child,
        .len = len,
        .sentinel = if (zero_sentinel) try sentinelFor(self, child) else null,
    } };
    if (child.default) |initial| {
        const memory: [*]u8 = @ptrCast(@constCast(try zeroes(self, t.size, t.alignment)));
        for (0..len) |i| @memcpy(memory[i * child.size ..][0..child.size], @as([*]const u8, @ptrCast(initial))[0..child.size]);
        t.default = memory;
    }
    return t;
}

fn optionalOf(self: *Registry, child: *const Type) Error!*const Type {
    if (child.kind != .pointer or child.info.pointer.size == .c) return error.Unsupported;
    const name = try std.fmt.allocPrint(self.gpa, "?{s}", .{child.name.slice()});
    defer self.gpa.free(name);
    if (known(self, name)) |t| return t;

    const pointer = typeOf(?*anyopaque);
    const t = try newType(self, name);
    t.kind = .optional;
    t.size = pointer.size;
    t.alignment = pointer.alignment;
    t.bit_size = pointer.bit_size;
    t.default = pointer.default;
    t.info = .{ .optional = .{ .child = child, .ops = pointer.info.optional.ops } };
    return t;
}

// -------------------------------------------------------------------------
// Types described from C, or anything else without a Zig type
// -------------------------------------------------------------------------

pub const FieldSpec = struct {
    name: []const u8,
    type: *const Type,
    offset: usize,
};

pub const StructSpec = struct {
    name: []const u8,
    size: usize,
    alignment: usize,
    fields: []const FieldSpec,
};

/// A struct laid out as the C compiler laid it out, from `sizeof`,
/// `_Alignof` and `offsetof`. It starts as all zeroes, as C's `= {0}` does.
pub fn defineStruct(self: *Registry, spec: StructSpec) Error!*const Type {
    if (self.find(spec.name) != null) return error.NameTaken;
    try checkShape(spec.size, spec.alignment);
    const a = self.arena.allocator();
    const fields = try a.alloc(model.Field, spec.fields.len);
    for (spec.fields, fields, 0..) |f, *out, i| {
        if (f.offset + f.type.size > spec.size or f.type.alignment == 0 or f.offset % f.type.alignment != 0) return error.InvalidLayout;
        for (spec.fields[0..i]) |earlier| if (std.mem.eql(u8, earlier.name, f.name)) return error.InvalidLayout;
        out.* = .{
            .name = .of(try a.dupeZ(u8, f.name)),
            .type = f.type,
            .offset = f.offset,
            .default = null,
            .attributes = .empty,
            .bit_offset = 0,
            .is_comptime = false,
            .is_bit_field = false,
        };
    }
    const t = try newType(self, spec.name);
    t.kind = .@"struct";
    t.size = spec.size;
    t.alignment = @intCast(spec.alignment);
    t.bit_size = @intCast(spec.size * 8);
    t.default = try zeroes(self, spec.size, spec.alignment);
    t.info = .{ .@"struct" = .{ .fields = .of(fields), .backing = null, .layout = .@"extern", .is_tuple = false } };
    try self.addType(t);
    return t;
}

pub const MemberSpec = struct {
    name: []const u8,
    value: i64,
};

pub const EnumSpec = struct {
    name: []const u8,
    /// An integer type: `c_int` for most C enums.
    tag: *const Type,
    members: []const MemberSpec,
    /// Whether a value no member names is refused. C allows one.
    is_exhaustive: bool = false,
};

pub fn defineEnum(self: *Registry, spec: EnumSpec) Error!*const Type {
    if (self.find(spec.name) != null) return error.NameTaken;
    if (spec.tag.kind != .int or spec.tag.info.int.bits > 64) return error.InvalidLayout;
    const a = self.arena.allocator();
    const members = try a.alloc(model.Member, spec.members.len);
    for (spec.members, members, 0..) |m, *out, i| {
        for (spec.members[0..i]) |earlier| if (std.mem.eql(u8, earlier.name, m.name)) return error.InvalidLayout;
        const tag = spec.tag.info.int;
        if (!bits.fits(m.value, tag.bits, tag.signed)) return error.InvalidLayout;
        out.* = .{ .name = .of(try a.dupeZ(u8, m.name)), .value = @bitCast(m.value), .attributes = .empty };
    }
    const t = try newType(self, spec.name);
    t.kind = .@"enum";
    t.size = spec.tag.size;
    t.alignment = spec.tag.alignment;
    t.bit_size = spec.tag.bit_size;
    t.info = .{ .@"enum" = .{ .tag = spec.tag, .members = .of(members), .is_exhaustive = spec.is_exhaustive } };
    if (members.len > 0 or !spec.is_exhaustive) {
        const initial = try zeroes(self, t.size, t.alignment);
        if (members.len > 0) {
            const first: [*]u8 = @ptrCast(@constCast(initial));
            Value.init(t, first).storeRaw(members[0].value);
        }
        t.default = initial;
    }
    try self.addType(t);
    return t;
}

pub const ArmSpec = struct {
    name: []const u8,
    type: *const Type,
};

pub const UnionSpec = struct {
    name: []const u8,
    size: usize,
    alignment: usize,
    arms: []const ArmSpec,
};

/// A C union: every arm at the first byte, and none known to be live.
pub fn defineUnion(self: *Registry, spec: UnionSpec) Error!*const Type {
    if (self.find(spec.name) != null) return error.NameTaken;
    try checkShape(spec.size, spec.alignment);
    const a = self.arena.allocator();
    const arms = try a.alloc(model.Field, spec.arms.len);
    for (spec.arms, arms, 0..) |arm, *out, i| {
        if (arm.type.size > spec.size or arm.type.alignment > spec.alignment) return error.InvalidLayout;
        for (spec.arms[0..i]) |earlier| if (std.mem.eql(u8, earlier.name, arm.name)) return error.InvalidLayout;
        out.* = .{
            .name = .of(try a.dupeZ(u8, arm.name)),
            .type = arm.type,
            .offset = 0,
            .default = null,
            .attributes = .empty,
            .bit_offset = 0,
            .is_comptime = false,
            .is_bit_field = false,
        };
    }
    const t = try newType(self, spec.name);
    t.kind = .@"union";
    t.size = spec.size;
    t.alignment = @intCast(spec.alignment);
    t.bit_size = @intCast(spec.size * 8);
    t.default = try zeroes(self, spec.size, spec.alignment);
    t.info = .{ .@"union" = .{ .arms = .of(arms), .tag = null, .ops = null, .layout = .@"extern" } };
    try self.addType(t);
    return t;
}

fn checkShape(size: usize, alignment: usize) Error!void {
    if (alignment == 0 or !std.math.isPowerOfTwo(alignment) or size % alignment != 0) return error.InvalidLayout;
    if (size * 8 > std.math.maxInt(u32)) return error.InvalidLayout;
}

// -------------------------------------------------------------------------
// In the arena
// -------------------------------------------------------------------------

pub fn newType(self: *Registry, name: []const u8) Error!*Type {
    const a = self.arena.allocator();
    const t = try a.create(Type);
    const owned = try a.dupeZ(u8, name);
    t.* = .{
        .name = .of(owned),
        .id = hashing.hashBytes(owned),
        .size = 0,
        .default = null,
        .attributes = .empty,
        .methods = .empty,
        .alignment = 1,
        .bit_size = 0,
        .kind = .void,
        .info = std.mem.zeroes(model.Info),
    };
    return t;
}

fn zeroes(self: *Registry, size: usize, alignment: usize) Error!*const anyopaque {
    const memory = self.arena.allocator().rawAlloc(@max(size, 1), .fromByteUnits(alignment), @returnAddress()) orelse
        return error.OutOfMemory;
    @memset(memory[0..@max(size, 1)], 0);
    return memory;
}
