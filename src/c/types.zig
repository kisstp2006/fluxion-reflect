// SPDX-License-Identifier: BSL-1.0

//! `include/fluxion_reflect/types.h`: questions about a type.

const std = @import("std");

const model = @import("../model.zig");
const base = @import("base.zig");
const Type = model.Type;
const Field = model.Field;
const span = base.span;

export fn fxr_kind_name(kind: u8) [*:0]const u8 {
    const k = std.enums.fromInt(model.Kind, kind) orelse return "unknown";
    return @tagName(k);
}

export fn fxr_type_field(t: *const Type, name: [*:0]const u8) ?*const Field {
    return t.field(span(name));
}

export fn fxr_type_member(t: *const Type, name: [*:0]const u8) ?*const model.Member {
    return t.member(span(name));
}

export fn fxr_type_method(t: *const Type, name: [*:0]const u8) ?*const model.Method {
    return t.method(span(name));
}

fn findAttribute(list: model.List(model.Attribute), wanted: *const Type) ?*const anyopaque {
    for (list.slice()) |a| if (a.type.same(wanted)) return a.value;
    return null;
}

export fn fxr_type_attribute(t: *const Type, wanted: *const Type) ?*const anyopaque {
    return findAttribute(t.attributes, wanted);
}

export fn fxr_field_attribute(f: *const Field, wanted: *const Type) ?*const anyopaque {
    return findAttribute(f.attributes, wanted);
}

export fn fxr_type_child(t: *const Type) ?*const Type {
    return t.child();
}

export fn fxr_type_same(a: *const Type, b: *const Type) bool {
    return a.same(b);
}

export fn fxr_type_fingerprint(t: *const Type) u64 {
    return t.fingerprint();
}

export fn fxr_type_describe(t: *const Type, buffer: ?[*]u8, capacity: usize) usize {
    var clip: base.Clip = .init(buffer, capacity);
    t.describe(&clip.writer) catch {};
    return clip.finish();
}

export fn fxr_type_suggest(t: *const Type, name: [*:0]const u8) ?[*:0]const u8 {
    return if (t.suggest(span(name))) |near| near.ptr else null;
}
