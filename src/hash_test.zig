// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;
const hashing = @import("fluxion_hash");

const Value = @import("root.zig").Value;

const test_types = @import("test_types.zig");
const Flags = test_types.Flags;
const Player = test_types.Player;
const Shape = test_types.Shape;

test "hashes agree with fluxion-hash's hashValue" {
    var target: Player = .{ .name = "t" };
    var player: Player = .{ .name = "Ada", .level = 3, .target = &target, .inventory = .{ 9, 8, 7 } };
    try testing.expectEqual(hashing.hashValue(player), Value.of(&player).hash());
    var shape: Shape = .{ .box = .{ .w = 1, .h = 2 } };
    try testing.expectEqual(hashing.hashValue(shape), Value.of(&shape).hash());
    shape = .none;
    try testing.expectEqual(hashing.hashValue(shape), Value.of(&shape).hash());
    var numbers: []const i24 = &.{ -1, 2, 3 };
    try testing.expectEqual(hashing.hashValue(numbers), Value.of(&numbers).hash());
    var maybe: ?u64 = null;
    try testing.expectEqual(hashing.hashValue(maybe), Value.of(&maybe).hash());
    maybe = 12;
    try testing.expectEqual(hashing.hashValue(maybe), Value.of(&maybe).hash());
    var failure: anyerror!u8 = error.Broken;
    try testing.expectEqual(hashing.hashValue(failure), Value.of(&failure).hash());
    failure = 4;
    try testing.expectEqual(hashing.hashValue(failure), Value.of(&failure).hash());
    var flags: Flags = .{ .layer = 5 };
    try testing.expectEqual(hashing.hashValue(flags), Value.of(&flags).hash());
    var float: f80 = -1.25;
    try testing.expectEqual(hashing.hashValue(float), Value.of(&float).hash());
    _ = &numbers;
}

test "equal values are eql and hash alike, different ones are not" {
    var a: Player = .{ .name = "same" };
    var b: Player = .{ .name = "same" };
    const text_copy = try testing.allocator.dupe(u8, "same");
    defer testing.allocator.free(text_copy);
    b.name = text_copy;
    try testing.expect(Value.of(&a).eql(Value.of(&b)));
    try testing.expectEqual(Value.of(&a).hash(), Value.of(&b).hash());
    b.flags.solid = true;
    try testing.expect(!Value.of(&a).eql(Value.of(&b)));
    var n: f32 = std.math.nan(f32);
    var m: f32 = std.math.nan(f32);
    try testing.expect(Value.of(&n).eql(Value.of(&m)));
    var zero: f32 = 0;
    var negative_zero: f32 = -0.0;
    try testing.expect(!Value.of(&zero).eql(Value.of(&negative_zero)));
}
