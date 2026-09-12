// SPDX-License-Identifier: BSL-1.0

//! A `Value` written as JSON or CBOR, spelt as fluxion-json spells the Zig
//! type. How a key is spelt is here too, and `read.zig` reads keys by it.

const std = @import("std");
const Allocator = std.mem.Allocator;
const json = @import("fluxion_json");

const bits = @import("../bits.zig");
const model = @import("../model.zig");
const reflect_json = @import("../json.zig");
const Value = @import("../value.zig").Value;

const Type = model.Type;
const Field = model.Field;
const Name = reflect_json.Name;
const Ignored = reflect_json.Ignored;
const Tag = reflect_json.Tag;
const Items = reflect_json.Items;
const Hooked = reflect_json.Hooked;
const Map = reflect_json.Map;
const WriteError = reflect_json.WriteError;

/// Write `v` where a value goes next: at the top, as an array item, or after
/// a `key`.
pub fn write(w: *json.Writer, v: Value) WriteError!void {
    const t = v.type;
    if (t.attribute(Hooked) != null or t.attribute(Map) != null) return error.Unsupported;
    switch (t.kind) {
        .bool => try w.writeBool(v.toBool().?),
        .int => {
            const n = v.wideInt() orelse return error.Unsupported;
            if (std.math.cast(i64, n)) |small| return w.writeInt(small);
            if (n < 0) return w.writeInt(@as(i128, @intCast(n)));
            try w.writeInt(@as(u128, @intCast(n)));
        },
        .float => {
            const raw = v.raw();
            switch (t.info.float.bits) {
                16 => try w.writeFloat(@as(f16, @bitCast(@as(u16, @truncate(raw))))),
                32 => try w.writeFloat(@as(f32, @bitCast(@as(u32, @truncate(raw))))),
                64 => try w.writeFloat(@as(f64, @bitCast(@as(u64, @truncate(raw))))),
                80 => try w.writeFloat(@as(f80, @bitCast(@as(u80, @truncate(raw))))),
                else => try w.writeFloat(@as(f128, @bitCast(raw))),
            }
        },
        .@"enum" => {
            const m = t.memberOf(@truncate(bits.fromWide(v.wideInt().?))) orelse
                return w.writeInt(@as(i128, @intCast(v.wideInt().?)));
            try w.writeString(keyOf(m.attributes, m.name));
        },
        .optional => if (v.unwrap()) |inside| try write(w, inside) else try w.writeNull(),
        .@"union" => try writeUnion(w, v),
        .@"struct" => try writeStruct(w, v),
        .array => {
            const a = t.info.array;
            if (isByte(a.child) and a.sentinel != null) return w.writeString(std.mem.sliceTo(v.toString().?, 0));
            try writeItems(w, v);
        },
        .vector => try writeItems(w, v),
        .slice => if (isByte(t.info.slice.child)) try w.writeString(v.toString().?) else try writeItems(w, v),
        .pointer => {
            const p = t.info.pointer;
            switch (p.size) {
                .one => {
                    if (p.child.kind == .array and isByte(p.child.info.array.child) and p.child.info.array.sentinel != null) {
                        const target = v.deref() catch return error.Unsupported;
                        return w.writeString(std.mem.sliceTo(target.toString().?, 0));
                    }
                    if (p.child.kind == .function or p.child.kind == .@"opaque") return error.Unsupported;
                    try write(w, v.deref() catch return error.Unsupported);
                },
                .many => {
                    if (!isByte(p.child) or p.sentinel == null) return error.Unsupported;
                    try w.writeString(v.toString() orelse return error.Unsupported);
                },
                .c => {
                    if (!isByte(p.child)) return error.Unsupported;
                    if (v.toString()) |s| try w.writeString(s) else try w.writeNull();
                },
            }
        },
        .type => try w.writeString(if (v.asType()) |named| named.name.slice() else return w.writeNull()),
        else => return error.Unsupported,
    }
}

/// `v` as JSON text, or with `.format = .cbor` as CBOR. The caller frees it.
pub fn stringify(gpa: Allocator, v: Value, options: json.WriteOptions) WriteError![]u8 {
    var out: std.Io.Writer.Allocating = .init(gpa);
    defer out.deinit();
    var w: json.Writer = .init(&out.writer, options);
    write(&w, v) catch |err| return if (err == error.WriteFailed) error.OutOfMemory else err;
    return out.toOwnedSlice();
}

