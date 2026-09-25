// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;

const reflect = @import("root.zig");
const typeOf = reflect.typeOf;
const Value = reflect.Value;

const test_types = @import("test_types.zig");
const Team = test_types.Team;
const Stats = test_types.Stats;
const Player = test_types.Player;
const Shape = test_types.Shape;
const Node = test_types.Node;
const Signed = test_types.Signed;

test "a value that owns memory lets go of it as it is destroyed" {
    const Holder = struct {
        words: []u8 = &.{},

        pub const reflect_drop = release;

        fn release(self: *@This(), gpa: std.mem.Allocator) void {
            gpa.free(self.words);
            self.words = &.{};
        }
    };
    try testing.expect(typeOf(Holder).drop != null);
    try testing.expect(typeOf(Player).drop == null);

    const held = try testing.allocator.create(Holder);
    held.* = .{ .words = try testing.allocator.dupe(u8, "kept until the end") };
    // The testing allocator says so if the words are left behind.
    Value.of(held).destroy(testing.allocator);

    // One made from the default holds nothing, and lets go of nothing.
    const fresh = try Value.create(testing.allocator, typeOf(Holder));
    fresh.destroy(testing.allocator);
}

test "a new value starts from the declared defaults" {
    const v = try Value.create(testing.allocator, typeOf(Player));
    defer v.destroy(testing.allocator);
    const player = v.as(Player).?;
    try testing.expectEqualStrings("anon", player.name);
    try testing.expectEqual(@as(u16, 1), player.level);
    try testing.expectEqual(@as(f32, 100), player.stats.health);
    try testing.expectEqual(Team.red, player.team);
    try testing.expect(player.target == null);
    try testing.expectEqual(@as(u4, 3), player.flags.layer);
    try testing.expect(player.flags.visible);
    try testing.expectError(error.NoDefault, Value.create(testing.allocator, typeOf(*Player)));
}

test "fields are read and written by name" {
    var player: Player = .{};
    const v = Value.of(&player);
    try (try v.field("level")).setInt(42);
    try (try v.path("stats.health")).setFloat(12.5);
    try (try v.field("team")).setString("blue");
    try (try v.path("inventory[1]")).setInt(7);
    try testing.expectEqual(@as(u16, 42), player.level);
    try testing.expectEqual(@as(f32, 12.5), player.stats.health);
    try testing.expectEqual(Team.blue, player.team);
    try testing.expectEqual(@as(u8, 7), player.inventory[1]);

    try testing.expectEqual(@as(?u16, 42), (try v.field("level")).toInt(u16));
    try testing.expectEqual(@as(?f64, 12.5), (try v.path("stats.health")).toFloat(f64));
    try testing.expectEqualStrings("blue", (try v.field("team")).toString().?);
    try testing.expectEqualStrings("anon", (try v.field("name")).toString().?);

    try testing.expectError(error.OutOfRange, (try v.field("level")).setInt(70000));
    try testing.expectError(error.OutOfRange, (try v.field("level")).setFloat(1.5));
    try testing.expectError(error.NoSuchMember, (try v.field("team")).setString("purple"));
    try testing.expectError(error.NoSuchField, v.field("levle"));
    try testing.expectError(error.IndexOutOfBounds, v.path("inventory[3]"));
    try testing.expectError(error.TypeMismatch, (try v.field("level")).set(f32, 1));

    const frozen: Player = .{};
    const read_only = Value.of(&frozen);
    try testing.expectError(error.ReadOnly, (try read_only.field("level")).setInt(2));
    try testing.expectEqual(@as(?u16, 1), (try read_only.field("level")).get(u16));
}

test "packed fields are bits, read and written in place" {
    var player: Player = .{};
    const flags = try Value.of(&player).field("flags");
    const layer = try flags.field("layer");
    try testing.expect(layer.is_bit_field);
    try testing.expectEqual(@as(?u8, 3), layer.toInt(u8));
    try layer.setInt(9);
    try (try flags.field("solid")).setBool(true);
    try testing.expectEqual(@as(u4, 9), player.flags.layer);
    try testing.expect(player.flags.solid);
    try testing.expect(player.flags.visible);
    try testing.expectEqual(@as(u2, 0), player.flags.spare);
    try testing.expectError(error.OutOfRange, layer.setInt(16));
    try testing.expectEqual(@as(?u4, 9), layer.get(u4));
    try testing.expect(layer.as(u4) == null);
}

test "optionals, pointers and paths through them" {
    var target: Player = .{ .name = "Grace", .level = 9 };
    var player: Player = .{ .target = &target };
    const v = Value.of(&player);
    try testing.expectEqualStrings("Grace", (try v.path("target.?.name")).toString().?);
    try testing.expectEqual(@as(?u16, 9), (try v.path("target.?.level")).toInt(u16));
    try (try v.path("target.?.*.level")).setInt(10);
    try testing.expectEqual(@as(u16, 10), target.level);

    try (try v.field("target")).setNull();
    try testing.expect(player.target == null);
    try testing.expect((try v.field("target")).isNull());
    try testing.expectError(error.Null, v.path("target.?.name"));
    try testing.expectError(error.Syntax, v.path("target..name"));

    var first: Node = .{ .value = 1 };
    var second: Node = .{ .value = 2, .next = &first };
    const node = Value.of(&second);
    try testing.expectEqual(@as(?i32, 1), (try node.path("next.?.value")).toInt(i32));
}

