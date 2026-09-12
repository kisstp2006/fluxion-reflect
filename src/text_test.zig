// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;

const reflect = @import("root.zig");
const Value = reflect.Value;

const test_types = @import("test_types.zig");
const Team = test_types.Team;
const Stats = test_types.Stats;
const Player = test_types.Player;
const Shape = test_types.Shape;

test "Zig syntax out, and back in" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var target: Player = .{};
    var player: Player = .{ .name = "Ada \"the first\"", .level = 7, .stats = .{ .health = 55.5, .armour = 3 }, .team = .green, .inventory = .{ 1, 2, 3 }, .target = &target };
    player.flags.layer = 12;
    const v = Value.of(&player);

    const written = try std.fmt.allocPrint(arena.allocator(), "{f}", .{v});
    try testing.expect(std.mem.indexOf(u8, written, ".name = \"Ada \\\"the first\\\"\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, ".team = .green") != null);
    try testing.expect(std.mem.indexOf(u8, written, ".inventory = .{ 1, 2, 3 }") != null);

    var copy: Player = .{};
    const into = Value.of(&copy);
    try into.parse(".{ .name = \"Ada \\\"the first\\\"\", .level = 7, .stats = .{ .health = 55.5, .armour = 3 }, .team = .green, .inventory = .{ 1, 2, 3 }, .flags = .{ .layer = 12 } }", .{ .allocator = arena.allocator() });
    copy.target = &target;
    try testing.expect(v.eql(into));

    try into.parse(".{ .level = 0x10, .team = blue }", .{});
    try testing.expectEqual(@as(u16, 16), copy.level);
    try testing.expectEqual(Team.blue, copy.team);
    try testing.expectEqualStrings("Ada \"the first\"", copy.name);

    var diagnostics: reflect.Diagnostics = .{};
    try testing.expectError(error.NoSuchField, into.parse(".{ .levle = 3 }", .{ .diagnostics = &diagnostics }));
    try testing.expectEqualStrings("level", diagnostics.suggestion.?);
    try testing.expectError(error.OutOfMemory, into.parse(".{ .name = \"x\" }", .{}));
}

test "slices read from text are allocated" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var numbers: []const i32 = &.{};
    try Value.of(&numbers).parse(".{ 1, -2, 3_000, }", .{ .allocator = arena.allocator() });
    try testing.expectEqualSlices(i32, &.{ 1, -2, 3000 }, numbers);
    var shapes: []Shape = &.{};
    try Value.of(&shapes).parse(".{ .{ .circle = 1 }, .none, .{ .box = .{ .w = 1, .h = 2 } } }", .{ .allocator = arena.allocator() });
    try testing.expectEqual(@as(usize, 3), shapes.len);
    try testing.expectEqual(Shape{ .box = .{ .w = 1, .h = 2 } }, shapes[2]);
    try Value.of(&numbers).parse(".{}", .{});
    try testing.expectEqual(@as(usize, 0), numbers.len);
}

test "the reader takes what Zig's own literals take" {
    const Knobs = struct {
        mask: u32 = 0,
        bits: u8 = 0,
        mode: u16 = 0,
        big: u64 = 0,
        ratio: f64 = 0,
        low: f32 = 0,
        tag: [6:0]u8 = @splat(0),
        pair: struct { i8, bool } = .{ 0, false },
        maybe: ?Stats = null,
    };
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var knobs: Knobs = .{};
    const v = Value.of(&knobs);
    try v.parse(
        \\.{
        \\    // written by hand
        \\    .mask = 0xdead_BEEF,
        \\    .bits = 0b1010_1010,
        \\    .mode = 0o755,
        \\    .big = 18_446_744_073_709_551_615,
        \\    .ratio = -1.5e3,
        \\    .low = -inf,
        \\    .tag = "A\x42\u{263A}",
        \\    .pair = .{ -128, true },
        \\    .maybe = .{ .armour = 9 },
        \\}
    , .{ .allocator = arena.allocator() });
    try testing.expectEqual(@as(u32, 0xdeadbeef), knobs.mask);
    try testing.expectEqual(@as(u8, 0xaa), knobs.bits);
    try testing.expectEqual(@as(u16, 0o755), knobs.mode);
    try testing.expectEqual(@as(u64, std.math.maxInt(u64)), knobs.big);
    try testing.expectEqual(@as(f64, -1500), knobs.ratio);
    try testing.expect(std.math.isNegativeInf(knobs.low));
    try testing.expectEqualStrings("AB\u{263A}", std.mem.sliceTo(&knobs.tag, 0));
    try testing.expectEqual(@as(i8, -128), knobs.pair[0]);
    try testing.expect(knobs.pair[1]);
    try testing.expectEqual(@as(u8, 9), knobs.maybe.?.armour);
    try testing.expectEqual(@as(f32, 100), knobs.maybe.?.health);

    try v.parse(".{ .ratio = nan, .maybe = null }", .{});
    try testing.expect(std.math.isNan(knobs.ratio));
    try testing.expect(knobs.maybe == null);

    var diagnostics: reflect.Diagnostics = .{};
    try testing.expectError(error.OutOfRange, v.parse(".{ .bits = 256 }", .{ .diagnostics = &diagnostics }));
    try testing.expectEqual(@as(usize, 11), diagnostics.offset);
    try testing.expectError(error.Syntax, v.parse(".{ .bits = 1", .{}));
    try testing.expectError(error.Syntax, v.parse(".{ .bits = 1 } extra", .{}));
    try testing.expectError(error.IndexOutOfBounds, v.parse(".{ .pair = .{ 1, true, 3 } }", .{}));
    try testing.expectError(error.OutOfRange, v.parse(".{ .tag = \"toolong\" }", .{}));
    try testing.expectError(error.Syntax, v.parse(".{ .tag = \"\\q\" }", .{}));
}
