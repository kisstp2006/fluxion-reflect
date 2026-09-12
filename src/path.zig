// SPDX-License-Identifier: BSL-1.0

//! Paths into a value, in Zig's own syntax: `inventory[2].name`,
//! `target.?.health`, `parent.*.x`. Pointers are followed on the way as Zig
//! follows them, so `owner.name` reads through `owner: *Player`.

const std = @import("std");
const fuzzy = @import("fluxion_text").fuzzy;

const model = @import("model.zig");
const value_mod = @import("value.zig");
const Value = value_mod.Value;
const Error = value_mod.Error;
const Type = model.Type;

const Step = union(enum) {
    field: []const u8,
    index: usize,
    unwrap,
    deref,
};

pub fn walk(start: Value, spec: []const u8) Error!Value {
    var cursor: Cursor = .{ .text = spec };
    var at = start;
    while (try cursor.next()) |step| at = try apply(at, step);
    return at;
}

fn apply(at: Value, step: Step) Error!Value {
    return switch (step) {
        .field => |name| at.field(name),
        .index => |i| at.index(i),
        .unwrap => at.unwrap() orelse if (at.type.kind == .optional or at.type.kind == .error_union) error.Null else error.TypeMismatch,
        .deref => at.deref(),
    };
}

const Cursor = struct {
    text: []const u8,
    at: usize = 0,

    fn next(self: *Cursor) Error!?Step {
        if (self.at >= self.text.len) return null;
        const c = self.text[self.at];
        if (c == '[') {
            const close = std.mem.indexOfScalarPos(u8, self.text, self.at, ']') orelse return error.Syntax;
            const digits = self.text[self.at + 1 .. close];
            const i = std.fmt.parseUnsigned(usize, digits, 10) catch return error.Syntax;
            self.at = close + 1;
            return .{ .index = i };
        }
        if (c == '.') {
            self.at += 1;
            if (self.at >= self.text.len) return error.Syntax;
            switch (self.text[self.at]) {
                '?' => {
                    self.at += 1;
                    return .unwrap;
                },
                '*' => {
                    self.at += 1;
                    return .deref;
                },
                else => {},
            }
        } else if (self.at != 0) return error.Syntax;
        return .{ .field = try self.identifier() };
    }

    fn identifier(self: *Cursor) Error![]const u8 {
        const rest = self.text[self.at..];
        if (std.mem.startsWith(u8, rest, "@\"")) {
            const close = std.mem.indexOfScalarPos(u8, rest, 2, '"') orelse return error.Syntax;
            self.at += close + 1;
            return rest[2..close];
        }
        var n: usize = 0;
        while (n < rest.len and isIdentifierByte(rest[n], n)) n += 1;
        if (n == 0) return error.Syntax;
        self.at += n;
        return rest[0..n];
    }
};

pub fn isIdentifierByte(c: u8, position: usize) bool {
    return switch (c) {
        'a'...'z', 'A'...'Z', '_' => true,
        '0'...'9' => position > 0,
        else => false,
    };
}

/// Why `walk` failed, in words: which step, what it met there, and the
/// nearest name when a name was wrong.
pub fn explain(start: Value, spec: []const u8, w: *std.Io.Writer) std.Io.Writer.Error!void {
    var cursor: Cursor = .{ .text = spec };
    var at = start;
    while (true) {
        const before = cursor.at;
        const step = cursor.next() catch {
            return w.print("\"{s}\" does not read at byte {d}", .{ spec, before });
        } orelse return w.print("\"{s}\" leads to a {f}", .{ spec, at.type });
        at = apply(at, step) catch |err| {
            const where = if (before == 0) "the value" else spec[0..before];
            try w.print("{s} is a {f}", .{ where, at.type });
            switch (step) {
                .field => |name| {
                    const target = if (at.type.kind == .pointer and at.type.info.pointer.size == .one) at.type.info.pointer.child else at.type;
                    switch (err) {
                        error.NoSuchField => {
                            try w.print(", which has no field {s}", .{name});
                            if (suggest(target, name)) |near| try w.print(" - did you mean {s}?", .{near});
                        },
                        error.InactiveArm => try w.print(", and {s} is not its live arm", .{name}),
                        error.Null => try w.writeAll(", which is null"),
                        else => try w.print(", which has no fields to take {s} from", .{name}),
                    }
                },
                .index => |i| switch (err) {
                    error.IndexOutOfBounds => try w.print(", which has {d} items and no [{d}]", .{ at.len() catch 0, i }),
                    error.Null => try w.writeAll(", which is null"),
                    else => try w.writeAll(", which cannot be indexed"),
                },
                .unwrap => try w.writeAll(if (err == error.Null) ", which holds nothing to unwrap" else ", which is neither an optional nor an error union"),
                .deref => try w.writeAll(if (err == error.Null) ", which is null" else ", which is not a pointer to one value"),
            }
            return;
        };
    }
}

/// The field, member or method name of `t` nearest to `name`, when one is
/// near enough to be what was meant.
pub fn suggest(t: *const Type, name: []const u8) ?[:0]const u8 {
    const budget = @max(2, name.len / 3);
    var best: ?[:0]const u8 = null;
    var best_distance: usize = budget + 1;
    const consider = struct {
        fn one(candidate: [:0]const u8, needle: []const u8, limit: usize, found: *?[:0]const u8, distance: *usize) void {
            const d = (fuzzy.editDistance(needle, candidate, limit) catch return) orelse return;
            if (d < distance.*) {
                distance.* = d;
                found.* = candidate;
            }
        }
    }.one;
    for (t.fields()) |f| consider(f.name.slice(), name, budget, &best, &best_distance);
    for (t.members()) |m| consider(m.name.slice(), name, budget, &best, &best_distance);
    for (t.methods.slice()) |m| consider(m.name.slice(), name, budget, &best, &best_distance);
    return best;
}