test "what a const pointer points at is read-only, and a short list is refused" {
    const Watcher = struct {
        watched: *const Stats,
        mine: *Stats,
        slots: [3]u8 = .{ 0, 0, 0 },
    };
    const theirs: Stats = .{};
    var ours: Stats = .{};
    var watcher: Watcher = .{ .watched = &theirs, .mine = &ours };
    const v = Value.of(&watcher);
    try testing.expectError(error.ReadOnly, (try v.path("watched.armour")).setInt(3));
    try testing.expectError(error.ReadOnly, (try v.path("watched.*")).copyFrom(.of(&ours)));
    try (try v.path("mine.armour")).setInt(3);
    try testing.expectEqual(@as(u8, 3), ours.armour);
    try testing.expectError(error.IndexOutOfBounds, v.parse(".{ .slots = .{ 1, 2 } }", .{}));
    try testing.expectError(error.IndexOutOfBounds, v.parse(".{ .slots = .{} }", .{}));
    try v.parse(".{ .slots = .{ 1, 2, 3 } }", .{});
    try testing.expectEqualSlices(u8, &.{ 1, 2, 3 }, &watcher.slots);
}

test "a failed path is explained, with the name that was probably meant" {
    var player: Player = .{};
    const v = Value.of(&player);
    var buffer: [256]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    try reflect.explainPath(v, "stats.helth", &w);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "no field helth - did you mean health?") != null);
    w = .fixed(&buffer);
    try reflect.explainPath(v, "inventory[5]", &w);
    try testing.expect(std.mem.indexOf(u8, w.buffered(), "has 3 items and no [5]") != null);
}

test "a tagged union's live arm, and making another one live" {
    var shape: Shape = .{ .box = .{ .w = 2, .h = 3 } };
    const v = Value.of(&shape);
    try testing.expectEqualStrings("box", v.active().?.name.slice());
    try testing.expectEqual(@as(?f32, 3), (try v.path("box.h")).toFloat(f32));
    try testing.expectError(error.InactiveArm, v.field("circle"));

    const circle = try v.activate("circle");
    try circle.setFloat(4.5);
    try testing.expectEqual(Shape{ .circle = 4.5 }, shape);
    _ = try v.activate("none");
    try testing.expect(shape == .none);
}

test "numbers convert between kinds where nothing is lost" {
    var x: u8 = 200;
    var y: f32 = 0;
    var z: i64 = -5;
    try testing.expectEqual(@as(?i16, 200), Value.of(&x).toInt(i16));
    try testing.expectEqual(@as(?i8, null), Value.of(&x).toInt(i8));
    try Value.of(&y).convertFrom(Value.of(&x));
    try testing.expectEqual(@as(f32, 200), y);
    try Value.of(&z).convertFrom(Value.of(&y));
    try testing.expectEqual(@as(i64, 200), z);
    y = 2.5;
    try testing.expectError(error.OutOfRange, Value.of(&z).convertFrom(Value.of(&y)));
    try testing.expectEqual(@as(?i64, 2), Value.of(&(@as(f64, 2.0))).toInt(i64));
}

test "signed enums, by name and by number" {
    var level: Signed = .zero;
    const v = Value.of(&level);
    try testing.expectEqual(@as(u64, @bitCast(@as(i64, -2))), typeOf(Signed).member("low").?.value);
    try v.setString(".low");
    try testing.expectEqual(Signed.low, level);
    try testing.expectEqual(@as(?i8, -2), v.toInt(i8));
    try testing.expectEqualStrings("low", v.toString().?);
    try v.setInt(5);
    try testing.expectEqual(Signed.high, level);
    try testing.expectError(error.NoSuchMember, v.setInt(3));
    try testing.expectError(error.OutOfRange, v.setInt(-200));
    try v.parse("@enumFromInt(-2)", .{});
    try testing.expectEqual(Signed.low, level);
    var buffer: [32]u8 = undefined;
    try testing.expectEqualStrings(".low", try std.fmt.bufPrint(&buffer, "{f}", .{v}));
}

test "error unions and error sets by name" {
    const Failure = error{ Broken, Lost };
    var result: Failure!u8 = 3;
    const v = Value.of(&result);
    try testing.expectEqual(@as(?u8, 3), v.unwrap().?.toInt(u8));
    try v.setError("Lost");
    try testing.expectError(error.Lost, result);
    try testing.expectEqualStrings("Lost", v.errorName().?);
    try testing.expectError(error.NoSuchError, v.setError("Found"));
    try v.setError("error.Broken");
    try testing.expectError(error.Broken, result);
    const payload = try v.unwrapOrInit();
    try payload.setInt(9);
    try testing.expectEqual(@as(u8, 9), try result);
    var buffer: [32]u8 = undefined;
    result = error.Broken;
    try testing.expectEqualStrings("error.Broken", try std.fmt.bufPrint(&buffer, "{f}", .{v}));
    try v.parse("error.Lost", .{});
    try testing.expectError(error.Lost, result);
    try v.parse("5", .{});
    try testing.expectEqual(@as(u8, 5), try result);
}

test "vectors, addressable or not" {
    var floats: @Vector(4, f32) = .{ 1, 2, 3, 4 };
    const v = Value.of(&floats);
    try testing.expectEqual(@as(?f32, 3), (try v.index(2)).toFloat(f32));
    try (try v.index(1)).setFloat(9);
    try testing.expectEqual(@as(f32, 9), floats[1]);

    var flags: @Vector(8, bool) = @splat(false);
    const b = Value.of(&flags);
    try testing.expectError(error.NotAddressable, b.index(0));
    var item = true;
    try b.setElement(5, Value.of(&item));
    try testing.expect(flags[5]);
    try b.parse(".{ true, false, true, false, false, false, false, true }", .{});
    try testing.expect(flags[0] and flags[2] and flags[7] and !flags[5]);
    var buffer: [64]u8 = undefined;
    try testing.expectEqualStrings(".{ 1, 9, 3, 4 }", try std.fmt.bufPrint(&buffer, "{f}", .{v}));
}
