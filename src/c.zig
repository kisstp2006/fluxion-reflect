// SPDX-License-Identifier: BSL-1.0

//! The functions `include/fluxion_reflect.h` declares: one file under `c/`
//! for each of its headers.
//!
//! Nothing else in the library refers to these files, and that matters: an
//! `export fn` is put in the binary as soon as anything reaches the file it is
//! in. A C program links the library `zig build` installs; a Zig program that
//! wants C code beside it to call these writes `comptime { _ = reflect.c; }`.

const base = @import("c/base.zig");
const values = @import("c/values.zig");
const json = @import("c/json.zig");
const registry = @import("c/registry.zig");

comptime {
    _ = base;
    _ = @import("c/types.zig");
    _ = values;
    _ = @import("c/calls.zig");
    _ = json;
    _ = registry;
}

pub const abi_version = base.abi_version;
pub const allocator = base.allocator;
pub const Status = base.Status;
pub const Bytes = values.Bytes;
pub const JsonOptions = json.Options;
pub const FieldDesc = registry.FieldDesc;
pub const StructDesc = registry.StructDesc;
pub const MemberDesc = registry.MemberDesc;
pub const EnumDesc = registry.EnumDesc;
pub const ArmDesc = registry.ArmDesc;
pub const UnionDesc = registry.UnionDesc;
pub const FunctionDesc = registry.FunctionDesc;
