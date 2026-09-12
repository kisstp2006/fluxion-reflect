// SPDX-License-Identifier: BSL-1.0

//! JSON or CBOR read into a `Value`, as fluxion-json reads the Zig type:
//! from text, from CBOR, or from a `json.Value` tree.

const std = @import("std");
const json = @import("fluxion_json");

const model = @import("../model.zig");
const value_mod = @import("../value.zig");
const reflect_json = @import("../json.zig");
const spelling = @import("write.zig");

const Value = value_mod.Value;
const Type = model.Type;
const Field = model.Field;
const Tag = reflect_json.Tag;
const Items = reflect_json.Items;
const Hooked = reflect_json.Hooked;
const Map = reflect_json.Map;
const ReadError = reflect_json.ReadError;
const ReadOptions = reflect_json.ReadOptions;
const isByte = spelling.isByte;
const keyOf = spelling.keyOf;
const ignored = spelling.ignored;

/// Read JSON text, or CBOR, into `into`.
pub fn parse(into: Value, text: []const u8, options: ReadOptions) ReadError!void {
    var reader: json.Reader = .init(options.allocator, text, .{
        .syntax = options.syntax,
        .format = options.format,
        .max_depth = options.max_depth,
        .diagnostics = options.diagnostics,
    });
    defer reader.deinit();
    try read(into, &reader, options);
    if (try reader.next() != null) {
        reader.report("more after the value", .{});
        return error.SyntaxError;
    }
}

/// Read the next value from `reader` into `into`: from text, CBOR, or a
/// `json.Value` tree (`json.Reader.initValue`).
pub fn read(into: Value, reader: *json.Reader, options: ReadOptions) ReadError!void {
    var c: Context = .{ .reader = reader, .options = options };
    return c.value(into);
}

