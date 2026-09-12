// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;
const fj = @import("fluxion_json");

const reflect = @import("root.zig");
const Value = reflect.Value;
const rj = reflect.json;

const Color = enum { red, dark_green, blue };

const Point = struct { x: f32, y: f32 };

const Shape = union(enum) {
    circle: f32,
    rect: Point,
    none,
};

const Tagged = union(enum) {
    circle: struct { radius: f32 = 1 },
    square: struct { side: f32 = 1, label: []const u8 = "sq" },
    nothing,

    pub const json_tag = "type";
};

const Settings = struct {
    title: []const u8 = "untitled",
    volume: f32 = 0.8,
    precise: f64 = 0.1,
    small: f16 = 1.5,
    level: u8 = 3,
    big: u64 = 1 << 60,
    negative: i32 = -7,
    color: Color = .dark_green,
    shape: Shape = .{ .circle = 2 },
    tagged: Tagged = .nothing,
    maybe: ?u16 = null,
    points: []const Point = &.{},
    fixed: [3]i8 = .{ 1, -2, 3 },
    label: [8:0]u8 = .{ 'h', 'i', 0, 0, 0, 0, 0, 0 },
    flags: packed struct(u8) { a: bool = false, b: bool = true, rest: u6 = 0 } = .{},
    pair: struct { i32, bool } = .{ 5, true },
    list: std.ArrayList(u16) = .empty,
    cache: u32 = 0,
    byte_offset: u16 = 9,
    vector: @Vector(3, f32) = .{ 1, 2, 3 },

    pub const json_ignore = .{.cache};
    pub const json_case = .camel;
    pub const json_rename = .{ .title = "heading" };
};

fn expectSame(value: anytype, options: fj.WriteOptions) !void {
    const expected = try fj.stringify(testing.allocator, value, options);
    defer testing.allocator.free(expected);
    var copy = value;
    const got = try rj.stringify(testing.allocator, Value.of(&copy), options);
    defer testing.allocator.free(got);
    if (options.format == .cbor) {
        try testing.expectEqualSlices(u8, expected, got);
    } else try testing.expectEqualStrings(expected, got);
}

const option_sets = [_]fj.WriteOptions{
    .{},
    .{ .indent = 2 },
    .{ .sort_keys = true },
    .{ .skip_defaults = true, .skip_nulls = true },
    .{ .format = .cbor },
    .{ .format = .cbor, .sort_keys = true, .skip_defaults = true },
};

test "written exactly as fluxion-json writes the Zig value" {
    var list_items = [_]u16{ 4, 5, 6 };
    var settings: Settings = .{};
    try expectSame(settings, .{});
    settings.title = "Ada \"quoted\" \u{1F980}";
    settings.maybe = 12;
    settings.points = &.{ .{ .x = 1, .y = -2.5 }, .{ .x = 0.1, .y = 1e30 } };
    settings.shape = .{ .rect = .{ .x = 3, .y = 4 } };
    settings.tagged = .{ .square = .{ .side = 2.5 } };
    settings.color = .blue;
    settings.list = .{ .items = &list_items, .capacity = list_items.len };
    settings.vector = .{ 0.5, -0.25, 8 };
    settings.big = std.math.maxInt(u64);
    for (option_sets) |options| try expectSame(settings, options);
    settings.shape = .none;
    settings.tagged = .{ .circle = .{} };
    for (option_sets) |options| try expectSame(settings, options);
}

