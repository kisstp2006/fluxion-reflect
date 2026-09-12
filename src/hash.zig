// SPDX-License-Identifier: BSL-1.0

//! Equality and hashing for a value of any type, walking its descriptor the
//! way `fluxion-hash`'s `updateValue` walks a Zig type: integers little-endian
//! at their declared width, a tag byte for an optional, the length before a
//! slice's items, what a single pointer points at. So a value hashes to the
//! same number reached through reflection or not.
//!
//! Where `updateValue` refuses at compile time - a many-item pointer, a
//! function pointer, an untagged union - this hashes the address or the bytes
//! instead, since there is no compile time left to refuse at. Comptime fields
//! go in as the values they are kept as here (`i64` for a number), which is
//! the one place the two can differ.

const std = @import("std");
const hashing = @import("fluxion_hash");

const model = @import("model.zig");
const value_mod = @import("value.zig");
const bits = @import("bits.zig");
const Value = value_mod.Value;
const Type = model.Type;

/// Past this many pointers followed, a cycle is assumed and the rest is
/// left out of the hash, and compared by address.
const max_depth = 256;

pub fn hash(v: Value) u64 {
    var hasher: hashing.Xx64 = .init();
    feed(&hasher, v, 0);
    return hasher.final();
}

fn int(h: *hashing.Xx64, raw: u128, bit_count: u32) void {
    if (bit_count == 0) return;
    var buffer: [16]u8 = undefined;
    std.mem.writeInt(u128, &buffer, raw & bits.mask(bit_count), .little);
    h.update(buffer[0 .. std.mem.alignForward(u32, @min(bit_count, 128), 8) / 8]);
}

fn feed(h: *hashing.Xx64, v: Value, depth: usize) void {
    if (depth > max_depth) return;
    const t = v.type;
    switch (t.kind) {
        .void, .noreturn => {},
        .bool => int(h, v.raw() & 1, 1),
        .int => if (t.info.int.bits <= 128) int(h, v.raw(), t.info.int.bits) else wide(h, v),
        .float => int(h, v.raw(), t.info.float.bits),
        .@"enum" => int(h, v.raw(), t.info.@"enum".tag.info.int.bits),
        .error_set => int(h, v.raw(), @bitSizeOf(anyerror)),
        .type => int(h, if (v.asType()) |named| named.id else 0, 64),
        .optional => if (v.unwrap()) |inside| {
            int(h, 1, 1);
            feed(h, inside, depth + 1);
        } else int(h, 0, 1),
        .error_union => if (v.unwrap()) |inside| {
            int(h, 1, 1);
            feed(h, inside, depth + 1);
        } else {
            int(h, 0, 1);
            int(h, t.info.error_union.ops.code(v.ptr), @bitSizeOf(anyerror));
        },
        .array => for (0..t.info.array.len) |i| feed(h, v.index(i) catch return, depth),
        .vector => {
            const info = t.info.vector;
            var buffer: [16]u8 align(16) = undefined;
            if (info.child.size > buffer.len) return;
            for (0..info.len) |i| {
                const item: Value = .init(info.child, &buffer);
                v.getElement(i, item) catch return;
                feed(h, item, depth);
            }
        },
        .@"struct" => {
            const s = t.info.@"struct";
            if (s.layout == .@"packed") return int(h, v.raw(), t.bit_size);
            for (0..s.fields.len) |i| feed(h, v.fieldAt(i) catch continue, depth);
        },
        .@"union" => {
            const i = v.activeIndex() orelse return h.update(bytesOf(v));
            const tag = t.info.@"union".tag.?;
            int(h, tag.members()[i].value, tag.info.@"enum".tag.info.int.bits);
            feed(h, v.payload() catch return, depth);
        },
        .pointer => {
            const p = t.info.pointer;
            if (p.size == .one and p.child.kind != .function and p.child.kind != .@"opaque") {
                if (v.deref()) |target| return feed(h, target, depth + 1) else |_| {}
            }
            int(h, v.address(), @bitSizeOf(usize));
        },
        .slice => {
            const items = v.sliceRaw();
            int(h, items.len, @bitSizeOf(usize));
            const child = t.info.slice.child;
            if (child.kind == .int and child.size == 1 and child.bit_size == 8) {
                if (items.len > 0) h.update(@as([*]const u8, @ptrCast(items.ptr.?))[0..items.len]);
                return;
            }
            for (0..items.len) |i| feed(h, v.index(i) catch return, depth);
        },
        .function, .@"opaque" => int(h, @intFromPtr(v.ptr), @bitSizeOf(usize)),
    }
}