fn writeItems(w: *json.Writer, v: Value) WriteError!void {
    try w.beginArray();
    if (v.type.kind == .vector) {
        const info = v.type.info.vector;
        var buffer: [16]u8 align(16) = undefined;
        if (info.child.size > buffer.len) return error.Unsupported;
        for (0..info.len) |i| {
            const item: Value = .init(info.child, &buffer);
            v.getElement(i, item) catch return error.Unsupported;
            try write(w, item);
        }
    } else {
        const n = v.len() catch return error.Unsupported;
        for (0..n) |i| try write(w, v.index(i) catch return error.Unsupported);
    }
    try w.endArray();
}

fn writeUnion(w: *json.Writer, v: Value) WriteError!void {
    const live = v.active() orelse return error.Unsupported;
    const payload = v.payload() catch return error.Unsupported;
    const name = keyOf(live.attributes, live.name);
    if (v.type.attribute(Tag)) |tag| {
        if (payload.type.kind != .void and (payload.type.kind != .@"struct" or payload.type.info.@"struct".is_tuple)) return error.Unsupported;
        try w.beginObject();
        try w.key(tag.key);
        try w.writeString(name);
        if (payload.type.kind != .void) try writeMembers(w, payload);
        return w.endObject();
    }
    if (payload.type.kind == .void) return w.writeString(name);
    try w.beginObject();
    try w.key(name);
    try write(w, payload);
    try w.endObject();
}

fn writeStruct(w: *json.Writer, v: Value) WriteError!void {
    const s = v.type.info.@"struct";
    if (s.is_tuple) {
        try w.beginArray();
        for (0..s.fields.len) |i| {
            const item = v.fieldAt(i) catch return error.Unsupported;
            if (item.type.kind != .void) try write(w, item);
        }
        return w.endArray();
    }
    if (v.type.attribute(Items) != null) return write(w, v.field("items") catch return error.Unsupported);
    try w.beginObject();
    try writeMembers(w, v);
    try w.endObject();
}

fn writeMembers(w: *json.Writer, v: Value) WriteError!void {
    const fields = v.type.fields();
    if (!w.options.sort_keys) {
        for (fields, 0..) |*f, i| try writeMember(w, v, f, i);
        return;
    }
    var last: ?[]const u8 = null;
    for (0..fields.len) |_| {
        var next: ?usize = null;
        for (fields, 0..) |*f, i| {
            const key = keyOf(f.attributes, f.name);
            if (last) |l| if (!std.mem.lessThan(u8, l, key)) continue;
            if (next == null or std.mem.lessThan(u8, key, keyOf(fields[next.?].attributes, fields[next.?].name))) next = i;
        }
        const i = next orelse break;
        try writeMember(w, v, &fields[i], i);
        last = keyOf(fields[i].attributes, fields[i].name);
    }
}

fn writeMember(w: *json.Writer, v: Value, f: *const Field, i: usize) WriteError!void {
    if (ignored(f)) return;
    const member = v.fieldAt(i) catch return error.Unsupported;
    if (w.options.skip_nulls and member.type.kind == .optional and member.isNull()) return;
    if (w.options.skip_defaults and !f.is_comptime) {
        if (f.default) |d| if (member.eql(.initConst(f.type, d))) return;
    }
    try w.key(keyOf(f.attributes, f.name));
    try write(w, member);
}

// -------------------------------------------------------------------------
// How a key is spelt, for writing and reading alike
// -------------------------------------------------------------------------

pub fn isByte(t: *const Type) bool {
    return t.kind == .int and t.info.int.bits == 8 and !t.info.int.signed;
}

pub fn keyOf(attributes: model.List(model.Attribute), name: model.Str) []const u8 {
    for (attributes.slice()) |a| if (a.as(Name)) |renamed| return renamed.text;
    return name.slice();
}

pub fn ignored(f: *const Field) bool {
    return f.type.kind == .void or f.attribute(Ignored) != null;
}
