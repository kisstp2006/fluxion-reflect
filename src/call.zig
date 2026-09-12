// SPDX-License-Identifier: BSL-1.0

//! Calling a function through its descriptor, with values as arguments.
//!
//! An argument is passed as it is when it is of the parameter's type. When
//! the parameter is a pointer to that type it is passed by address, which is
//! what makes `value.call("heal", ...)` work on a method taking `self: *T`.
//! Numbers, bools and enums are converted to the parameter's kind, and text
//! is handed to a `[]const u8` parameter.

const std = @import("std");

const model = @import("model.zig");
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const Error = value_mod.Error;
const Type = model.Type;

/// The most arguments one call takes.
pub const max_args = 16;

const Slot = struct {
    bytes: [16]u8 align(16),
    pointer: *anyopaque,
};

pub fn call(method: *const model.Method, args: []const Value, result: ?Value) Error!void {
    const run = method.invoke orelse return error.NotCallable;
    return callWith(run, method.function, method.type, args, result);
}

pub fn callMethod(receiver: Value, name: []const u8, args: []const Value, result: ?Value) Error!void {
    const self = if (receiver.type.kind == .pointer and receiver.type.info.pointer.size == .one) try receiver.deref() else receiver;
    const method = self.type.method(name) orelse return error.NoSuchMethod;
    if (args.len + 1 > max_args) return error.ArgumentCount;
    var all: [max_args]Value = undefined;
    all[0] = self;
    @memcpy(all[1..][0..args.len], args);
    return call(method, all[0 .. args.len + 1], result);
}

pub fn callPointer(pointer: Value, args: []const Value, result: ?Value) Error!void {
    const t = pointer.type;
    if (t.kind != .pointer or t.info.pointer.child.kind != .function) return error.NotCallable;
    const function = t.info.pointer.child;
    const run = function.info.function.invoke orelse return error.NotCallable;
    const address = pointer.address();
    if (address == 0) return error.Null;
    return callWith(run, @ptrCast(&address), function, args, result);
}

fn callWith(run: *const model.Invoke, function: *const anyopaque, fn_type: *const Type, args: []const Value, result: ?Value) Error!void {
    const f = fn_type.info.function;
    const params = f.params.slice();
    if (args.len != params.len or params.len > max_args) return error.ArgumentCount;

    var slots: [max_args]Slot = undefined;
    var pointers: [max_args]*anyopaque = undefined;
    for (params, args, 0..) |p, arg, i| pointers[i] = try adapt(p.type, arg, &slots[i]);

    const returns = f.return_type;
    var returned: Slot = undefined;
    var out: ?*anyopaque = null;
    var convert = false;
    if (result) |into| {
        if (into.type.same(returns) and !into.is_bit_field) {
            if (into.is_const) return error.ReadOnly;
            out = into.ptr;
        } else if (isScalar(returns) and returns.size <= returned.bytes.len and isScalar(into.type)) {
            out = &returned.bytes;
            convert = true;
        } else return error.TypeMismatch;
    }

    run(function, &pointers, out);
    if (convert) try result.?.convertFrom(.initConst(returns, &returned.bytes));
}

fn adapt(want: *const Type, arg: Value, slot: *Slot) Error!*anyopaque {
    if (want.same(arg.type)) {
        if (!arg.is_bit_field) return arg.ptr;
        if (want.size > slot.bytes.len) return error.NotAddressable;
        Value.init(want, &slot.bytes).storeRaw(arg.raw());
        return &slot.bytes;
    }
    if (want.kind == .pointer and want.info.pointer.size != .many and want.info.pointer.child.same(arg.type)) {
        if (arg.is_bit_field) return error.NotAddressable;
        if (arg.is_const and !want.info.pointer.is_const) return error.ReadOnly;
        slot.pointer = arg.ptr;
        return @ptrCast(&slot.pointer);
    }
    if (arg.type.kind == .pointer and arg.type.info.pointer.size == .one and arg.type.info.pointer.child.same(want)) {
        return adapt(want, try arg.deref(), slot);
    }
    if (isScalar(want) and isScalar(arg.type) and want.size <= slot.bytes.len) {
        try Value.init(want, &slot.bytes).convertFrom(arg);
        return &slot.bytes;
    }
    if (want.kind == .slice and want.isString() and want.info.slice.is_const and want.info.slice.sentinel == null) {
        if (arg.toString()) |bytes| {
            try Value.init(want, &slot.bytes).setSliceRaw(@ptrCast(@constCast(bytes.ptr)), bytes.len);
            return &slot.bytes;
        }
    }
    return error.ArgumentType;
}

fn isScalar(t: *const Type) bool {
    return switch (t.kind) {
        .int => t.info.int.bits <= 128,
        .float, .bool, .@"enum" => true,
        else => false,
    };
}
