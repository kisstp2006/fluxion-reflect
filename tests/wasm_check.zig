// SPDX-License-Identifier: BSL-1.0

//! The library as a browser build has it: `wasm32-freestanding`, no C
//! library, the C API exported, and the C half of the C test linked in.
//! `zig build test` compiles it; `tests/web.mjs` runs `check` in Node.

const std = @import("std");
const reflect = @import("fluxion_reflect");

comptime {
    _ = reflect.c;
}

const gpa = std.heap.wasm_allocator;

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

var report_buffer: [4096]u8 = undefined;
var report: std.Io.Writer = .fixed(&report_buffer);

export fn reportPtr() [*]const u8 {
    return &report_buffer;
}

export fn reportLen() usize {
    return report.end;
}

fn expect(ok: bool, what: []const u8, failures: *u32) void {
    if (ok) return;
    failures.* += 1;
    report.print("wasm_check: {s}\n", .{what}) catch {};
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

export fn check() u32 {
    var failures: u32 = 0;
    report = .fixed(&report_buffer);

    var registry: reflect.Registry = .init(gpa);
    defer registry.deinit();
    _ = registry.add(Hero) catch return 1000;
    var boss: reflect.Value = undefined;
    expect(fxr_test_c_types(&registry, &boss) == 0, "C described its types", &failures);

    var hero: Hero = .{};
    const v = reflect.Value.of(&hero);
    var c_arena: std.heap.ArenaAllocator = .init(gpa);
    defer c_arena.deinit();
    var c_report: [2048]u8 = undefined;
    const c_failures = fxr_test_run(&registry, &v, &c_arena, &c_report, c_report.len);
    if (c_failures != 0) report.print("{s}", .{std.mem.sliceTo(&c_report, 0)}) catch {};
    failures += @intCast(c_failures);
    expect(std.mem.eql(u8, hero.name, "From C") and hero.level == 7 and hero.flags.flying, "C wrote the hero", &failures);
    expect(hero.inventory.items.len == 2 and std.mem.eql(u8, hero.inventory.items[1], "lamp"), "C parsed a slice of strings", &failures);

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
    expect(got == n and std.mem.eql(usize, expected[0..n], measured[0..got]), "the header's layouts match", &failures);

    var text: [512]u8 = undefined;
    const written = std.fmt.bufPrint(&text, "{f}", .{(v.field("inventory") catch return failures + 100)}) catch "";
    expect(std.mem.eql(u8, written, ".{ .gold = 99, .items = .{ \"rope\", \"lamp\" } }"), "the inventory reads back as Zig syntax", &failures);

    var arena: std.heap.ArenaAllocator = .init(gpa);
    defer arena.deinit();
    const json_text = reflect.json.stringify(arena.allocator(), v.field("inventory") catch return failures + 100, .{}) catch "";
    expect(std.mem.eql(u8, json_text, "{\"gold\":99,\"items\":[\"rope\",\"lamp\"]}"), "the inventory as JSON", &failures);
    var copy: Inventory = .{};
    reflect.json.parse(.of(&copy), json_text, .{ .allocator = arena.allocator() }) catch {};
    expect(copy.gold == 99 and copy.items.len == 2, "the inventory back from JSON", &failures);

    const packed_layer = v.path("flags.invisible") catch return failures + 100;
    packed_layer.setBool(true) catch {};
    expect(hero.flags.invisible and hero.flags.flying, "a bit field written in place", &failures);
    expect(@sizeOf(usize) == 4, "wasm32 pointers are four bytes", &failures);
    return failures;
}
