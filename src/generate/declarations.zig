// SPDX-License-Identifier: BSL-1.0

//! The declarations a type shapes its descriptor with: `reflect_attributes`,
//! `reflect_fields` and `reflect_methods`, and fluxion-json's `json_*`
//! declarations, kept as attributes so that `reflect.json` spells a value
//! as fluxion-json spells the type.

const std = @import("std");

const model = @import("../model.zig");
const attr = @import("../attr.zig");
const json = @import("../json.zig");
const generate = @import("../generate.zig");
const defaults = @import("defaults.zig");
const thunks = @import("thunks.zig");

const Attribute = model.Attribute;
const Method = model.Method;
const List = model.List;
const typeOf = generate.typeOf;
const hasDecl = generate.hasDecl;
const refuse = generate.refuse;

pub fn check(comptime T: type) void {
    if (hasDecl(T, "reflect_fields")) {
        for (std.meta.fieldNames(@TypeOf(T.reflect_fields))) |name| {
            const known = switch (@typeInfo(T)) {
                .@"struct", .@"union", .@"enum" => @hasField(T, name),
                else => false,
            };
            if (!known) refuse(T, "reflect_fields names ." ++ name ++ ", which it does not have");
        }
    }
}

// -------------------------------------------------------------------------
// Attributes
// -------------------------------------------------------------------------

pub fn typeAttributes(comptime T: type) List(Attribute) {
    return comptime blk: {
        var out: []const Attribute = if (hasDecl(T, "reflect_attributes")) attributes(T.reflect_attributes) else &.{};
        if (hasDecl(T, "json_tag")) out = out ++ [_]Attribute{attributeOf(json.Tag{ .key = T.json_tag })};
        if (hasDecl(T, "toJson") or hasDecl(T, "fromJson")) out = out ++ [_]Attribute{attributeOf(json.Hooked{})};
        if (isArrayList(T)) out = out ++ [_]Attribute{attributeOf(json.Items{})};
        if (isMap(T)) out = out ++ [_]Attribute{attributeOf(json.Map{})};
        break :blk listOf(out);
    };
}

pub fn fieldAttributes(comptime T: type, comptime name: []const u8) List(Attribute) {
    return comptime blk: {
        const listed = hasDecl(T, "reflect_fields") and @hasField(@TypeOf(T.reflect_fields), name);
        var out: []const Attribute = if (listed) attributes(@field(T.reflect_fields, name)) else &.{};
        if (jsonName(T, name)) |renamed| out = out ++ [_]Attribute{attributeOf(json.Name{ .text = renamed })};
        if (jsonIgnored(T, name)) out = out ++ [_]Attribute{attributeOf(json.Ignored{})};
        break :blk listOf(out);
    };
}

fn listOf(comptime items: []const Attribute) List(Attribute) {
    if (items.len == 0) return .empty;
    return .of(&defaults.Static([items.len]Attribute, items[0..items.len].*).held);
}

fn attributeOf(comptime value: anytype) Attribute {
    const held = defaults.hold(@TypeOf(value), value);
    return .{ .type = held.type, .value = held.value };
}

fn attributes(comptime tuple: anytype) []const Attribute {
    const info = @typeInfo(@TypeOf(tuple));
    if (info != .@"struct" or !info.@"struct".is_tuple) {
        @compileError("fluxion-reflect: attributes are a tuple of values, such as .{ reflect.attr.Doc{ .text = \"...\" } }");
    }
    return comptime blk: {
        const fields = info.@"struct".fields;
        var out: [fields.len]Attribute = undefined;
        for (fields, 0..) |f, i| {
            const held = if (f.is_comptime)
                defaults.materialize(f.type, @ptrCast(@alignCast(f.default_value_ptr.?)))
            else
                defaults.hold(f.type, @field(tuple, f.name));
            out[i] = .{ .type = held.type, .value = held.value };
        }
        const final = out;
        break :blk &final;
    };
}

// -------------------------------------------------------------------------
// What fluxion-json's declarations say
// -------------------------------------------------------------------------

fn jsonName(comptime T: type, comptime name: []const u8) ?[]const u8 {
    if (hasDecl(T, "json_rename") and @hasField(@TypeOf(T.json_rename), name)) return @field(T.json_rename, name);
    if (hasDecl(T, "json_case")) return convertCase(name, @tagName(T.json_case));
    return null;
}

fn jsonIgnored(comptime T: type, comptime name: []const u8) bool {
    if (!hasDecl(T, "json_ignore")) return false;
    inline for (T.json_ignore) |entry| {
        if (std.mem.eql(u8, @tagName(entry), name)) return true;
    }
    return false;
}

