// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;

const reflect = @import("root.zig");
const typeOf = reflect.typeOf;
const Value = reflect.Value;

const test_types = @import("test_types.zig");
const Player = test_types.Player;
const Machine = test_types.Machine;
const triple = test_types.triple;

test "methods called with values" {
    var player: Player = .{};
    const v = Value.of(&player);
    var amount: f32 = 5;
    var result: f32 = 0;
    try v.call("heal", &.{Value.of(&amount)}, Value.of(&result));
    try testing.expectEqual(@as(f32, 105), result);
    try testing.expectEqual(@as(f32, 105), player.stats.health);

    var whole: i64 = 10;
    var as_double: f64 = 0;
    try v.call("heal", &.{Value.of(&whole)}, Value.of(&as_double));
    try testing.expectEqual(@as(f64, 115), as_double);

    const name: []const u8 = "Linus";
    try v.call("rename", &.{Value.of(&name)}, null);
    try testing.expectEqualStrings("Linus", player.name);

    var tens: u16 = 0;
    player.level = 4;
    try v.call("describe", &.{}, Value.of(&tens));
    try testing.expectEqual(@as(u16, 40), tens);

    try testing.expectError(error.NoSuchMethod, v.call("hurt", &.{}, null));
    try testing.expectError(error.ArgumentCount, v.call("heal", &.{}, null));
    const frozen: Player = .{};
    try testing.expectError(error.ReadOnly, Value.of(&frozen).call("heal", &.{Value.of(&amount)}, null));
    try testing.expectEqual(@as(usize, 3), typeOf(Player).methods.len);
}

test "a function pointer in a field is called through its type" {
    var machine: Machine = .{};
    const v = Value.of(&machine);
    var x: i32 = 21;
    var out: i32 = 0;
    try (try v.field("on_hit")).callPointer(&.{.of(&x)}, .of(&out));
    try testing.expectEqual(@as(i32, 42), out);
    try testing.expectError(error.NotCallable, (try v.field("level")).callPointer(&.{}, null));
    machine.maybe_hit = triple;
    const inside = (try v.field("maybe_hit")).unwrap().?;
    try inside.callPointer(&.{.of(&x)}, .of(&out));
    try testing.expectEqual(@as(i32, 63), out);
}

test "a registered function, and a method that returns an error" {
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    const f = try registry.addFunction("triple", triple);
    try testing.expectError(error.NameTaken, registry.addFunction("triple", triple));
    var x: u8 = 4;
    var out: i64 = 0;
    try reflect.call(f, &.{.of(&x)}, .of(&out));
    try testing.expectEqual(@as(i64, 12), out);
    try testing.expect(registry.function("triple") == f);

    var machine: Machine = .{ .level = .high };
    const v = Value.of(&machine);
    var fail = true;
    var result: error{Jammed}!u8 = 0;
    try v.call("load", &.{.of(&fail)}, .of(&result));
    try testing.expectEqualStrings("Jammed", Value.of(&result).errorName().?);
    fail = false;
    try v.call("load", &.{.of(&fail)}, .of(&result));
    try testing.expectEqual(@as(u8, 15), try result);
    var fallback: u8 = 1;
    var plain: u8 = 0;
    try v.call("loadOr", &.{.of(&fallback)}, .of(&plain));
    try testing.expectEqual(@as(u8, 15), plain);
}