fn wide(h: *hashing.Xx64, v: Value) void {
    const width = std.mem.alignForward(usize, v.type.bit_size, 8) / 8;
    const memory = bytesOf(v);
    switch (@import("builtin").cpu.arch.endian()) {
        .little => h.update(memory[0..width]),
        .big => {
            var i = memory.len;
            while (i > memory.len - width) {
                i -= 1;
                h.update(memory[i..][0..1]);
            }
        },
    }
}

fn bytesOf(v: Value) []const u8 {
    return @as([*]const u8, @ptrCast(v.ptr))[0..v.type.size];
}

pub fn eql(a: Value, b: Value) bool {
    return same(a, b, 0);
}

fn same(a: Value, b: Value, depth: usize) bool {
    if (!a.type.same(b.type)) return false;
    if (depth > max_depth) return a.ptr == b.ptr;
    const t = a.type;
    switch (t.kind) {
        .void, .noreturn => return true,
        .bool, .float, .@"enum", .error_set => return a.raw() == b.raw(),
        .int => {
            if (t.info.int.bits <= 128) return a.raw() == b.raw();
            return std.mem.eql(u8, bytesOf(a), bytesOf(b));
        },
        .type => return a.address() == b.address(),
        .optional, .error_union => {
            const x = a.unwrap();
            const y = b.unwrap();
            if (x != null and y != null) return same(x.?, y.?, depth + 1);
            if (x != null or y != null) return false;
            if (t.kind == .optional) return true;
            return t.info.error_union.ops.code(a.ptr) == t.info.error_union.ops.code(b.ptr);
        },
        .array, .slice => {
            const n = a.len() catch return false;
            if (n != (b.len() catch return false)) return false;
            for (0..n) |i| {
                const x = a.index(i) catch return false;
                const y = b.index(i) catch return false;
                if (!same(x, y, depth)) return false;
            }
            return true;
        },
        .vector => {
            const info = t.info.vector;
            var x_buffer: [16]u8 align(16) = undefined;
            var y_buffer: [16]u8 align(16) = undefined;
            if (info.child.size > x_buffer.len) return std.mem.eql(u8, bytesOf(a), bytesOf(b));
            for (0..info.len) |i| {
                const x: Value = .init(info.child, &x_buffer);
                const y: Value = .init(info.child, &y_buffer);
                a.getElement(i, x) catch return false;
                b.getElement(i, y) catch return false;
                if (!same(x, y, depth)) return false;
            }
            return true;
        },
        .@"struct" => {
            const s = t.info.@"struct";
            if (s.layout == .@"packed") return a.raw() == b.raw();
            for (s.fields.slice(), 0..) |f, i| {
                if (f.is_comptime) continue;
                const x = a.fieldAt(i) catch return false;
                const y = b.fieldAt(i) catch return false;
                if (!same(x, y, depth)) return false;
            }
            return true;
        },
        .@"union" => {
            const i = a.activeIndex() orelse {
                if (a.is_bit_field or b.is_bit_field) return a.raw() == b.raw();
                return std.mem.eql(u8, bytesOf(a), bytesOf(b));
            };
            if (b.activeIndex() != i) return false;
            return same(a.payload() catch return false, b.payload() catch return false, depth);
        },
        .pointer => {
            if (a.address() == b.address()) return true;
            const p = t.info.pointer;
            if (p.size != .one or p.child.kind == .function or p.child.kind == .@"opaque") return false;
            return same(a.deref() catch return false, b.deref() catch return false, depth + 1);
        },
        .function, .@"opaque" => return a.ptr == b.ptr,
    }
}
