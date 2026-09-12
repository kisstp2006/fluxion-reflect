// SPDX-License-Identifier: BSL-1.0

const std = @import("std");
const testing = std.testing;
const hashing = @import("fluxion_hash");

const reflect = @import("root.zig");
const typeOf = reflect.typeOf;
const Value = reflect.Value;
const attr = reflect.attr;

const test_types = @import("test_types.zig");
const Team = test_types.Team;
const Player = test_types.Player;
const Node = test_types.Node;
const Signed = test_types.Signed;
const Machine = test_types.Machine;

test "a descriptor says what the compiler knows" {
    const t = typeOf(Player);
    try testing.expectEqual(reflect.Kind.@"struct", t.kind);
    try testing.expectEqualStrings(@typeName(Player), t.name.slice());
    try testing.expectEqual(@sizeOf(Player), t.size);
    try testing.expectEqual(@as(u32, @alignOf(Player)), t.alignment);
    try testing.expectEqual(hashing.hashBytes(@typeName(Player)), t.id);
    try testing.expectEqual(@as(usize, 7), t.fields().len);
    inline for (@typeInfo(Player).@"struct".fields, 0..) |f, i| {
        const described = t.fields()[i];
        try testing.expectEqualStrings(f.name, described.name.slice());
        try testing.expectEqual(@as(usize, @offsetOf(Player, f.name)), described.offset);
        try testing.expect(described.type == typeOf(f.type));
    }
    try testing.expectEqual(reflect.Kind.slice, t.field("name").?.type.kind);
    try testing.expect(t.field("name").?.type.child().? == typeOf(u8));
    try testing.expectEqual(@as(usize, 3), typeOf([3]u8).info.array.len);
    try testing.expectEqual(reflect.Kind.@"enum", typeOf(Team).kind);
    try testing.expectEqual(@as(usize, 3), typeOf(Team).members().len);
    try testing.expectEqual(@as(u64, 1), typeOf(Team).member("blue").?.value);
    try testing.expect(t.field("nope") == null);
}

test "one type, one descriptor, and a type that points at itself closes into a cycle" {
    try testing.expect(typeOf(Player) == typeOf(Player));
    const next = typeOf(Node).field("next").?.type;
    try testing.expectEqual(reflect.Kind.optional, next.kind);
    try testing.expectEqual(reflect.Kind.pointer, next.child().?.kind);
    try testing.expect(next.child().?.child().? == typeOf(Node));
    try testing.expect(typeOf(Node).is(Node));
    try testing.expect(!typeOf(Node).is(Player));
}

test "attributes are found by their type" {
    const t = typeOf(Player);
    try testing.expectEqualStrings("someone playing", t.attribute(attr.Doc).?.text);
    const range = t.field("level").?.attribute(attr.Range).?;
    try testing.expectEqual(@as(f64, 99), range.max);
    try testing.expect(t.field("stats").?.attribute(attr.Hidden) != null);
    try testing.expect(t.field("name").?.attribute(attr.Hidden) == null);
    try testing.expectEqualStrings("how it is doing", t.field("stats").?.attribute(attr.Doc).?.text);
}

test "comptime values in attributes: numbers, names, types" {
    const t = typeOf(Machine);
    try testing.expect(t.attribute(attr.Hidden) != null);
    const bag = t.attributes.slice()[0];
    const v: Value = .initConst(bag.type, bag.value);
    try testing.expectEqual(@as(?i64, 10), (try v.field("max")).toInt(i64));
    try testing.expectEqual(@as(?i64, -3), (try v.field("min")).toInt(i64));
    try testing.expectEqualStrings("gauge", (try v.field("name")).toString().?);
    try testing.expectEqual(@as(?f64, 0.5), (try v.field("scale")).toFloat(f64));
    try testing.expect((try v.field("kind")).asType().? == typeOf(u32));
    try testing.expect(bag.type.fields()[0].is_comptime);
    try testing.expectError(error.ReadOnly, (try v.field("max")).setInt(3));
    try testing.expectEqualStrings("Low", typeOf(Signed).member("low").?.attribute(attr.Label).?.text);
    try testing.expect(typeOf(Machine).field("on_hit").?.attribute(attr.ReadOnly) != null);
}
