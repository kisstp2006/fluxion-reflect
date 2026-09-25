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

test "a method and a free function say the names of their parameters" {
    const machine = typeOf(Machine);

    const load = machine.method("load").?;
    try testing.expect(load.takesSelf(machine));
    try testing.expectEqual(@as(usize, 1), load.paramNames().?.len);
    try testing.expectEqualStrings("fail", load.paramNames().?[0]);
    try testing.expectEqualStrings("Loads the level, or jams", load.attribute(reflect.attr.Doc).?.text);

    // a method listed with no attributes has no names, and a function beside a type no self
    const player = typeOf(Player);
    try testing.expect(player.method("heal").?.paramNames() == null);
    try testing.expect(player.method("heal").?.takesSelf(player));
    try testing.expect(player.method("describe").?.takesSelf(player));
    try testing.expect(!player.method("heal").?.takesSelf(machine));

    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    const scale = try registry.addFunctionWith("scale", test_types.scale, .{
        reflect.attr.Params{ .names = &.{ "factor", "value" } },
        reflect.attr.Doc{ .text = "Multiplies a value" },
    });
    try testing.expectEqual(@as(usize, 2), scale.paramNames().?.len);
    try testing.expectEqualStrings("value", scale.paramNames().?[1]);
    try testing.expect(!scale.takesSelf(player));
    _ = try registry.addFunction("triple", triple);
    try testing.expect(registry.function("triple").?.paramNames() == null);

    // the functions can be listed, in the order they were added
    const list = registry.functionList();
    try testing.expectEqual(@as(usize, 2), list.len);
    try testing.expectEqualStrings("scale", list[0].name.slice());
    try testing.expectEqualStrings("triple", list[1].name.slice());

    // and the function still calls
    var factor: f32 = 3;
    var value: f32 = 4;
    var out: f32 = 0;
    try reflect.call(scale, &.{ .of(&factor), .of(&value) }, .of(&out));
    try testing.expectEqual(@as(f32, 12), out);
}

/// A player of clips: its last parameters have defaults, and its name is
/// written through a method.
const Deck = struct {
    name: [16]u8 = @splat(0),
    speed: f32 = 1,
    restarted: u32 = 0,

    pub const reflect_methods = .{
        .play = .{ reflect.attr.Params{ .names = &.{ "name", "speed", "from_end" } }, reflect.attr.defaults(.{ "", 1.0, false }) },
        .setName = .{reflect.attr.Params{ .names = &.{"name"} }},
    };
    pub const reflect_fields = .{ .name = .{reflect.attr.Setter{ .method = "setName" }} };

    pub fn play(self: *Deck, name: []const u8, speed: f32, from_end: bool) void {
        if (name.len > 0) self.setName(name);
        self.speed = if (from_end) -speed else speed;
    }

    pub fn setName(self: *Deck, name: []const u8) void {
        self.name = @splat(0);
        @memcpy(self.name[0..@min(name.len, 16)], name[0..@min(name.len, 16)]);
        self.restarted += 1;
    }
};

test "a method's defaults are its last parameters', each of the parameter's type, and a field names its setter" {
    const t = typeOf(Deck);
    const play = t.method("play").?;
    const given = play.defaultArgs();
    try testing.expectEqual(@as(usize, 3), given.len);
    try testing.expect(given[0].type.is([]const u8));
    try testing.expectEqualStrings("", @as(*const []const u8, @ptrCast(@alignCast(given[0].value))).*);
    try testing.expect(given[1].type.is(f32));
    try testing.expectEqual(@as(f32, 1.0), @as(*const f32, @ptrCast(@alignCast(given[1].value))).*);
    try testing.expect(!@as(*const bool, @ptrCast(@alignCast(given[2].value))).*);
    // What was written with `attr.defaults` is not an attribute of its own.
    try testing.expectEqualStrings("from_end", play.paramNames().?[2]);
    try testing.expectEqual(@as(usize, 2), play.attributes.len);
    try testing.expectEqual(@as(usize, 0), t.method("setName").?.defaultArgs().len);

    const setter = t.field("name").?.attribute(reflect.attr.Setter).?;
    try testing.expectEqualStrings("setName", setter.method);
}
