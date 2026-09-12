// SPDX-License-Identifier: BSL-1.0

//! What every part of the C API shares: the allocator, the status every
//! function returns, and text written into a caller's buffer.

const std = @import("std");
const builtin = @import("builtin");
const Allocator = std.mem.Allocator;

const value_mod = @import("../value.zig");
const Value = value_mod.Value;

pub const abi_version: u32 = 1;

/// What the C side allocates with: registries, values made by
/// `fxr_value_create`, arenas.
pub const allocator: Allocator = if (builtin.single_threaded) std.heap.page_allocator else std.heap.smp_allocator;

pub const Status = enum(c_int) {
    ok = 0,
    type_mismatch,
    no_such_field,
    no_such_member,
    no_such_method,
    no_such_error,
    index_out_of_bounds,
    read_only,
    null,
    not_addressable,
    out_of_range,
    inactive_arm,
    not_callable,
    argument_count,
    argument_type,
    missing_sentinel,
    no_default,
    syntax,
    out_of_memory,
    unsupported,
    name_taken,
    invalid_layout,
    unknown_type,
};

pub fn statusOf(err: anyerror) Status {
    return switch (err) {
        error.TypeMismatch => .type_mismatch,
        error.NoSuchField => .no_such_field,
        error.NoSuchMember => .no_such_member,
        error.NoSuchMethod => .no_such_method,
        error.NoSuchError => .no_such_error,
        error.IndexOutOfBounds => .index_out_of_bounds,
        error.ReadOnly => .read_only,
        error.Null => .null,
        error.NotAddressable => .not_addressable,
        error.OutOfRange => .out_of_range,
        error.InactiveArm => .inactive_arm,
        error.NotCallable => .not_callable,
        error.ArgumentCount => .argument_count,
        error.ArgumentType => .argument_type,
        error.MissingSentinel => .missing_sentinel,
        error.NoDefault => .no_default,
        error.Syntax, error.SyntaxError, error.TooDeep, error.DuplicateKey => .syntax,
        error.WrongType => .type_mismatch,
        error.LengthMismatch => .index_out_of_bounds,
        error.MissingField, error.UnknownField => .no_such_field,
        error.UnknownTag => .no_such_member,
        error.OutOfMemory => .out_of_memory,
        error.NameTaken => .name_taken,
        error.InvalidLayout => .invalid_layout,
        error.UnknownType => .unknown_type,
        else => .unsupported,
    };
}

pub fn done(result: anyerror!void) Status {
    result catch |err| return statusOf(err);
    return .ok;
}

pub fn into(out: *Value, result: value_mod.Error!Value) Status {
    out.* = result catch |err| return statusOf(err);
    return .ok;
}

pub fn span(name: [*:0]const u8) []const u8 {
    return std.mem.span(name);
}

export fn fxr_abi_version() u32 {
    return abi_version;
}

export fn fxr_status_name(status: c_int) [*:0]const u8 {
    const s = std.enums.fromInt(Status, status) orelse return "unknown";
    return @tagName(s);
}

/// Keeps what fits in a caller's buffer, with room for a zero after it, and
/// counts all of it, as `snprintf` does.
pub const Clip = struct {
    buffer: []u8,
    total: usize = 0,
    writer: std.Io.Writer = .{ .buffer = &.{}, .vtable = &.{ .drain = drain } },

    pub fn init(buffer: ?[*]u8, capacity: usize) Clip {
        return .{ .buffer = if (buffer) |b| b[0..capacity] else &.{} };
    }

    fn take(self: *Clip, bytes: []const u8) void {
        if (self.buffer.len > 0 and self.total < self.buffer.len - 1) {
            const room = self.buffer.len - 1 - self.total;
            const n = @min(room, bytes.len);
            @memcpy(self.buffer[self.total..][0..n], bytes[0..n]);
        }
        self.total += bytes.len;
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Clip = @alignCast(@fieldParentPtr("writer", w));
        var n: usize = 0;
        for (data[0 .. data.len - 1]) |bytes| {
            self.take(bytes);
            n += bytes.len;
        }
        const last = data[data.len - 1];
        for (0..splat) |_| self.take(last);
        return n + last.len * splat;
    }

    /// Puts the zero after what was kept, and says how long all of it was.
    pub fn finish(self: *Clip) usize {
        if (self.buffer.len > 0) self.buffer[@min(self.total, self.buffer.len - 1)] = 0;
        return self.total;
    }
};