test "read back as fluxion-json reads it, from text and from CBOR" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var list_items = [_]u16{ 7, 8 };
    var original: Settings = .{
        .title = "back again",
        .maybe = 3,
        .points = &.{.{ .x = 9, .y = 10 }},
        .shape = .{ .rect = .{ .x = 1, .y = 2 } },
        .tagged = .{ .square = .{ .side = 4, .label = "four" } },
        .list = .{ .items = &list_items, .capacity = 2 },
        .big = std.math.maxInt(u64) - 1,
        .negative = std.math.minInt(i32),
    };
    for (option_sets) |options| {
        const text = try fj.stringify(a, original, options);
        var read: Settings = .{ .level = 99, .maybe = 1 };
        try rj.parse(Value.of(&read), text, .{ .allocator = a });
        try testing.expect(Value.of(&read).eql(Value.of(&original)));
    }
    _ = &original;

    const Small = struct {
        byte_offset: u16 = 1,
        kind: Color = .red,
        shape: Shape = .none,
        points: []const Point = &.{},
        skipped: u8 = 5,

        pub const json_case = .kebab;
        pub const json_ignore = .{.skipped};
    };
    var small: Small = .{ .byte_offset = 300, .kind = .blue, .shape = .{ .circle = 0.5 }, .points = &.{.{ .x = 1, .y = 2 }}, .skipped = 9 };
    for (option_sets) |options| {
        const text = try fj.stringify(a, small, options);
        var read: Small = .{};
        try rj.parse(Value.of(&read), text, .{ .allocator = a });
        const parsed = try fj.parseAs(Small, a, text, .{});
        try testing.expect(Value.of(&read).eql(Value.of(&parsed.value)));
        try testing.expectEqual(@as(u8, 5), read.skipped);
    }
    _ = &small;
}

test "a tag written after the payload still reads" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var tagged: Tagged = .nothing;
    try rj.parse(Value.of(&tagged), "{\"side\": 3, \"label\": \"late\", \"type\": \"square\"}", .{ .allocator = arena.allocator() });
    try testing.expectEqual(@as(f32, 3), tagged.square.side);
    try testing.expectEqualStrings("late", tagged.square.label);
    try rj.parse(Value.of(&tagged), "{\"type\": \"circle\"}", .{ .allocator = arena.allocator() });
    try testing.expectEqual(@as(f32, 1), tagged.circle.radius);
}

test "what fluxion-json refuses, refused the same way" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var settings: Settings = .{};
    const v = Value.of(&settings);
    try testing.expectError(error.OutOfRange, rj.parse(v, "{\"level\": 300}", .{ .allocator = a }));
    try testing.expectError(error.WrongType, rj.parse(v, "{\"level\": \"three\"}", .{ .allocator = a }));
    try testing.expectError(error.WrongType, rj.parse(v, "{\"level\": 1.5}", .{ .allocator = a }));
    try testing.expectError(error.UnknownTag, rj.parse(v, "{\"color\": \"purple\"}", .{ .allocator = a }));
    try testing.expectError(error.LengthMismatch, rj.parse(v, "{\"fixed\": [1, 2]}", .{ .allocator = a }));
    try testing.expectError(error.UnknownField, rj.parse(v, "{\"levle\": 1}", .{ .allocator = a, .unknown_fields = .fail }));
    try rj.parse(v, "{\"levle\": 1}", .{ .allocator = a });

    const Required = struct { must: u8, may: u8 = 2 };
    var required: Required = .{ .must = 1 };
    try testing.expectError(error.MissingField, rj.parse(Value.of(&required), "{\"may\": 3}", .{ .allocator = a }));
    try rj.parse(Value.of(&required), "{\"may\": 3}", .{ .allocator = a, .patch = true });
    try testing.expectEqual(@as(u8, 1), required.must);
    try testing.expectEqual(@as(u8, 3), required.may);

    const Hooked = struct {
        x: u8 = 0,
        pub fn toJson(self: @This(), w: *fj.Writer) fj.Writer.Error!void {
            try w.writeInt(self.x);
        }
    };
    var hooked: Hooked = .{};
    try testing.expectError(error.Unsupported, rj.stringify(a, Value.of(&hooked), .{}));
}

test "the fields left out take their defaults, as parseAs gives them" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var settings: Settings = .{ .level = 50, .color = .red, .maybe = 7 };
    try rj.parse(Value.of(&settings), "{\"heading\": \"only this\"}", .{ .allocator = arena.allocator() });
    try testing.expectEqualStrings("only this", settings.title);
    try testing.expectEqual(@as(u8, 3), settings.level);
    try testing.expectEqual(Color.dark_green, settings.color);
    try testing.expectEqual(@as(?u16, null), settings.maybe);
}