const Context = struct {
    reader: *json.Reader,
    options: ReadOptions,

    fn next(c: *Context) ReadError!json.Reader.Token {
        return (try c.reader.next()) orelse error.SyntaxError;
    }

    fn peek(c: *Context) ReadError!json.Reader.Kind {
        return (try c.reader.peek()) orelse error.SyntaxError;
    }

    fn wrong(c: *Context, t: *const Type, expected: []const u8) ReadError {
        c.reader.report("expected {s} for a {s}", .{ expected, t.name.slice() });
        return error.WrongType;
    }

    fn check(c: *Context, t: *const Type, result: value_mod.Error!void) ReadError!void {
        result catch |err| return c.failed(t, err);
    }

    fn failed(c: *Context, t: *const Type, err: value_mod.Error) ReadError {
        return switch (err) {
            error.OutOfRange => {
                c.reader.report("the number does not fit a {s}", .{t.name.slice()});
                return error.OutOfRange;
            },
            error.NoSuchMember, error.NoSuchField => error.UnknownTag,
            error.OutOfMemory => error.OutOfMemory,
            error.Unsupported => error.Unsupported,
            else => c.wrong(t, "something else"),
        };
    }

    fn value(c: *Context, into: Value) ReadError!void {
        const t = into.type;
        if (t.attribute(Hooked) != null or t.attribute(Map) != null) return error.Unsupported;
        switch (t.kind) {
            .bool => {
                const token = try c.next();
                if (token != .bool) return c.wrong(t, "true or false");
                try c.check(t, into.setBool(token.bool));
            },
            .int => {
                const token = try c.next();
                if (token != .number) return c.wrong(t, "a whole number");
                try c.integer(into, token.number);
            },
            .float => {
                const token = try c.next();
                if (token != .number) return c.wrong(t, "a number");
                try c.check(t, into.setFloat(token.number.asFloat(f128)));
            },
            .optional => {
                if (try c.peek() == .null) {
                    _ = try c.next();
                    return c.check(t, into.setNull());
                }
                try c.value(into.unwrapOrInit() catch |err| return c.failed(t, err));
            },
            .@"enum" => try c.enumeration(into),
            .@"union" => try c.@"union"(into),
            .@"struct" => {
                if (t.info.@"struct".is_tuple) return c.tuple(into);
                if (t.attribute(Items) != null) return c.arrayList(into);
                try c.members(into, false, null);
            },
            .array => try c.array(into),
            .vector => try c.array(into),
            .slice => try c.slice(into),
            .pointer => {
                const p = t.info.pointer;
                if (t.isString() and p.size != .one) {
                    if (p.size == .c and try c.peek() == .null) {
                        _ = try c.next();
                        return c.check(t, into.setNull());
                    }
                    const token = try c.next();
                    if (token != .string) return c.wrong(t, "a string");
                    const bytes = try c.options.allocator.dupeZ(u8, token.string);
                    return c.check(t, into.setStringZ(bytes));
                }
                if (p.size != .one or p.child.kind == .function or p.child.kind == .@"opaque") return error.Unsupported;
                if (into.is_const) return c.failed(t, error.ReadOnly);
                const target = Value.create(c.options.allocator, p.child) catch |err| switch (err) {
                    error.NoDefault => try c.blank(p.child),
                    else => return c.failed(t, err),
                };
                try c.value(target);
                into.storeRaw(@intFromPtr(target.ptr));
            },
            else => return error.Unsupported,
        }
    }

    /// Zeroed memory for a type with no default, about to be read over whole.
    fn blank(c: *Context, t: *const Type) ReadError!Value {
        const memory = c.options.allocator.rawAlloc(@max(t.size, 1), .fromByteUnits(t.alignment), @returnAddress()) orelse
            return error.OutOfMemory;
        @memset(memory[0..t.size], 0);
        return .init(t, memory);
    }

    fn integer(c: *Context, into: Value, n: json.Number) ReadError!void {
        const t = into.type;
        if (n.asInt(i128)) |i| return c.check(t, into.setInt(i));
        if (n.asInt(u128)) |u| return c.check(t, into.setInt(u));
        const f = n.asFloat(f128);
        if (!n.isInteger() and (!std.math.isFinite(f) or @floor(f) != f)) return c.wrong(t, "a whole number");
        try c.check(t, into.setFloat(f));
    }

    fn enumeration(c: *Context, into: Value) ReadError!void {
        const t = into.type;
        const token = try c.next();
        switch (token) {
            .string => |s| {
                for (t.members()) |*m| if (std.mem.eql(u8, keyOf(m.attributes, m.name), s)) {
                    if (t.info.@"enum".tag.info.int.signed) return c.check(t, into.setInt(@as(i64, @bitCast(m.value))));
                    return c.check(t, into.setInt(m.value));
                };
                c.reader.report("\"{s}\" is not one of {s}'s names", .{ s, t.name.slice() });
                return error.UnknownTag;
            },
            .number => |n| {
                const i = n.asInt(i128) orelse return error.UnknownTag;
                into.setInt(i) catch return error.UnknownTag;
            },
            else => return c.wrong(t, "a string"),
        }
    }

    // ---------------------------------------------------------------------
    // Unions
    // ---------------------------------------------------------------------

    fn armNamed(t: *const Type, name: []const u8) ?usize {
        for (t.fields(), 0..) |*f, i| if (std.mem.eql(u8, keyOf(f.attributes, f.name), name)) return i;
        return null;
    }

    fn @"union"(c: *Context, into: Value) ReadError!void {
        const t = into.type;
        if (t.info.@"union".tag == null) return error.Unsupported;
        if (t.attribute(Tag)) |tag| return c.taggedObject(into, tag.key);
        const token = try c.next();
        switch (token) {
            .string => |s| {
                const i = armNamed(t, s) orelse return c.unknownArm(t, s);
                if (t.fields()[i].type.kind != .void) return c.wrong(t, "an object with one member, for an arm that holds a value");
                _ = into.activateAt(i) catch |err| return c.failed(t, err);
            },
            .object_begin => {
                const inner = try c.next();
                if (inner != .key) return c.wrong(t, "an object with one member");
                const i = armNamed(t, inner.key) orelse return c.unknownArm(t, inner.key);
                const payload = into.activateAt(i) catch |err| return c.failed(t, err);
                if (payload.type.kind == .void) try c.reader.skipValue() else try c.value(payload);
                if (try c.next() != .object_end) return c.wrong(t, "an object with exactly one member");
            },
            else => return c.wrong(t, "an object with one member, or a string"),
        }
    }

    fn unknownArm(c: *Context, t: *const Type, name: []const u8) ReadError {
        c.reader.report("\"{s}\" is not one of {s}'s arms", .{ name, t.name.slice() });
        return error.UnknownTag;
    }

    /// `{"type": "circle", "radius": 2}`. When the tag is not the first
    /// member, the object is written out again with it first, and read from
    /// that.
    fn taggedObject(c: *Context, into: Value, tag_key: []const u8) ReadError!void {
        const t = into.type;
        const token = try c.next();
        if (token != .object_begin) return c.wrong(t, "an object");
        const first = try c.next();
        if (first == .key and std.mem.eql(u8, first.key, tag_key)) {
            const name = try c.next();
            if (name != .string) return c.wrong(t, "a string naming an arm");
            const i = armNamed(t, name.string) orelse return c.unknownArm(t, name.string);
            const payload = into.activateAt(i) catch |err| return c.failed(t, err);
            return c.members(payload, true, tag_key);
        }
        if (first == .object_end) {
            c.reader.report("missing the \"{s}\" member that says which arm this is", .{tag_key});
            return error.MissingField;
        }

        var text: std.Io.Writer.Allocating = .init(c.options.allocator);
        defer text.deinit();
        var copy: json.Writer = .init(&text.writer, .{});
        var arm: ?[]const u8 = null;
        copy.beginObject() catch return error.OutOfMemory;
        var key = first.key;
        while (true) {
            if (std.mem.eql(u8, key, tag_key)) {
                const name = try c.next();
                if (name != .string) return c.wrong(t, "a string naming an arm");
                arm = try c.options.allocator.dupe(u8, name.string);
            } else {
                copy.key(key) catch return error.OutOfMemory;
                try copyValue(c.reader, &copy);
            }
            const after = try c.next();
            if (after == .object_end) break;
            key = after.key;
        }
        copy.endObject() catch return error.OutOfMemory;
        const name = arm orelse {
            c.reader.report("missing the \"{s}\" member that says which arm this is", .{tag_key});
            return error.MissingField;
        };
        const i = armNamed(t, name) orelse return c.unknownArm(t, name);
        const payload = into.activateAt(i) catch |err| return c.failed(t, err);
        var again: json.Reader = .init(c.options.allocator, text.written(), .{ .max_depth = c.options.max_depth });
        defer again.deinit();
        var inner: Context = .{ .reader = &again, .options = c.options };
        try inner.members(payload, false, null);
    }

    // ---------------------------------------------------------------------
    // Structs
    // ---------------------------------------------------------------------

    fn members(c: *Context, into: Value, open: bool, skip_key: ?[]const u8) ReadError!void {
        const t = into.type;
        if (!open) {
            const token = try c.next();
            if (token != .object_begin) return c.wrong(t, "an object");
        }
        if (t.kind == .void) {
            while (try c.next() != .object_end) try c.reader.skipValue();
            return;
        }
        if (t.kind != .@"struct") return error.Unsupported;
        const fields = t.fields();
        var seen_small: [64]bool = @splat(false);
        const seen: []bool = if (fields.len <= seen_small.len) seen_small[0..fields.len] else try c.options.allocator.alloc(bool, fields.len);
        @memset(seen, false);
        while (true) {
            const key = switch (try c.next()) {
                .key => |name| name,
                .object_end => break,
                else => return error.SyntaxError,
            };
            if (skip_key) |skipped| if (std.mem.eql(u8, key, skipped)) {
                try c.reader.skipValue();
                continue;
            };
            const i = fieldNamed(fields, key) orelse {
                if (c.options.unknown_fields == .fail) {
                    c.reader.report("{s} has no field \"{s}\"", .{ t.name.slice(), key });
                    return error.UnknownField;
                }
                try c.reader.skipValue();
                continue;
            };
            if (fields[i].is_comptime) {
                try c.reader.skipValue();
                continue;
            }
            try c.value(into.fieldAt(i) catch |err| return c.failed(t, err));
            seen[i] = true;
        }
        if (c.options.patch) return;
        for (fields, seen, 0..) |*f, was_seen, i| {
            if (was_seen or f.is_comptime or ignored(f)) continue;
            const member = into.fieldAt(i) catch |err| return c.failed(t, err);
            if (f.default) |d| {
                try c.check(t, member.copyFrom(.initConst(f.type, d)));
            } else if (f.type.kind == .optional) {
                try c.check(t, member.setNull());
            } else {
                c.reader.report("missing the field \"{s}\", which has no default", .{keyOf(f.attributes, f.name)});
                return error.MissingField;
            }
        }
    }

    fn fieldNamed(fields: []const Field, key: []const u8) ?usize {
        for (fields, 0..) |*f, i| {
            if (ignored(f)) continue;
            if (std.mem.eql(u8, keyOf(f.attributes, f.name), key)) return i;
        }
        return null;
    }

    fn tuple(c: *Context, into: Value) ReadError!void {
        const t = into.type;
        const token = try c.next();
        if (token != .array_begin) return c.wrong(t, "an array");
        const n = t.fields().len;
        for (0..n) |i| {
            if (try c.peek() == .array_end) return c.lengths(n, i);
            try c.value(into.fieldAt(i) catch |err| return c.failed(t, err));
        }
        if (try c.next() != .array_end) return c.lengths(n, n + 1);
    }

    // ---------------------------------------------------------------------
    // Arrays, vectors, slices and array lists
    // ---------------------------------------------------------------------

    fn lengths(c: *Context, want: usize, found: usize) ReadError {
        c.reader.report("expected {d} items, found {d}", .{ want, found });
        return error.LengthMismatch;
    }

    fn array(c: *Context, into: Value) ReadError!void {
        const t = into.type;
        const n = into.len() catch return error.Unsupported;
        const token = try c.next();
        if (t.kind == .array and isByte(t.info.array.child) and token == .string) {
            const s = token.string;
            const out: [*]u8 = @ptrCast(into.ptr);
            if (t.info.array.sentinel != null) {
                if (s.len > n) return c.lengths(n, s.len);
                @memcpy(out[0..s.len], s);
                @memset(out[s.len..n], 0);
                return;
            }
            if (s.len != n) return c.lengths(n, s.len);
            @memcpy(out[0..n], s);
            return;
        }
        if (token != .array_begin) return c.wrong(t, "an array");
        var count: usize = 0;
        while (try c.peek() != .array_end) : (count += 1) {
            if (count == n) return c.lengths(n, n + 1);
            if (t.kind == .vector) {
                try c.element(into, count);
            } else try c.value(into.index(count) catch |err| return c.failed(t, err));
        }
        _ = try c.next();
        if (count != n) return c.lengths(n, count);
    }

    fn element(c: *Context, into: Value, i: usize) ReadError!void {
        if (into.index(i)) |item| return c.value(item) else |_| {}
        const child = into.type.info.vector.child;
        var buffer: [16]u8 align(16) = @splat(0);
        if (child.size > buffer.len) return error.Unsupported;
        const item: Value = .init(child, &buffer);
        try c.value(item);
        try c.check(into.type, into.setElement(i, item));
    }

    fn slice(c: *Context, into: Value) ReadError!void {
        const t = into.type;
        const s = t.info.slice;
        const gpa = c.options.allocator;
        if (isByte(s.child)) {
            const token = try c.next();
            if (token != .string) return c.wrong(t, "a string");
            const bytes = try gpa.allocSentinel(u8, token.string.len, 0);
            @memcpy(bytes, token.string);
            return c.check(t, into.setSliceRaw(bytes.ptr, bytes.len));
        }
        const token = try c.next();
        if (token != .array_begin) return c.wrong(t, "an array");
        const size = s.child.size;
        const alignment: std.mem.Alignment = .fromByteUnits(s.child.alignment);
        var grown: []u8 = &.{};
        defer if (grown.len > 0) gpa.rawFree(grown, alignment, @returnAddress());
        var count: usize = 0;
        while (try c.peek() != .array_end) : (count += 1) {
            if ((count + 1) * size > grown.len) {
                const bigger = @max(2 * grown.len, (count + 1) * size, 64);
                const memory = gpa.rawAlloc(bigger, alignment, @returnAddress()) orelse return error.OutOfMemory;
                @memcpy(memory[0 .. count * size], grown[0 .. count * size]);
                if (grown.len > 0) gpa.rawFree(grown, alignment, @returnAddress());
                grown = memory[0..bigger];
            }
            const at = grown[count * size ..][0..size];
            if (s.child.default) |d| @memcpy(at, @as([*]const u8, @ptrCast(d))[0..size]) else @memset(at, 0);
            try c.value(.init(s.child, at.ptr));
        }
        _ = try c.next();
        const end_size: usize = if (s.sentinel != null) size else 0;
        const memory = gpa.rawAlloc(@max(count * size + end_size, 1), alignment, @returnAddress()) orelse
            return error.OutOfMemory;
        @memcpy(memory[0 .. count * size], grown[0 .. count * size]);
        if (s.sentinel) |end| @memcpy(memory[count * size ..][0..size], @as([*]const u8, @ptrCast(end))[0..size]);
        try c.check(t, into.setSliceRaw(memory, count));
    }

    fn arrayList(c: *Context, into: Value) ReadError!void {
        const t = into.type;
        if (t.field("allocator") != null) return error.Unsupported;
        const items = into.field("items") catch |err| return c.failed(t, err);
        try c.slice(items);
        const count = items.len() catch return error.Unsupported;
        try c.check(t, (into.field("capacity") catch |err| return c.failed(t, err)).setInt(count));
    }
};

/// Streams one value from `reader` to `w` token by token, numbers as they
/// were written.
fn copyValue(reader: *json.Reader, w: *json.Writer) ReadError!void {
    var depth: usize = 0;
    while (true) {
        const token = (try reader.next()) orelse return error.SyntaxError;
        switch (token) {
            .object_begin => {
                w.beginObject() catch return error.OutOfMemory;
                depth += 1;
            },
            .array_begin => {
                w.beginArray() catch return error.OutOfMemory;
                depth += 1;
            },
            .object_end => {
                w.endObject() catch return error.OutOfMemory;
                depth -= 1;
            },
            .array_end => {
                w.endArray() catch return error.OutOfMemory;
                depth -= 1;
            },
            .key => |k| w.key(k) catch return error.OutOfMemory,
            .string => |s| w.writeString(s) catch return error.OutOfMemory,
            .number => |n| w.writeNumber(n) catch return error.OutOfMemory,
            .bool => |b| w.writeBool(b) catch return error.OutOfMemory,
            .null => w.writeNull() catch return error.OutOfMemory,
        }
        if (depth == 0 and token != .key) return;
    }
}