fn convertCase(comptime name: []const u8, comptime case: []const u8) []const u8 {
    return comptime blk: {
        var out: [name.len]u8 = undefined;
        var len = 0;
        var upper = std.mem.eql(u8, case, "pascal");
        for (name) |c| {
            if (c == '_' and len > 0) {
                if (std.mem.eql(u8, case, "kebab")) {
                    out[len] = '-';
                    len += 1;
                } else upper = true;
                continue;
            }
            out[len] = if (upper) std.ascii.toUpper(c) else c;
            upper = false;
            len += 1;
        }
        const final = out[0..len].*;
        break :blk &final;
    };
}

fn isArrayList(comptime T: type) bool {
    const info = @typeInfo(T);
    if (info != .@"struct" or !@hasField(T, "items") or !@hasField(T, "capacity")) return false;
    const items = @typeInfo(@FieldType(T, "items"));
    if (items != .pointer or items.pointer.size != .slice) return false;
    const fields = info.@"struct".fields.len;
    return fields == 2 or (fields == 3 and @hasField(T, "allocator"));
}

fn isMap(comptime T: type) bool {
    return @typeInfo(T) == .@"struct" and @hasDecl(T, "KV") and @hasDecl(T, "iterator");
}

// -------------------------------------------------------------------------
// Methods
// -------------------------------------------------------------------------

pub fn methodsOf(comptime T: type) List(Method) {
    if (!hasDecl(T, "reflect_methods")) return .empty;
    const spec = T.reflect_methods;
    const listed = @typeInfo(@TypeOf(spec)).@"struct";
    return comptime blk: {
        var out: [listed.fields.len]Method = undefined;
        for (listed.fields, 0..) |f, i| {
            out[i] = if (listed.is_tuple)
                methodOf(T, methodName(T, @field(spec, f.name)), .{})
            else
                methodOf(T, f.name, @field(spec, f.name));
        }
        const final = out;
        break :blk .of(&final);
    };
}

fn methodName(comptime T: type, comptime entry: anytype) [:0]const u8 {
    return switch (@typeInfo(@TypeOf(entry))) {
        .enum_literal => @tagName(entry),
        .pointer => entry,
        else => refuse(T, "reflect_methods lists names, as in .{ .heal, \"reset\" }, or attributes by name, as in .{ .heal = .{} }"),
    };
}

fn methodOf(comptime T: type, comptime name: [:0]const u8, comptime source: anytype) Method {
    if (!@hasDecl(T, name)) refuse(T, "reflect_methods names " ++ name ++ ", which it does not declare");
    const function = @field(T, name);
    const F = @TypeOf(function);
    if (@typeInfo(F) != .@"fn") refuse(T, "reflect_methods names " ++ name ++ ", which is not a function");
    const info = @typeInfo(F).@"fn";
    if (info.is_generic) refuse(T, name ++ " is generic, so there is no one function to call");
    if (info.calling_convention == .@"inline") refuse(T, name ++ " is inline, so it has no address to call");
    checkParams(T, name, info.params.len - @intFromBool(takesSelf(T, info)), source);
    return .{
        .name = .of(name),
        .type = typeOf(F),
        .function = @ptrCast(&thunks.Storage(function).pointer),
        .invoke = if (info.is_var_args) null else &thunks.Invoker(F).invoke,
        .attributes = attributeList(source),
    };
}

/// An attribute list from a tuple of values, or an empty one.
pub fn attributeList(comptime tuple: anytype) List(Attribute) {
    if (@typeInfo(@TypeOf(tuple)).@"struct".fields.len == 0) return .empty;
    return listOf(attributes(tuple));
}

/// Whether a method's first parameter is its own type, or a pointer to it: `self`.
fn takesSelf(comptime T: type, comptime info: std.builtin.Type.Fn) bool {
    if (info.params.len == 0) return false;
    const first = info.params[0].type orelse return false;
    if (first == T) return true;
    const p = @typeInfo(first);
    return p == .pointer and p.pointer.size == .one and p.pointer.child == T;
}

/// `attr.Params` has to name every parameter there is, no more and no fewer.
pub fn checkParams(comptime T: type, comptime name: []const u8, comptime expected: usize, comptime source: anytype) void {
    inline for (source) |entry| {
        if (@TypeOf(entry) == attr.Params) {
            if (entry.names.len != expected) {
                refuse(T, std.fmt.comptimePrint("{s} has {d} parameters to name (self is implied), and attr.Params lists {d}", .{ name, expected, entry.names.len }));
            }
        }
    }
}
