// SPDX-License-Identifier: BSL-1.0

const attr = @import("root.zig").attr;

pub const Team = enum(u8) { red, blue, green };

pub const Stats = struct {
    health: f32 = 100,
    armour: u8 = 0,
};

pub const Flags = packed struct(u8) {
    visible: bool = true,
    solid: bool = false,
    layer: u4 = 3,
    spare: u2 = 0,
};

pub const Player = struct {
    name: []const u8 = "anon",
    level: u16 = 1,
    stats: Stats = .{},
    team: Team = .red,
    target: ?*Player = null,
    inventory: [3]u8 = .{ 0, 0, 0 },
    flags: Flags = .{},

    pub const reflect_attributes = .{attr.Doc{ .text = "someone playing" }};
    pub const reflect_fields = .{
        .level = .{attr.Range{ .min = 1, .max = 99 }},
        .stats = .{ attr.Doc{ .text = "how it is doing" }, attr.Hidden{} },
    };
    pub const reflect_methods = .{ .heal, "rename", "describe" };

    pub fn heal(self: *Player, amount: f32) f32 {
        self.stats.health += amount;
        return self.stats.health;
    }

    pub fn rename(self: *Player, name: []const u8) void {
        self.name = name;
    }

    pub fn describe(self: Player) u16 {
        return self.level * 10;
    }
};

pub const Shape = union(enum) {
    circle: f32,
    box: struct { w: f32, h: f32 },
    none,
};

pub const Node = struct {
    value: i32 = 0,
    next: ?*Node = null,
};

pub const Signed = enum(i8) {
    low = -2,
    zero = 0,
    high = 5,

    pub const reflect_fields = .{ .low = .{attr.Label{ .text = "Low" }} };
};

pub const Machine = struct {
    level: Signed = .zero,
    on_hit: *const fn (i32) i32 = double,
    maybe_hit: ?*const fn (i32) i32 = null,

    pub const reflect_methods = .{ .load, .loadOr };
    pub const reflect_fields = .{
        .on_hit = .{attr.ReadOnly{}},
    };
    pub const reflect_attributes = .{ .{ .min = -3, .max = 10, .kind = u32, .name = .gauge, .scale = 0.5 }, attr.Hidden{} };

    fn double(x: i32) i32 {
        return x * 2;
    }

    pub fn load(self: *const Machine, fail: bool) error{Jammed}!u8 {
        if (fail) return error.Jammed;
        return @intCast(@intFromEnum(self.level) + 10);
    }

    pub fn loadOr(self: *const Machine, fallback: u8) u8 {
        return self.load(false) catch fallback;
    }
};

pub fn triple(x: i32) i32 {
    return x * 3;
}
