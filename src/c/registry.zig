// SPDX-License-Identifier: BSL-1.0

//! `include/fluxion_reflect/registry.h`: types by name, and C's own types
//! and functions described to a registry.
//!
//! The types in a description are optional here although C passes them as
//! plain pointers: one looked up under a misspelt name arrives as NULL, and
//! is refused rather than followed.

const model = @import("../model.zig");
const base = @import("base.zig");
const Registry = @import("../Registry.zig");
const Type = model.Type;
const Method = model.Method;
const Status = base.Status;
const allocator = base.allocator;
const statusOf = base.statusOf;
const done = base.done;
const span = base.span;

export fn fxr_registry_create() ?*Registry {
    const r = allocator.create(Registry) catch return null;
    r.* = .init(allocator);
    return r;
}

export fn fxr_registry_destroy(registry: ?*Registry) void {
    const r = registry orelse return;
    r.deinit();
    allocator.destroy(r);
}

export fn fxr_registry_add(r: *Registry, t: ?*const Type) Status {
    return done(r.addType(t orelse return .unknown_type));
}

export fn fxr_registry_find(r: *const Registry, name: [*:0]const u8) ?*const Type {
    return r.find(span(name));
}

export fn fxr_registry_find_id(r: *const Registry, id: u64) ?*const Type {
    return r.findId(id);
}

export fn fxr_registry_resolve(r: *Registry, expression: [*:0]const u8, out: *?*const Type) Status {
    out.* = r.resolve(span(expression)) catch |err| return statusOf(err);
    return .ok;
}

export fn fxr_registry_count(r: *const Registry) usize {
    return r.types().len;
}

export fn fxr_registry_at(r: *const Registry, index: usize) ?*const Type {
    const all = r.types();
    return if (index < all.len) all[index] else null;
}

export fn fxr_registry_suggest(r: *const Registry, name: [*:0]const u8) ?[*:0]const u8 {
    return if (r.suggest(span(name))) |near| near.ptr else null;
}

export fn fxr_registry_function(r: *const Registry, name: [*:0]const u8) ?*const Method {
    return r.function(span(name));
}

pub const FieldDesc = extern struct {
    name: [*:0]const u8,
    type: ?*const Type,
    offset: usize,
};

pub const StructDesc = extern struct {
    name: [*:0]const u8,
    size: usize,
    alignment: usize,
    fields: ?[*]const FieldDesc,
    field_count: usize,
};

export fn fxr_registry_define_struct(r: *Registry, desc: *const StructDesc, out: ?*?*const Type) Status {
    const given = if (desc.fields) |f| f[0..desc.field_count] else &.{};
    const fields = allocator.alloc(Registry.FieldSpec, given.len) catch return .out_of_memory;
    defer allocator.free(fields);
    for (given, fields) |g, *f| f.* = .{ .name = span(g.name), .type = g.type orelse return .unknown_type, .offset = g.offset };
    const t = r.defineStruct(.{ .name = span(desc.name), .size = desc.size, .alignment = desc.alignment, .fields = fields }) catch |err| return statusOf(err);
    if (out) |o| o.* = t;
    return .ok;
}

pub const MemberDesc = extern struct {
    name: [*:0]const u8,
    value: i64,
};

pub const EnumDesc = extern struct {
    name: [*:0]const u8,
    tag: ?*const Type,
    members: ?[*]const MemberDesc,
    member_count: usize,
    is_exhaustive: bool,
};

export fn fxr_registry_define_enum(r: *Registry, desc: *const EnumDesc, out: ?*?*const Type) Status {
    const tag = desc.tag orelse return .unknown_type;
    const given = if (desc.members) |m| m[0..desc.member_count] else &.{};
    const members = allocator.alloc(Registry.MemberSpec, given.len) catch return .out_of_memory;
    defer allocator.free(members);
    for (given, members) |g, *m| m.* = .{ .name = span(g.name), .value = g.value };
    const t = r.defineEnum(.{ .name = span(desc.name), .tag = tag, .members = members, .is_exhaustive = desc.is_exhaustive }) catch |err| return statusOf(err);
    if (out) |o| o.* = t;
    return .ok;
}

pub const ArmDesc = extern struct {
    name: [*:0]const u8,
    type: ?*const Type,
};

pub const UnionDesc = extern struct {
    name: [*:0]const u8,
    size: usize,
    alignment: usize,
    arms: ?[*]const ArmDesc,
    arm_count: usize,
};

export fn fxr_registry_define_union(r: *Registry, desc: *const UnionDesc, out: ?*?*const Type) Status {
    const given = if (desc.arms) |a| a[0..desc.arm_count] else &.{};
    const arms = allocator.alloc(Registry.ArmSpec, given.len) catch return .out_of_memory;
    defer allocator.free(arms);
    for (given, arms) |g, *a| a.* = .{ .name = span(g.name), .type = g.type orelse return .unknown_type };
    const t = r.defineUnion(.{ .name = span(desc.name), .size = desc.size, .alignment = desc.alignment, .arms = arms }) catch |err| return statusOf(err);
    if (out) |o| o.* = t;
    return .ok;
}

pub const FunctionDesc = extern struct {
    name: [*:0]const u8,
    params: ?[*]const ?*const Type,
    param_count: usize,
    return_type: ?*const Type,
    function: *const anyopaque,
    invoke: *const model.Invoke,
};

export fn fxr_registry_define_function(r: *Registry, desc: *const FunctionDesc, out: ?*?*const Method) Status {
    const given = if (desc.params) |p| p[0..desc.param_count] else &.{};
    const params = allocator.alloc(*const Type, given.len) catch return .out_of_memory;
    defer allocator.free(params);
    for (given, params) |g, *p| p.* = g orelse return .unknown_type;
    const m = r.defineFunction(.{
        .name = span(desc.name),
        .params = params,
        .return_type = desc.return_type orelse return .unknown_type,
        .function = desc.function,
        .invoke = desc.invoke,
    }) catch |err| return statusOf(err);
    if (out) |o| o.* = m;
    return .ok;
}
