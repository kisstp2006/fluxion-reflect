// SPDX-License-Identifier: BSL-1.0

//! A type written down in `fluxion-data`'s schema grammar, and the number that
//! stands for it.
//!
//! For every type `fluxion-data` writes, the text is the one its
//! `schema.describe` gives and the number the one its `schema.fingerprint`
//! gives, so a file's schema can be checked against a type that was only met
//! at run time - one from C, or from a plugin. Past what that library writes,
//! the grammar goes on in the same spirit: a pointer is `*` and the name of
//! what it points at, which is also what stops a type that points at itself
//! from being written out for ever.

const std = @import("std");
const Writer = std.Io.Writer;
const hashing = @import("fluxion_hash");

const model = @import("model.zig");
const Type = model.Type;

pub fn fingerprint(t: *const Type) u64 {
    var stream: hashing.Stream(hashing.Xx64) = .init(.init());
    describe(t, stream.writer()) catch unreachable;
    return stream.final();
}

pub fn describe(t: *const Type, w: *Writer) Writer.Error!void {
    var open: Open = .{};
    return write(t, w, &open);
}

/// The types being written, outermost first, so that one met again inside
/// itself is written by name.
const Open = struct {
    types: [64]*const Type = undefined,
    len: usize = 0,

    fn has(self: *const Open, t: *const Type) bool {
        for (self.types[0..self.len]) |held| if (held == t) return true;
        return false;
    }
};

fn write(t: *const Type, w: *Writer, open: *Open) Writer.Error!void {
    if (open.has(t) or open.len == open.types.len) return w.writeAll(t.name.slice());
    open.types[open.len] = t;
    open.len += 1;
    defer open.len -= 1;

    switch (t.kind) {
        .void => try w.writeAll("void"),
        .bool => try w.writeAll("bool"),
        .noreturn => try w.writeAll("noreturn"),
        .type => try w.writeAll("type"),
        .int => try w.print("{c}{d}", .{ @as(u8, if (t.info.int.signed) 'i' else 'u'), t.info.int.bits }),
        .float => try w.print("f{d}", .{t.info.float.bits}),
        .@"enum" => {
            const e = t.info.@"enum";
            try w.writeAll("enum(");
            try write(e.tag, w, open);
            try w.writeAll("){");
            for (e.members.slice(), 0..) |m, i| {
                if (i > 0) try w.writeByte(',');
                try w.writeAll(m.name.slice());
            }
            if (!e.is_exhaustive) try w.writeAll(if (e.members.len > 0) ",_" else "_");
            try w.writeByte('}');
        },
        .optional => {
            try w.writeByte('?');
            try write(t.info.optional.child, w, open);
        },
        .array => {
            try w.print("[{d}]", .{t.info.array.len});
            try write(t.info.array.child, w, open);
        },
        .vector => {
            try w.print("@Vector({d},", .{t.info.vector.len});
            try write(t.info.vector.child, w, open);
            try w.writeByte(')');
        },
        .slice => {
            const s = t.info.slice;
            if (s.sentinel) |end| try w.print("[:{d}]", .{sentinelValue(s.child, end)}) else try w.writeAll("[]");
            try write(s.child, w, open);
        },
        .pointer => {
            const p = t.info.pointer;
            try w.writeAll(switch (p.size) {
                .one => "*",
                .many => "[*]",
                .c => "[*c]",
            });
            try w.writeAll(p.child.name.slice());
        },
        .@"struct" => {
            const s = t.info.@"struct";
            if (s.layout == .@"packed" and s.backing != null) {
                try w.writeAll("packed(");
                try write(s.backing.?, w, open);
                try w.writeAll("){");
            } else try w.writeAll("struct{");
            var written: usize = 0;
            for (s.fields.slice()) |f| {
                if (f.is_comptime) continue;
                if (written > 0) try w.writeByte(',');
                written += 1;
                try w.print("{s}:", .{f.name.slice()});
                try write(f.type, w, open);
            }
            try w.writeByte('}');
        },
        .@"union" => {
            const u = t.info.@"union";
            try w.writeAll(if (u.tag != null) "union{" else "untagged union{");
            for (u.arms.slice(), 0..) |f, i| {
                if (i > 0) try w.writeByte(',');
                try w.print("{s}:", .{f.name.slice()});
                try write(f.type, w, open);
            }
            try w.writeByte('}');
        },
        .error_set => {
            const e = t.info.error_set;
            if (e.is_any) return w.writeAll("anyerror");
            try w.writeAll("error{");
            for (e.names.slice(), 0..) |name, i| {
                if (i > 0) try w.writeByte(',');
                try w.writeAll(name.slice());
            }
            try w.writeByte('}');
        },
        .error_union => {
            try write(t.info.error_union.error_set, w, open);
            try w.writeByte('!');
            try write(t.info.error_union.payload, w, open);
        },
        .function => {
            const f = t.info.function;
            try w.writeAll("fn(");
            for (f.params.slice(), 0..) |p, i| {
                if (i > 0) try w.writeByte(',');
                try write(p.type, w, open);
            }
            try w.writeByte(')');
            try write(f.return_type, w, open);
        },
        .@"opaque" => try w.print("opaque({s})", .{t.name.slice()}),
    }
}

fn sentinelValue(child: *const Type, end: *const anyopaque) i129 {
    if (child.kind != .int or child.info.int.bits > 64) return 0;
    const bytes: [*]const u8 = @ptrCast(end);
    var raw: u128 = 0;
    for (0..child.size) |i| raw |= @as(u128, bytes[i]) << @intCast(8 * switch (@import("builtin").cpu.arch.endian()) {
        .little => i,
        .big => child.size - 1 - i,
    });
    return @import("bits.zig").toWide(raw, child.info.int.bits, child.info.int.signed);
}
