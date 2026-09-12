// SPDX-License-Identifier: BSL-1.0

//! A tour of Fluxion Reflect. Run it with `zig build example`.
//!
//! It describes a type, reads and writes a value of it by name, types into
//! it the way a console would, calls a method by name, finds the type by
//! name in a registry, and writes the value out as JSON.

const std = @import("std");
const Allocator = std.mem.Allocator;
const reflect = @import("fluxion_reflect");
const attr = reflect.attr;
const Value = reflect.Value;

const Team = enum { red, blue };

const Flags = packed struct(u8) { visible: bool = true, ghost: bool = false, spare: u6 = 0 };

const Stats = struct {
    health: f32 = 100,
    armour: u8 = 0,

    pub const reflect_fields = .{
        .health = .{ attr.Range{ .min = 0, .max = 200, .step = 5 }, attr.Doc{ .text = "Hit points" } },
    };
};

const Player = struct {
    name: []const u8 = "Ada",
    level: u16 = 1,
    team: Team = .red,
    stats: Stats = .{},
    inventory: []const []const u8 = &.{},
    target: ?*Player = null,
    flags: Flags = .{},

    pub const reflect_name = "Player";
    pub const reflect_attributes = .{attr.Doc{ .text = "Someone in the game" }};
    pub const reflect_methods = .{ .heal = .{attr.Doc{ .text = "Adds to health, up to its range" }} };

    pub fn heal(self: *Player, amount: f32) f32 {
        const range = reflect.typeOf(Stats).field("health").?.attribute(attr.Range).?;
        self.stats.health = @min(self.stats.health + amount, @as(f32, @floatCast(range.max)));
        return self.stats.health;
    }
};

pub fn main(init: std.process.Init) !void {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buffer);
    const out = &stdout.interface;
    try tour(init.gpa, out);
    try out.flush();
}

fn tour(gpa: Allocator, out: *std.Io.Writer) !void {
    var arena_state: std.heap.ArenaAllocator = .init(gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    try out.writeAll("--- a type, made into data at compile time ---\n");
    const t = reflect.typeOf(Player);
    try out.print("{s}: {d} bytes, {s}\n", .{ t.name.slice(), t.size, t.attribute(attr.Doc).?.text });
    try printFields(out, t, 1);

    try out.writeAll("\n--- a value, read and written by name ---\n");
    var player: Player = .{};
    const v = Value.of(&player);
    try (try v.path("stats.health")).setFloat(75);
    try (try v.field("team")).setString("blue");
    try (try v.path("flags.ghost")).setBool(true);
    try out.print("{f}\n", .{v});

    try out.writeAll("\n--- typed in, as a console would ---\n");
    try v.parse(".{ .name = \"Grace\", .level = 12, .inventory = .{ \"map\", \"lamp\" } }", .{ .allocator = arena });
    try out.print("{f}\n", .{v});
    if (v.path("stats.helth")) |_| {} else |_| {
        try reflect.explainPath(v, "stats.helth", out);
        try out.writeByte('\n');
    }

    try out.writeAll("\n--- a method, called by name ---\n");
    const heal = t.method("heal").?;
    var amount: f32 = 500;
    var healed: f32 = 0;
    try v.call("heal", &.{.of(&amount)}, .of(&healed));
    try out.print("{s} ({s}): health is now {d}\n", .{ heal.name.slice(), heal.attribute(attr.Doc).?.text, healed });

    try out.writeAll("\n--- a registry, for finding types by name ---\n");
    var registry: reflect.Registry = .init(gpa);
    defer registry.deinit();
    _ = try registry.add(Player);
    const found = registry.find("Player").?;
    const list = try registry.resolve("[]const Player");
    try out.print("found {s}, and made {s}, the same type as the compiler's: {}\n", .{
        found.name.slice(),
        list.name.slice(),
        list.same(reflect.typeOf([]const Player)),
    });
    try out.print("\"Plyer\"? did you mean {s}?\n", .{registry.suggest("Plyer").?});

    try out.writeAll("\n--- JSON, through fluxion-json ---\n");
    const text = try reflect.json.stringify(arena, v, .{ .indent = 2, .skip_defaults = true });
    try out.print("{s}\n", .{text});
    var copy: Player = .{};
    try reflect.json.parse(.of(&copy), text, .{ .allocator = arena });
    try out.print("read back the same: {}\n", .{Value.of(&copy).eql(v)});

    try out.writeAll("\n--- what the value and the type come to ---\n");
    try out.print("hash {x}, schema fingerprint {x}\n", .{ v.hash(), t.fingerprint() });
}

fn printFields(out: *std.Io.Writer, t: *const reflect.Type, depth: usize) !void {
    for (t.fields()) |f| {
        try out.splatByteAll(' ', depth * 2);
        try out.print("{s}: {s}", .{ f.name.slice(), f.type.name.slice() });
        if (f.is_bit_field) try out.print(" (bits {d}..{d})", .{ f.bit_offset, f.bit_offset + f.type.bit_size - 1 }) else try out.print(" at {d}", .{f.offset});
        if (f.attribute(attr.Range)) |range| try out.print(", {d} to {d}", .{ range.min, range.max });
        try out.writeByte('\n');
        if (f.type.kind == .@"struct" and f.type.info.@"struct".layout != .@"packed") try printFields(out, f.type, depth + 1);
    }
}

test "the tour runs, and says what it should" {
    var buffer: [8192]u8 = undefined;
    var w: std.Io.Writer = .fixed(&buffer);
    try tour(std.testing.allocator, &w);
    const said = w.buffered();
    try std.testing.expect(std.mem.indexOf(u8, said, "did you mean health?") != null);
    try std.testing.expect(std.mem.indexOf(u8, said, "health is now 200") != null);
    try std.testing.expect(std.mem.indexOf(u8, said, "read back the same: true") != null);
    try std.testing.expect(std.mem.indexOf(u8, said, "the same type as the compiler's: true") != null);
}
