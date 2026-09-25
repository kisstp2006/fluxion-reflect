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

/// What a method's last parameters are when a call leaves them out: one
/// value for each of as many of the last parameters as there are values,
/// each of the parameter's type. Written with `defaults`, which the registry
/// turns into this:
///
/// ```zig
/// pub const reflect_methods = .{
///     .play = .{
///         attr.Params{ .names = &.{ "name", "custom_speed", "from_end" } },
///         attr.defaults(.{ "", 1.0, false }),
///     },
/// };
/// ```
pub const Defaults = struct {
    /// The first defaulted parameter's first.
    values: []const Default,

    pub const Default = struct {
        type: *const model.Type,
        value: *const anyopaque,
    };
};

/// `Defaults` as `reflect_methods` writes them: the values, which the
/// registry makes the types of the parameters they are for.
pub fn defaults(comptime values: anytype) DefaultsOf(@TypeOf(values)) {
    return .{ .values = values };
}

/// What `defaults` makes, before the registry has seen the parameters.
pub fn DefaultsOf(comptime Values: type) type {
    return struct {
        values: Values,

        pub const reflect_defaults_of = Values;
    };
}

/// A field whose writes go through a method of its type's - named here, and
/// listed in `reflect_methods` - that takes the new value: a change with more
/// to do than be stored, such as an animation's name that starts it again.
/// A tool that writes the field for a person - a console, a script - calls
/// the method instead.
pub const Setter = struct {
    method: []const u8,
};

const model = @import("model.zig");
