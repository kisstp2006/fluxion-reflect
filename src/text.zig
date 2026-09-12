// SPDX-License-Identifier: BSL-1.0

//! Values as Zig syntax, written and read the way ZON spells them:
//! `.{ .name = "Ada", .hp = 100, .team = .red, .target = null }`.
//!
//! Reading goes into a value that already exists, so a struct literal only
//! changes the fields it names - which is what a console's `set` wants.

const std = @import("std");
const Allocator = std.mem.Allocator;
const Writer = std.Io.Writer;

const model = @import("model.zig");
const Error = @import("value.zig").Error;
const Type = model.Type;

/// So that a slice leading back to itself cannot overflow the stack.
pub const max_depth = 64;

pub const write = @import("text/write.zig").write;
pub const parse = @import("text/read.zig").parse;

pub const ParseOptions = struct {
    /// Where the items of a slice and the bytes of a string read into a
    /// slice are put. Without one, those are refused and everything held in
    /// place still reads. What a failed read allocated is not given back: read
    /// into an arena.
    allocator: ?Allocator = null,
    diagnostics: ?*Diagnostics = null,
};

/// Where reading stopped, and what it was reading into.
pub const Diagnostics = struct {
    /// Bytes from the start of the text.
    offset: usize = 0,
    /// What was being read into there.
    type: ?*const Type = null,
    /// A name that was not found, and the nearest one that was.
    name: []const u8 = "",
    suggestion: ?[:0]const u8 = null,
    err: ?Error = null,

    pub fn format(self: Diagnostics, w: *Writer) Writer.Error!void {
        try w.print("byte {d}", .{self.offset});
        if (self.type) |t| try w.print(", reading a {s}", .{t.name.slice()});
        if (self.err) |err| try w.print(": {s}", .{@errorName(err)});
        if (self.name.len > 0) try w.print(" {s}", .{self.name});
        if (self.suggestion) |near| try w.print(" - did you mean {s}?", .{near});
    }
};
