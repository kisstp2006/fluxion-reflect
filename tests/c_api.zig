// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;
const reflect = @import("fluxion_reflect");

comptime {
    _ = reflect.c;
}

const Team = enum(u8) { red, blue };

const Inventory = struct {
    gold: u32 = 0,
    items: []const []const u8 = &.{},
};

const Hero = struct {
    name: []const u8 = "hero",
    level: u16 = 1,
    health: f32 = 100,
    team: Team = .red,
    tags: [4]u8 = .{ 'a', 'b', 'c', 0 },
    inventory: Inventory = .{},
    pal: ?*Hero = null,
    flags: packed struct(u8) { flying: bool = false, invisible: bool = false, rest: u6 = 0 } = .{},

    pub const reflect_name = "Hero";
    pub const reflect_methods = .{ .heal, .greet };

    pub fn heal(self: *Hero, amount: f32) f32 {
        self.health += amount;
        return self.health;
    }

    pub fn greet(self: *const Hero, times: u8) u32 {
        return @as(u32, self.level) * times;
    }
};

extern fn fxr_test_run(registry: *reflect.Registry, hero: *const reflect.Value, arena: *std.heap.ArenaAllocator, out: [*]u8, capacity: usize) c_int;
extern fn fxr_test_c_types(registry: *reflect.Registry, boss: *reflect.Value) c_int;
extern fn fxr_test_layouts(out: [*]usize, capacity: usize) usize;

test "C reads, writes and calls a Zig value it knows only through the API" {
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    _ = try registry.add(Hero);
    var boss: reflect.Value = undefined;
    try testing.expectEqual(@as(c_int, 0), fxr_test_c_types(&registry, &boss));

    var hero: Hero = .{};
    const v = reflect.Value.of(&hero);
    var arena: std.heap.ArenaAllocator = .init(testing.allocator);
    defer arena.deinit();
    var report: [2048]u8 = undefined;
    const failures = fxr_test_run(&registry, &v, &arena, &report, report.len);
    if (failures != 0) std.debug.print("{s}", .{std.mem.sliceTo(&report, 0)});
    try testing.expectEqual(@as(c_int, 0), failures);

    try testing.expectEqualStrings("From C", hero.name);
    try testing.expectEqual(@as(u16, 7), hero.level);
    try testing.expectEqual(@as(f32, 50.5), hero.health);
    try testing.expectEqual(Team.blue, hero.team);
    try testing.expectEqualSlices(u8, "xyz\x00", &hero.tags);
    try testing.expectEqual(@as(u32, 99), hero.inventory.gold);
    try testing.expectEqual(@as(usize, 2), hero.inventory.items.len);
    try testing.expectEqualStrings("lamp", hero.inventory.items[1]);
    try testing.expect(hero.flags.flying);
    try testing.expect(!hero.flags.invisible);
}

test "Zig reads the types C described" {
    var registry: reflect.Registry = .init(testing.allocator);
    defer registry.deinit();
    var boss: reflect.Value = undefined;
    try testing.expectEqual(@as(c_int, 0), fxr_test_c_types(&registry, &boss));

    try testing.expectEqualStrings("Enemy", boss.type.name.slice());
    try testing.expectEqual(@as(?u32, 7), (try boss.field("id")).toInt(u32));
    try testing.expectEqual(@as(?f32, 1.5), (try boss.path("at.x")).toFloat(f32));
    try testing.expectEqualStrings("boss", (try boss.field("kind")).toString().?);
    try testing.expectEqualStrings("the Destroyer", (try boss.field("title")).toString().?);

    var buffer: [256]u8 = undefined;
    const written = try std.fmt.bufPrint(&buffer, "{f}", .{boss});
    try testing.expect(std.mem.indexOf(u8, written, ".name = \"Grendel\"") != null);
    try testing.expect(std.mem.indexOf(u8, written, ".kind = .boss") != null);

    try (try boss.field("hp")).setInt(12);
    try testing.expectError(error.OutOfRange, (try boss.field("hp")).setInt(256));
    try testing.expectEqual(@as(?u8, 12), (try boss.field("hp")).toInt(u8));

    const add = registry.function("add").?;
    var a: i32 = 20;
    var b: i64 = 22;
    var sum: i32 = 0;
    try reflect.call(add, &.{ .of(&a), .of(&b) }, .of(&sum));
    try testing.expectEqual(@as(i32, 42), sum);
}

fn measure(comptime T: type, out: []usize, n: *usize) void {
    out[n.*] = @sizeOf(T);
    out[n.* + 1] = @alignOf(T);
    n.* += 2;
    if (@typeInfo(T) != .@"struct") return;
    inline for (@typeInfo(T).@"struct".fields) |f| {
        out[n.*] = @offsetOf(T, f.name);
        n.* += 1;
    }
}

test "the header's structs are the Zig ones, byte for byte" {
    const r = reflect;
    const C = reflect.c;
    var expected: [512]usize = undefined;
    var n: usize = 0;
    inline for (.{
        r.Str,           r.Attribute,          r.List(r.Attribute), r.Field,           r.Member,
        r.Method,        r.info.Int,           r.info.Float,        r.info.Pointer,    r.RawSlice,
        r.info.SliceOps, r.info.Slice,         r.info.Array,        r.info.ElementOps, r.info.Vector,
        r.info.Struct,   r.info.Enum,          r.info.UnionOps,     r.info.Union,      r.info.OptionalOps,
        r.info.Optional, r.info.ErrorUnionOps, r.info.ErrorUnion,   r.info.ErrorSet,   r.Param,
        r.info.Function, r.info.Info,          r.Type,              r.Value,           C.Bytes,
        C.FieldDesc,     C.StructDesc,         C.MemberDesc,        C.EnumDesc,        C.ArmDesc,
        C.UnionDesc,     C.FunctionDesc,       C.JsonOptions,
    }) |T| measure(T, &expected, &n);
    expected[n] = @sizeOf(C.Status);
    expected[n + 1] = @intFromEnum(C.Status.unknown_type);
    expected[n + 2] = @intFromEnum(reflect.Kind.noreturn);
    expected[n + 3] = @intFromEnum(reflect.PointerSize.c);
    expected[n + 4] = @intFromEnum(reflect.Layout.@"packed");
    expected[n + 5] = @intFromEnum(reflect.CallingConvention.other);
    n += 6;

    var measured: [512]usize = undefined;
    const got = fxr_test_layouts(&measured, measured.len);
    try testing.expectEqualSlices(usize, expected[0..n], measured[0..got]);
}
