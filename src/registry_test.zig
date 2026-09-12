// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;

const reflect = @import("root.zig");
const typeOf = reflect.typeOf;
const Value = reflect.Value;

const test_types = @import("test_types.zig");
const Stats = test_types.Stats;
const Player = test_types.Player;
const Node = test_types.Node;

test "a registry finds types by name and builds the ones Zig would write" {
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    const player = try registry.add(Player);
    _ = try registry.add(Node);
    _ = try registry.add(Player);
    try testing.expect(registry.find(@typeName(Player)) == player);
    try testing.expect(registry.findId(player.id) == player);
    try testing.expect(registry.find("f32") == typeOf(f32));
    try testing.expect(registry.find("uint16_t") == typeOf(u16));
    try testing.expect(registry.find("Player") == null);

    try testing.expect(try registry.resolve("[]const u8") == typeOf([]const u8));
    const vec = try registry.resolve("[4]f32");
    try testing.expect(vec.same(typeOf([4]f32)));
    try testing.expectEqual(typeOf([4]f32).size, vec.size);
    const list = try registry.resolve("[]const " ++ @typeName(Player));
    try testing.expect(list.same(typeOf([]const Player)));
    try testing.expect(try registry.resolve("[]const " ++ @typeName(Player)) == list);
    const maybe = try registry.resolve("?*" ++ @typeName(Node));
    try testing.expect(maybe.same(typeOf(?*Node)));
    try testing.expectError(error.Unsupported, registry.resolve("?u8"));
    try testing.expectError(error.UnknownType, registry.resolve("[]Nothing"));

    try testing.expectEqualStrings(@typeName(Player), registry.suggest(@typeName(Player)[0 .. @typeName(Player).len - 1]).?);
}

test "a runtime-made slice type works on real slices" {
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    const list = try registry.resolve("[]const i16");
    try testing.expect(list == typeOf([]const i16) or list.same(typeOf([]const i16)));
    _ = try registry.add(Stats);
    const made = try registry.resolve("[]const " ++ @typeName(Stats));
    const items = [_]Stats{ .{ .health = 1 }, .{ .health = 2 } };
    var slice: []const Stats = &items;
    const v: Value = .init(made, @ptrCast(&slice));
    try testing.expectEqual(@as(usize, 2), try v.len());
    try testing.expectEqual(@as(?f32, 2), (try v.path("[1].health")).toFloat(f32));
}

test "a struct described from C" {
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    const Vec2 = extern struct { x: f32, y: f32 };
    const Enemy = extern struct { id: c_int, at: Vec2, hp: u8 };
    const vec2 = try registry.defineStruct(.{ .name = "Vec2", .size = @sizeOf(Vec2), .alignment = @alignOf(Vec2), .fields = &.{
        .{ .name = "x", .type = registry.find("float").?, .offset = @offsetOf(Vec2, "x") },
        .{ .name = "y", .type = registry.find("float").?, .offset = @offsetOf(Vec2, "y") },
    } });
    const enemy = try registry.defineStruct(.{ .name = "Enemy", .size = @sizeOf(Enemy), .alignment = @alignOf(Enemy), .fields = &.{
        .{ .name = "id", .type = registry.find("int").?, .offset = @offsetOf(Enemy, "id") },
        .{ .name = "at", .type = vec2, .offset = @offsetOf(Enemy, "at") },
        .{ .name = "hp", .type = try registry.resolve("uint8_t"), .offset = @offsetOf(Enemy, "hp") },
    } });
    try testing.expect(registry.find("Enemy") == enemy);

    var e: Enemy = .{ .id = 3, .at = .{ .x = 1, .y = 2 }, .hp = 50 };
    const v: Value = .init(enemy, &e);
    try (try v.path("at.y")).setFloat(8);
    try testing.expectEqual(@as(f32, 8), e.at.y);
    var buffer: [128]u8 = undefined;
    try testing.expectEqualStrings(".{ .id = 3, .at = .{ .x = 1, .y = 8 }, .hp = 50 }", try std.fmt.bufPrint(&buffer, "{f}", .{v}));

    const fresh = try Value.create(testing.allocator, enemy);
    defer fresh.destroy(testing.allocator);
    try testing.expectEqual(@as(?i64, 0), (try fresh.field("hp")).toInt(i64));

    try testing.expectError(error.InvalidLayout, registry.defineStruct(.{ .name = "Bad", .size = 4, .alignment = 4, .fields = &.{
        .{ .name = "x", .type = typeOf(f64), .offset = 0 },
    } }));
    try testing.expectError(error.NameTaken, registry.defineStruct(.{ .name = "Vec2", .size = 8, .alignment = 4, .fields = &.{} }));
}
