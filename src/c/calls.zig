// SPDX-License-Identifier: BSL-1.0

//! `include/fluxion_reflect/calls.h`: calls with values as arguments.

const model = @import("../model.zig");
const call_mod = @import("../call.zig");
const base = @import("base.zig");
const Value = @import("../value.zig").Value;
const Status = base.Status;
const done = base.done;

fn list(args: ?[*]const Value, count: usize) []const Value {
    return if (args) |a| a[0..count] else &.{};
}

fn wanted(result: ?*const Value) ?Value {
    return if (result) |r| r.* else null;
}

export fn fxr_method_call(method: *const model.Method, args: ?[*]const Value, count: usize, result: ?*const Value) Status {
    return done(call_mod.call(method, list(args, count), wanted(result)));
}

export fn fxr_value_call(v: *const Value, name: [*:0]const u8, args: ?[*]const Value, count: usize, result: ?*const Value) Status {
    return done(v.call(base.span(name), list(args, count), wanted(result)));
}

export fn fxr_value_call_pointer(v: *const Value, args: ?[*]const Value, count: usize, result: ?*const Value) Status {
    return done(v.callPointer(list(args, count), wanted(result)));
}
