// SPDX-License-Identifier: BSL-1.0

//! A `Value` written as Zig syntax, the way ZON spells it.

const std = @import("std");
const Writer = std.Io.Writer;

const Value = @import("../value.zig").Value;
const max_depth = @import("../text.zig").max_depth;
const strings = @import("strings.zig");

const isText = strings.isText;
const writeString = strings.writeString;

pub fn write(v: Value, w: *Writer) Writer.Error!void {
    return writeValue(v, w, 0);
}

fn writeValue(v: Value, w: *Writer, depth: usize) Writer.Error!void {
    if (depth > max_depth) return w.writeAll("...");
    const t = v.type;
    switch (t.kind) {
        .void => try w.writeAll("{}"),
        .bool => try w.writeAll(if (v.toBool().?) "true" else "false"),
        .int => if (v.wideInt()) |n| try w.print("{d}", .{n}) else try w.print("<{s}>", .{t.name.slice()}),
        .float => try writeFloat(v, w),
        .@"enum" => if (v.toString()) |name| {
            try w.print(".{f}", .{std.zig.fmtIdPU(name)});
        } else try w.print("@enumFromInt({d})", .{v.wideInt().?}),
        .error_set => try writeError(v, w),
        .error_union => if (v.unwrap()) |inside| try writeValue(inside, w, depth + 1) else try writeError(v, w),
        .optional => if (v.unwrap()) |inside| try writeValue(inside, w, depth + 1) else try w.writeAll("null"),
        .type => try w.writeAll(if (v.asType()) |named| named.name.slice() else "null"),
        .pointer => {
            const address = v.address();
            if (address == 0) return w.writeAll("null");
            if (t.isString()) return writeString(v.toString().?, w);
            try w.print("@ptrFromInt(0x{x})", .{address});
        },
        .slice => if (t.isString()) try writeString(v.toString().?, w) else try writeItems(v, w, depth),
        .array => if (t.isString() and !v.is_bit_field and isText(v.toString().?))
            try writeString(std.mem.trimEnd(u8, v.toString().?, "\x00"), w)
        else
            try writeItems(v, w, depth),
        .vector => try writeVector(v, w, depth),
        .@"struct" => try writeStruct(v, w, depth),
        .@"union" => try writeUnion(v, w, depth),
        .function, .@"opaque", .noreturn => try w.print("<{s}>", .{t.name.slice()}),
    }
}

fn writeFloat(v: Value, w: *Writer) Writer.Error!void {
    const raw = v.raw();
    switch (v.type.info.float.bits) {
        16 => try w.print("{d}", .{@as(f16, @bitCast(@as(u16, @truncate(raw))))}),
        32 => try w.print("{d}", .{@as(f32, @bitCast(@as(u32, @truncate(raw))))}),
        64 => try w.print("{d}", .{@as(f64, @bitCast(@as(u64, @truncate(raw))))}),
        80 => try w.print("{d}", .{@as(f80, @bitCast(@as(u80, @truncate(raw))))}),
        else => try w.print("{d}", .{@as(f128, @bitCast(raw))}),
    }
}

fn writeError(v: Value, w: *Writer) Writer.Error!void {
    if (v.errorName()) |name| return w.print("error.{f}", .{std.zig.fmtIdPU(name)});
    try w.writeAll("error.@\"?\"");
}

fn writeItems(v: Value, w: *Writer, depth: usize) Writer.Error!void {
    const n = v.len() catch 0;
    if (n == 0) return w.writeAll(".{}");
    try w.writeAll(".{ ");
    for (0..n) |i| {
        if (i > 0) try w.writeAll(", ");
        if (v.index(i)) |item| try writeValue(item, w, depth + 1) else |_| try w.writeAll("?");
    }
    try w.writeAll(" }");
}

fn writeVector(v: Value, w: *Writer, depth: usize) Writer.Error!void {
    const info = v.type.info.vector;
    if (info.len == 0) return w.writeAll(".{}");
    var buffer: [16]u8 align(16) = undefined;
    try w.writeAll(".{ ");
    for (0..info.len) |i| {
        if (i > 0) try w.writeAll(", ");
        const item: Value = .init(info.child, &buffer);
        if (info.child.size <= buffer.len and v.getElement(i, item) != error.TypeMismatch) {
            try writeValue(item, w, depth + 1);
        } else try w.writeAll("?");
    }
    try w.writeAll(" }");
}

fn writeStruct(v: Value, w: *Writer, depth: usize) Writer.Error!void {
    const s = v.type.info.@"struct";
    var written: usize = 0;
    for (s.fields.slice(), 0..) |f, i| {
        if (f.is_comptime) continue;
        try w.writeAll(if (written == 0) ".{ " else ", ");
        written += 1;
        if (!s.is_tuple) try w.print(".{f} = ", .{std.zig.fmtIdPU(f.name.slice())});
        if (v.fieldAt(i)) |item| try writeValue(item, w, depth + 1) else |_| try w.writeAll("?");
    }
    try w.writeAll(if (written == 0) ".{}" else " }");
}

fn writeUnion(v: Value, w: *Writer, depth: usize) Writer.Error!void {
    const live = v.active() orelse return w.print("<{s}>", .{v.type.name.slice()});
    const inside = v.payload() catch return w.print("<{s}>", .{v.type.name.slice()});
    if (inside.type.kind == .void) return w.print(".{f}", .{std.zig.fmtIdPU(live.name.slice())});
    try w.print(".{{ .{f} = ", .{std.zig.fmtIdPU(live.name.slice())});
    try writeValue(inside, w, depth + 1);
    try w.writeAll(" }");
}
