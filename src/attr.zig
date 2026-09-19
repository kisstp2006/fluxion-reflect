// SPDX-License-Identifier: BSL-1.0

//! Attributes worth one spelling across the Fluxion tools. Any value can be an
//! attribute; these are the ones an inspector, a console and a serialiser
//! would otherwise each invent.
//!
//! ```zig
//! pub const reflect_fields = .{
//!     .health = .{ attr.Range{ .min = 0, .max = 100 }, attr.Doc{ .text = "Hit points" } },
//!     .cache = .{attr.Hidden{}},
//! };
//! ```

/// The span a number is meant to keep to, and the step an editor moves it
/// by; zero is no step.
pub const Range = extern struct {
    min: f64,
    max: f64,
    step: f64 = 0,
};

/// A line about it, for a tooltip or a console's help.
pub const Doc = struct {
    text: []const u8,
};

/// What a person sees instead of the name.
pub const Label = struct {
    text: []const u8,
};

/// The names of a function's parameters, in order.
///
/// Zig does not keep them, so a function that a tool calls by name - an
/// inspector, a console, a binding generator - lists them here, on the method
/// in `reflect_methods` or on a function added to a `Registry`. `self` is not
/// listed: a method whose first parameter is its own type, or a pointer to it,
/// has that one implied.
///
/// The count is checked, so a parameter added later is a compile error until
/// its name is here too:
///
/// ```zig
/// pub const reflect_methods = .{
///     .heal = .{ attr.Params{ .names = &.{"amount"} }, attr.Doc{ .text = "Adds hit points" } },
/// };
/// ```
pub const Params = struct {
    names: []const []const u8,
};

/// Kept out of an inspector's view.
pub const Hidden = struct {};

/// Shown, and not to be changed by hand.
pub const ReadOnly = struct {};
