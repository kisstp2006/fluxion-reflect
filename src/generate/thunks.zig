// SPDX-License-Identifier: BSL-1.0

//! What run-time code cannot do for itself, because Zig does not fix the
//! layout: where an optional keeps its flag, a tagged union its tag, a slice
//! its length, how a function takes its arguments. Each is a small function
//! made for one type, and called through the C calling convention so a
//! descriptor works the same from C.

const std = @import("std");

const model = @import("../model.zig");
const fill = @import("defaults.zig").fill;

pub fn SliceOps(comptime S: type) type {
    const p = @typeInfo(S).pointer;
    const Many = @TypeOf(@as(S, undefined).ptr);
    const alignment = p.alignment orelse @alignOf(p.child);
    return struct {
        var nothing: (if (p.sentinel()) |s| [0:s]p.child else [0]p.child) align(alignment) = .{};

        fn get(ptr: *const anyopaque, out: *model.RawSlice) callconv(.c) void {
            const slice: *const S = @ptrCast(@alignCast(ptr));
            out.* = .{ .ptr = @ptrCast(@constCast(slice.ptr)), .len = slice.len };
        }

        fn set(ptr: *anyopaque, raw: *const model.RawSlice) callconv(.c) void {
            const slice: *S = @ptrCast(@alignCast(ptr));
            const address = raw.ptr orelse {
                slice.* = &nothing;
                return;
            };
            const many: Many = @ptrCast(@alignCast(address));
            slice.* = if (comptime p.sentinel()) |s| many[0..raw.len :s] else many[0..raw.len];
        }

        pub const ops: model.SliceOps = .{ .get = &get, .set = &set };
    };
}

pub fn VectorOps(comptime V: type) type {
    const v = @typeInfo(V).vector;
    return struct {
        fn get(ptr: *const anyopaque, index: usize, out: *anyopaque) callconv(.c) void {
            const vector: *const V = @ptrCast(@alignCast(ptr));
            const items: [v.len]v.child = vector.*;
            @as(*v.child, @ptrCast(@alignCast(out))).* = items[index];
        }

        fn set(ptr: *anyopaque, index: usize, in: *const anyopaque) callconv(.c) void {
            const vector: *V = @ptrCast(@alignCast(ptr));
            var items: [v.len]v.child = vector.*;
            items[index] = @as(*const v.child, @ptrCast(@alignCast(in))).*;
            vector.* = items;
        }

        pub const ops: model.ElementOps = .{ .get = &get, .set = &set };
    };
}

pub fn UnionOps(comptime U: type) type {
    const u = @typeInfo(U).@"union";
    return struct {
        fn active(ptr: *const anyopaque) callconv(.c) u32 {
            const value: *const U = @ptrCast(@alignCast(ptr));
            const tag = std.meta.activeTag(value.*);
            inline for (u.fields, 0..) |f, i| {
                if (tag == @field(u.tag_type.?, f.name)) return i;
            }
            unreachable;
        }

        fn payload(ptr: *anyopaque, arm: u32) callconv(.c) *anyopaque {
            const value: *U = @ptrCast(@alignCast(ptr));
            switch (arm) {
                inline 0...u.fields.len - 1 => |i| return @ptrCast(&@field(value.*, u.fields[i].name)),
                else => unreachable,
            }
        }

        fn activate(ptr: *anyopaque, arm: u32) callconv(.c) void {
            const value: *U = @ptrCast(@alignCast(ptr));
            switch (arm) {
                inline 0...u.fields.len - 1 => |i| {
                    value.* = @unionInit(U, u.fields[i].name, fill(u.fields[i].type));
                },
                else => unreachable,
            }
        }

        pub const ops: model.UnionOps = .{
            .active = if (u.tag_type != null) &active else null,
            .payload = &payload,
            .activate = &activate,
        };
    };
}

pub fn OptionalOps(comptime O: type) type {
    const Child = @typeInfo(O).optional.child;
    return struct {
        fn payload(ptr: *anyopaque) callconv(.c) ?*anyopaque {
            const value: *O = @ptrCast(@alignCast(ptr));
            if (value.*) |*p| return @ptrCast(p);
            return null;
        }

        fn setNull(ptr: *anyopaque) callconv(.c) void {
            const value: *O = @ptrCast(@alignCast(ptr));
            value.* = null;
        }

        fn setSome(ptr: *anyopaque) callconv(.c) *anyopaque {
            const value: *O = @ptrCast(@alignCast(ptr));
            value.* = fill(Child);
            return @ptrCast(&value.*.?);
        }

        pub const ops: model.OptionalOps = .{ .payload = &payload, .set_null = &setNull, .set_some = &setSome };
    };
}

pub fn ErrorUnionOps(comptime E: type) type {
    const Payload = @typeInfo(E).error_union.payload;
    const Set = @typeInfo(E).error_union.error_set;
    return struct {
        fn payload(ptr: *anyopaque) callconv(.c) ?*anyopaque {
            const value: *E = @ptrCast(@alignCast(ptr));
            if (value.*) |*p| return @ptrCast(p) else |_| return null;
        }

        fn code(ptr: *const anyopaque) callconv(.c) u32 {
            const value: *const E = @ptrCast(@alignCast(ptr));
            if (value.*) |_| return 0 else |err| return @intFromError(err);
        }

        fn setCode(ptr: *anyopaque, number: u32) callconv(.c) void {
            const value: *E = @ptrCast(@alignCast(ptr));
            const any: anyerror = @errorFromInt(@as(std.meta.Int(.unsigned, @bitSizeOf(anyerror)), @intCast(number)));
            value.* = @as(Set, @errorCast(any));
        }

        fn setPayload(ptr: *anyopaque) callconv(.c) *anyopaque {
            const value: *E = @ptrCast(@alignCast(ptr));
            value.* = fill(Payload);
            if (value.*) |*p| return @ptrCast(p) else |_| unreachable;
        }

        pub const ops: model.ErrorUnionOps = .{ .payload = &payload, .code = &code, .set_code = &setCode, .set_payload = &setPayload };
    };
}

/// Calls a `*const F` kept at `function`: each argument is read from where
/// `args` points, and the return value written to `result`.
pub fn Invoker(comptime F: type) type {
    const f = @typeInfo(F).@"fn";
    const R = f.return_type.?;
    return struct {
        pub fn invoke(function: *const anyopaque, args: [*]const *anyopaque, result: ?*anyopaque) callconv(.c) void {
            const pointer: *const *const F = @ptrCast(@alignCast(function));
            var tuple: std.meta.ArgsTuple(F) = undefined;
            inline for (f.params, 0..) |p, i| {
                tuple[i] = @as(*const p.type.?, @ptrCast(@alignCast(args[i]))).*;
            }
            if (R == noreturn) {
                @call(.auto, pointer.*, tuple);
            } else {
                const returned = @call(.auto, pointer.*, tuple);
                if (@sizeOf(R) > 0) {
                    if (result) |r| @as(*R, @ptrCast(@alignCast(r))).* = returned;
                }
            }
        }
    };
}

/// Where a pointer to `function` is kept, for an `Invoker` to be handed.
pub fn Storage(comptime function: anytype) type {
    return struct {
        pub const pointer: *const @TypeOf(function) = &function;
    };
}
