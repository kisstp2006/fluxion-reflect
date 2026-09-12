// SPDX-License-Identifier: BSL-1.0

//! Fluxion Reflect - Zig types, read and written at run time, from Zig and
//! from C.
//!
//! ```zig
//! const reflect = @import("fluxion_reflect");
//!
//! const t = reflect.typeOf(Player);          // a descriptor: data in the binary
//! for (t.fields()) |f| std.debug.print("{s}: {s}\n", .{ f.name.slice(), f.type.name.slice() });
//!
//! var player: Player = .{};
//! const v = reflect.Value.of(&player);
//! try (try v.path("stats.health")).setFloat(80);
//! try v.parse(".{ .name = \"Ada\", .team = .blue }", .{});
//! std.debug.print("{f}\n", .{v});            // .{ .name = "Ada", .team = .blue, ... }
//!
//! var registry: reflect.Registry = .init(gpa);
//! defer registry.deinit();
//! _ = try registry.add(Player);
//! const found = registry.find("Player").?;   // by name, at run time
//! ```

const model = @import("model.zig");
const value = @import("value.zig");
const generate = @import("generate.zig");
const text = @import("text.zig");
const path_mod = @import("path.zig");
const call_mod = @import("call.zig");

pub const Type = model.Type;
pub const Kind = model.Kind;
pub const Field = model.Field;
pub const Member = model.Member;
pub const Method = model.Method;
pub const Attribute = model.Attribute;
pub const Param = model.Param;
pub const Str = model.Str;
pub const List = model.List;
pub const Invoke = model.Invoke;
pub const RawSlice = model.RawSlice;
pub const PointerSize = model.PointerSize;
pub const Layout = model.Layout;
pub const CallingConvention = model.CallingConvention;
pub const info = struct {
    pub const Int = model.Int;
    pub const Float = model.Float;
    pub const Pointer = model.Pointer;
    pub const Slice = model.Slice;
    pub const Array = model.Array;
    pub const Vector = model.Vector;
    pub const Struct = model.Struct;
    pub const Enum = model.Enum;
    pub const Union = model.Union;
    pub const Optional = model.Optional;
    pub const ErrorUnion = model.ErrorUnion;
    pub const ErrorSet = model.ErrorSet;
    pub const Function = model.Function;
    pub const SliceOps = model.SliceOps;
    pub const ElementOps = model.ElementOps;
    pub const UnionOps = model.UnionOps;
    pub const OptionalOps = model.OptionalOps;
    pub const ErrorUnionOps = model.ErrorUnionOps;
    pub const Info = model.Info;
};

pub const Value = value.Value;
pub const Error = value.Error;
pub const Registry = @import("Registry.zig");
pub const attr = @import("attr.zig");

/// Values as JSON and CBOR through fluxion-json, spelt as it spells the Zig
/// types.
pub const json = @import("json.zig");

pub const ParseOptions = text.ParseOptions;
pub const Diagnostics = text.Diagnostics;

/// The descriptor of `T`: made at compile time, kept in the binary, the same
/// pointer every time.
pub const typeOf = generate.typeOf;

/// What `T` starts as when nothing says otherwise. See `Type.default`.
pub const initialValue = generate.initialValue;

/// Call a method or registered function with values for arguments.
pub const call = call_mod.call;

/// Why `Value.path` failed, in words, with the nearest name when a name was
/// wrong.
pub const explainPath = path_mod.explain;

/// The C API of `include/fluxion_reflect.h`. Its functions are exported, so
/// they are in a binary only once something reaches this: a Zig program with
/// C code beside it writes `comptime { _ = reflect.c; }`.
pub const c = @import("c.zig");

test {
    _ = @import("bits.zig");
    _ = @import("describe_test.zig");
    _ = @import("value_test.zig");
    _ = @import("text_test.zig");
    _ = @import("call_test.zig");
    _ = @import("registry_test.zig");
    _ = @import("hash_test.zig");
    _ = @import("json_test.zig");
}