fn randomSettings(rng: std.Random, a: std.mem.Allocator) !Settings {
    var s: Settings = .{};
    s.volume = rng.float(f32) * 100 - 50;
    s.precise = (rng.float(f64) - 0.5) * 1e12;
    s.level = rng.int(u8);
    s.big = rng.int(u64);
    s.negative = rng.int(i32);
    s.color = rng.enumValue(Color);
    s.shape = switch (rng.uintLessThan(u8, 3)) {
        0 => .{ .circle = rng.float(f32) },
        1 => .{ .rect = .{ .x = rng.float(f32), .y = -rng.float(f32) } },
        else => .none,
    };
    s.tagged = switch (rng.uintLessThan(u8, 3)) {
        0 => .{ .circle = .{ .radius = rng.float(f32) } },
        1 => .{ .square = .{ .side = rng.float(f32), .label = if (rng.boolean()) "a" else "bee" } },
        else => .nothing,
    };
    s.maybe = if (rng.boolean()) rng.int(u16) else null;
    const points = try a.alloc(Point, rng.uintLessThan(usize, 5));
    for (points) |*p| p.* = .{ .x = rng.float(f32), .y = rng.float(f32) * 1000 };
    s.points = points;
    s.fixed = .{ rng.int(i8), rng.int(i8), rng.int(i8) };
    s.flags = .{ .a = rng.boolean(), .b = rng.boolean(), .rest = rng.int(u6) };
    s.pair = .{ rng.int(i32), rng.boolean() };
    s.byte_offset = rng.int(u16);
    const items = try a.alloc(u16, rng.uintLessThan(usize, 4));
    for (items) |*i| i.* = rng.int(u16);
    s.list = .{ .items = items, .capacity = items.len };
    return s;
}

test "random values: the same text, and the same value read back" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    var prng: std.Random.DefaultPrng = .init(0x7e5);
    const rng = prng.random();
    for (0..300) |round| {
        var original = try randomSettings(rng, a);
        const options = option_sets[round % option_sets.len];
        try expectSame(original, options);
        const text = try rj.stringify(a, Value.of(&original), options);
        var read: Settings = .{};
        try rj.parse(Value.of(&read), text, .{ .allocator = a });
        try testing.expect(Value.of(&read).eql(Value.of(&original)));
    }
}

test "a type described at run time goes to JSON and back" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    const Vec2 = extern struct { x: f32, y: f32 };
    const vec2 = try registry.defineStruct(.{ .name = "Vec2", .size = @sizeOf(Vec2), .alignment = @alignOf(Vec2), .fields = &.{
        .{ .name = "x", .type = registry.find("f32").?, .offset = @offsetOf(Vec2, "x") },
        .{ .name = "y", .type = registry.find("f32").?, .offset = @offsetOf(Vec2, "y") },
    } });
    var at: Vec2 = .{ .x = 1.5, .y = -2 };
    const text = try rj.stringify(arena.allocator(), .init(vec2, &at), .{});
    try testing.expectEqualStrings("{\"x\":1.5,\"y\":-2.0}", text);
    try rj.parse(.init(vec2, &at), "{\"y\": 7, \"x\": 3}", .{ .allocator = arena.allocator() });
    try testing.expectEqual(Vec2{ .x = 3, .y = 7 }, at);
}

test "pointers are followed on the way out, and allocated on the way in" {
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();
    const Link = struct {
        at: *const Point,
        next: ?*const Point = null,
        name: [*:0]const u8 = "link",
    };
    const target: Point = .{ .x = 1, .y = 2 };
    const other: Point = .{ .x = 3, .y = 4 };
    var link: Link = .{ .at = &target, .next = &other };
    try expectSame(link, .{});
    try expectSame(link, .{ .format = .cbor });
    link.next = null;
    try expectSame(link, .{});

    var read: Link = .{ .at = &other };
    try rj.parse(Value.of(&read), "{\"at\": {\"x\": 7, \"y\": 8}, \"next\": {\"x\": 9, \"y\": 10}, \"name\": \"z\"}", .{ .allocator = a });
    try testing.expectEqual(Point{ .x = 7, .y = 8 }, read.at.*);
    try testing.expectEqual(Point{ .x = 9, .y = 10 }, read.next.?.*);
    try testing.expect(read.at != &other);
}
