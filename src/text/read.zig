// SPDX-License-Identifier: BSL-1.0

//! Zig syntax read into a `Value` that already exists, so a struct literal
//! only changes the fields it names.

const std = @import("std");
const number = @import("fluxion_text").number;

const model = @import("../model.zig");
const value_mod = @import("../value.zig");
const path = @import("../path.zig");
const text = @import("../text.zig");
const strings = @import("strings.zig");

const Value = value_mod.Value;
const Error = value_mod.Error;
const Type = model.Type;
const ParseOptions = text.ParseOptions;
const max_depth = text.max_depth;

pub fn parse(into: Value, source: []const u8, options: ParseOptions) Error!void {
    var reader: Reader = .{ .source = source, .options = options };
    try reader.value(into, 0);
    reader.skip();
    if (reader.at != source.len) return reader.fail(error.Syntax, into.type);
}

const Reader = struct {
    source: []const u8,
    at: usize = 0,
    options: ParseOptions,

    // ---------------------------------------------------------------------
    // Failing, with diagnostics
    // ---------------------------------------------------------------------

    /// Where the text stopped reading: for a value that was refused, its
    /// start; for text that does not read, the place it stopped.
    fn note(self: *Reader, err: Error, t: ?*const Type, offset: usize) void {
        const d = self.options.diagnostics orelse return;
        if (d.err == null) d.* = .{ .offset = offset, .type = t, .err = err };
    }

    fn fail(self: *Reader, err: Error, t: ?*const Type) Error {
        self.note(err, t, self.at);
        return err;
    }

    fn failName(self: *Reader, err: Error, t: *const Type, name: []const u8) Error {
        if (self.options.diagnostics) |d| {
            if (d.err == null) d.* = .{
                .offset = @intFromPtr(name.ptr) - @intFromPtr(self.source.ptr),
                .type = t,
                .err = err,
                .name = name,
                .suggestion = path.suggest(t, name),
            };
        }
        return err;
    }

    fn check(_: *Reader, result: Error!void, _: *const Type) Error!void {
        return result;
    }

    fn check2(_: *Reader, result: Error!Value, _: *const Type) Error!Value {
        return result;
    }

    // ---------------------------------------------------------------------
    // Tokens
    // ---------------------------------------------------------------------

    fn skip(self: *Reader) void {
        while (self.at < self.source.len) {
            const c = self.source[self.at];
            if (c == ' ' or c == '\t' or c == '\n' or c == '\r') {
                self.at += 1;
            } else if (std.mem.startsWith(u8, self.source[self.at..], "//")) {
                self.at = std.mem.indexOfScalarPos(u8, self.source, self.at, '\n') orelse self.source.len;
            } else break;
        }
    }

    fn peek(self: *Reader) ?u8 {
        return if (self.at < self.source.len) self.source[self.at] else null;
    }

    fn eat(self: *Reader, c: u8) bool {
        self.skip();
        if (self.peek() != c) return false;
        self.at += 1;
        return true;
    }

    fn expect(self: *Reader, c: u8, t: *const Type) Error!void {
        if (!self.eat(c)) return self.fail(error.Syntax, t);
    }

    fn identifier(self: *Reader) ?[]const u8 {
        const rest = self.source[self.at..];
        if (std.mem.startsWith(u8, rest, "@\"")) {
            const close = std.mem.indexOfScalarPos(u8, rest, 2, '"') orelse return null;
            self.at += close + 1;
            return rest[2..close];
        }
        var n: usize = 0;
        while (n < rest.len and path.isIdentifierByte(rest[n], n)) n += 1;
        if (n == 0) return null;
        self.at += n;
        return rest[0..n];
    }

    /// The text between two quotes, escapes and all.
    fn quoted(self: *Reader, t: *const Type) Error![]const u8 {
        self.at += 1;
        const first = self.at;
        while (self.at < self.source.len) : (self.at += 1) {
            switch (self.source[self.at]) {
                '\\' => self.at += 1,
                '"' => {
                    self.at += 1;
                    return self.source[first .. self.at - 1];
                },
                '\n' => break,
                else => {},
            }
        }
        return self.fail(error.Syntax, t);
    }

    // ---------------------------------------------------------------------
    // Values
    // ---------------------------------------------------------------------

    fn value(self: *Reader, into: Value, depth: usize) Error!void {
        self.skip();
        const start = self.at;
        self.valueAt(into, depth) catch |err| {
            self.note(err, into.type, start);
            return err;
        };
    }

    fn valueAt(self: *Reader, into: Value, depth: usize) Error!void {
        const t = into.type;
        if (depth > max_depth) return self.fail(error.Syntax, t);
        const start = self.at;
        if (self.identifier()) |word| {
            if (std.mem.eql(u8, word, "null")) return self.check(into.setNull(), t);
            if (std.mem.eql(u8, word, "error") and self.eat('.')) {
                const name = self.identifier() orelse return self.fail(error.Syntax, t);
                return self.check(into.setError(name), t);
            }
            self.at = start;
        }
        switch (t.kind) {
            .optional, .error_union => return self.value(try self.check2(into.unwrapOrInit(), t), depth + 1),
            else => {},
        }
        const c = self.peek() orelse return self.fail(error.Syntax, t);
        switch (c) {
            '"' => return self.string(into),
            '.' => {
                self.at += 1;
                if (self.peek() == '{') {
                    self.at += 1;
                    return self.aggregate(into, depth);
                }
                const name = self.identifier() orelse return self.fail(error.Syntax, t);
                return self.named(into, name);
            },
            '-', '+', '0'...'9' => return self.numberInto(into),
            '@' => {
                if (std.mem.startsWith(u8, self.source[self.at..], "@enumFromInt(")) {
                    self.at += "@enumFromInt(".len;
                    try self.numberInto(into);
                    return self.expect(')', t);
                }
                const name = self.identifier() orelse return self.fail(error.Syntax, t);
                return self.named(into, name);
            },
            else => {
                const word = self.identifier() orelse return self.fail(error.Syntax, t);
                if (std.mem.eql(u8, word, "true")) return self.check(into.setBool(true), t);
                if (std.mem.eql(u8, word, "false")) return self.check(into.setBool(false), t);
                if (std.mem.eql(u8, word, "inf")) return self.check(into.setFloat(std.math.inf(f128)), t);
                if (std.mem.eql(u8, word, "nan")) return self.check(into.setFloat(std.math.nan(f128)), t);
                return self.named(into, word);
            },
        }
    }

    /// `.name` or a bare `name`: an enum's member, or a union's arm made
    /// live with its default, which is how ZON writes an arm with no payload.
    fn named(self: *Reader, into: Value, name: []const u8) Error!void {
        const t = into.type;
        switch (t.kind) {
            .@"enum" => {
                if (t.member(name) == null) return self.failName(error.NoSuchMember, t, name);
                return self.check(into.setString(name), t);
            },
            .@"union" => {
                if (t.fieldIndex(name) == null) return self.failName(error.NoSuchField, t, name);
                _ = try self.check2(into.activate(name), t);
            },
            else => return self.fail(error.TypeMismatch, t),
        }
    }

    /// A whole number is read as one, so a `u64` too big for a float's
    /// precision still arrives exactly; anything with a point or an exponent
    /// is read as a float.
    fn numberInto(self: *Reader, into: Value) Error!void {
        const t = into.type;
        const rest = self.source[self.at..];
        const float = number.scanFloat(f128, rest, .{}) catch null;
        if (scanWhole(rest)) |whole| {
            if (float == null or whole.len >= float.?.len) {
                try self.check(into.setInt(whole.value), t);
                self.at += whole.len;
                return;
            }
        }
        const read = float orelse return self.fail(error.Syntax, t);
        try self.check(into.setFloat(read.value), t);
        self.at += read.len;
    }

    fn scanWhole(rest: []const u8) ?number.Scanned(i129) {
        if (rest.len > 0 and rest[0] == '-') {
            const n = number.scanInt(i128, rest, .{}) catch return null;
            return .{ .value = n.value, .len = n.len };
        }
        const n = number.scanInt(u128, rest, .{}) catch return null;
        return .{ .value = n.value, .len = n.len };
    }

    fn string(self: *Reader, into: Value) Error!void {
        const t = into.type;
        const spelt = try self.quoted(t);
        const size = strings.unescapedLen(spelt) catch |err| return self.fail(err, t);
        switch (t.kind) {
            .array => {
                if (!t.isString() or into.is_bit_field) return self.fail(error.TypeMismatch, t);
                if (size > t.info.array.len) return self.fail(error.OutOfRange, t);
                const out: [*]u8 = @ptrCast(into.ptr);
                _ = strings.unescape(spelt, out[0..size]);
                @memset(out[size..t.info.array.len], 0);
            },
            .slice, .pointer => {
                if (!t.isString()) return self.fail(error.TypeMismatch, t);
                const gpa = self.options.allocator orelse return self.fail(error.OutOfMemory, t);
                const bytes = gpa.allocSentinel(u8, size, 0) catch return self.fail(error.OutOfMemory, t);
                _ = strings.unescape(spelt, bytes);
                return self.check(into.setStringZ(bytes), t);
            },
            .@"enum", .error_set => {
                var buffer: [256]u8 = undefined;
                if (size > buffer.len) return self.fail(error.NoSuchMember, t);
                return self.check(into.setString(buffer[0..strings.unescape(spelt, buffer[0..size])]), t);
            },
            else => return self.fail(error.TypeMismatch, t),
        }
    }

    // ---------------------------------------------------------------------
    // `.{ ... }`
    // ---------------------------------------------------------------------

    fn aggregate(self: *Reader, into: Value, depth: usize) Error!void {
        const t = into.type;
        switch (t.kind) {
            .@"struct" => {
                if (t.info.@"struct".is_tuple) return self.items(into, depth);
                return self.entries(into, depth);
            },
            .@"union" => {
                if (self.eat('}')) return self.fail(error.InactiveArm, t);
                try self.expect('.', t);
                const name = self.identifier() orelse return self.fail(error.Syntax, t);
                if (t.fieldIndex(name) == null) return self.failName(error.NoSuchField, t, name);
                try self.expect('=', t);
                const inside = try self.check2(into.activate(name), t);
                try self.value(inside, depth + 1);
                _ = self.eat(',');
                return self.expect('}', t);
            },
            .array, .vector => return self.items(into, depth),
            .slice => return self.slice(into, depth),
            else => return self.fail(error.TypeMismatch, t),
        }
    }

    fn entries(self: *Reader, into: Value, depth: usize) Error!void {
        const t = into.type;
        while (!self.eat('}')) {
            try self.expect('.', t);
            const name = self.identifier() orelse return self.fail(error.Syntax, t);
            const f = t.field(name) orelse return self.failName(error.NoSuchField, t, name);
            if (f.is_comptime) return self.fail(error.ReadOnly, t);
            try self.expect('=', t);
            try self.value(try self.check2(into.field(name), t), depth + 1);
            if (!self.eat(',')) return self.expect('}', t);
        }
    }

    fn items(self: *Reader, into: Value, depth: usize) Error!void {
        const t = into.type;
        const count = into.len() catch return self.fail(error.TypeMismatch, t);
        var i: usize = 0;
        while (!self.eat('}')) : (i += 1) {
            if (i >= count) return self.fail(error.IndexOutOfBounds, t);
            if (t.kind == .vector) {
                try self.element(into, i, depth);
            } else {
                try self.value(try self.check2(into.index(i), t), depth + 1);
            }
            if (!self.eat(',')) {
                try self.expect('}', t);
                i += 1;
                break;
            }
        }
        if (i != count) return self.fail(error.IndexOutOfBounds, t);
    }

    fn element(self: *Reader, into: Value, i: usize, depth: usize) Error!void {
        const child = into.type.info.vector.child;
        if (into.index(i)) |item| return self.value(item, depth + 1) else |_| {}
        var buffer: [16]u8 align(16) = @splat(0);
        if (child.size > buffer.len) return self.fail(error.Unsupported, into.type);
        const item: Value = .init(child, &buffer);
        try self.check(into.getElement(i, item), into.type);
        try self.value(item, depth + 1);
        try self.check(into.setElement(i, item), into.type);
    }

    fn slice(self: *Reader, into: Value, depth: usize) Error!void {
        const t = into.type;
        const child = t.info.slice.child;
        const count = try self.countItems(t);
        if (count == 0) {
            _ = self.eat('}');
            return self.check(into.setSliceRaw(null, 0), t);
        }
        const gpa = self.options.allocator orelse return self.fail(error.OutOfMemory, t);
        const sentinel = t.info.slice.sentinel;
        const bytes = count * child.size + if (sentinel != null) child.size else 0;
        const memory = gpa.rawAlloc(@max(bytes, 1), .fromByteUnits(child.alignment), @returnAddress()) orelse
            return self.fail(error.OutOfMemory, t);
        const start: [*]u8 = memory;
        const initial: ?[*]const u8 = if (child.default) |d| @ptrCast(d) else null;
        for (0..count) |i| {
            const at = start + i * child.size;
            if (initial) |d| @memcpy(at[0..child.size], d[0..child.size]) else @memset(at[0..child.size], 0);
        }
        if (sentinel) |end| @memcpy((start + count * child.size)[0..child.size], @as([*]const u8, @ptrCast(end))[0..child.size]);
        for (0..count) |i| {
            try self.value(.init(child, @ptrCast(start + i * child.size)), depth + 1);
            if (!self.eat(',')) {
                try self.expect('}', t);
                break;
            }
        } else try self.expect('}', t);
        return self.check(into.setSliceRaw(@ptrCast(start), count), t);
    }

    /// How many items a `.{ ... }` holds, found without reading them.
    fn countItems(self: *Reader, t: *const Type) Error!usize {
        const saved = self.at;
        defer self.at = saved;
        var count: usize = 0;
        var nesting: usize = 0;
        var any = false;
        while (self.at < self.source.len) : (self.at += 1) {
            const c = self.source[self.at];
            switch (c) {
                '"' => {
                    _ = try self.quoted(t);
                    self.at -= 1;
                    any = true;
                },
                '{', '(' => {
                    nesting += 1;
                    any = true;
                },
                ')' => nesting -|= 1,
                '}' => {
                    if (nesting == 0) return count + @intFromBool(any);
                    nesting -= 1;
                },
                ',' => if (nesting == 0) {
                    if (any) count += 1;
                    any = false;
                },
                ' ', '\t', '\n', '\r' => {},
                '/' => if (std.mem.startsWith(u8, self.source[self.at..], "//")) {
                    self.at = (std.mem.indexOfScalarPos(u8, self.source, self.at, '\n') orelse self.source.len) - 1;
                } else {
                    any = true;
                },
                else => any = true,
            }
        }
        return self.fail(error.Syntax, t);
    }
};
