// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;
const data = @import("fluxion_data");
const reflect = @import("fluxion_reflect");

const Colour = enum(u8) { red, green, blue };
const Point = struct { x: f32, y: f32 };
const Shape = union(enum) { circle: f32, box: Point, nothing: bool };
const Flags = packed struct(u8) { visible: bool, solid: bool, rest: u6 };

const Player = struct {
    name: []const u8,
    level: u16,
    at: Point,
    tint: Colour,
    carrying: ?u32,
    scores: [3]i16,
    shape: Shape,
    flags: Flags,
    history: []const Point,
    big: u128,
    small: i7,
    precise: f64,
    half: f16,
};

fn expectAgrees(comptime T: type) !void {
    var buffer: [1024]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    try reflect.typeOf(T).describe(&w);
    try testing.expectEqualStrings(data.schema.describe(T), w.buffered());
    try testing.expectEqual(data.schema.fingerprint(T), reflect.typeOf(T).fingerprint());
}

test "the fingerprint of every type fluxion-data writes is the one it writes" {
    inline for (.{
        bool,      u8,                                  i7,     u64,    f32,    f64,                              f16,
        Colour,    Point,                               Shape,  Flags,  ?u32,   [3]i16,                           []const u8,
        []u8,      []const Point,                       Player, ?Point, [2]?u8, struct { a: []const []const u8 }, [0]u8,
        struct {}, packed struct(u16) { a: u9, b: i7 },
    }) |T| try expectAgrees(T);
}

test "a type built at run time has the fingerprint of the same Zig type" {
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    const Vec = extern struct { x: f32, y: f32 };
    const vec = try registry.defineStruct(.{ .name = "Vec", .size = @sizeOf(Vec), .alignment = @alignOf(Vec), .fields = &.{
        .{ .name = "x", .type = registry.find("f32").?, .offset = 0 },
        .{ .name = "y", .type = registry.find("f32").?, .offset = 4 },
    } });
    try testing.expectEqual(data.schema.fingerprint(Point), vec.fingerprint());
    const list = try registry.resolve("[]const Vec");
    try testing.expectEqual(data.schema.fingerprint([]const Point), list.fingerprint());
    const fixed = try registry.resolve("[4]u8");
    try testing.expectEqual(data.schema.fingerprint([4]u8), fixed.fingerprint());
}
