// SPDX-License-Identifier: BSL-1.0

//! Zig string literals, both ways: bytes written as one, and one read back
//! into bytes.

const std = @import("std");
const Writer = std.Io.Writer;

const Error = @import("../value.zig").Error;

/// Whether a `u8` array holds text, zero-padded, rather than numbers: a name
/// kept in place is written as a string, an array of ids as a list.
pub fn isText(bytes: []const u8) bool {
    const used = std.mem.trimEnd(u8, bytes, "\x00");
    if (!std.unicode.utf8ValidateSlice(used)) return false;
    for (used) |c| if ((c < 0x20 and c != '\t' and c != '\n' and c != '\r') or c == 0x7f) return false;
    return true;
}

/// Escaped as Zig escapes a string, except that text in other scripts is
/// left as it is rather than spelt out a byte at a time.
pub fn writeString(bytes: []const u8, w: *Writer) Writer.Error!void {
    try w.writeByte('"');
    var i: usize = 0;
    while (i < bytes.len) {
        const c = bytes[i];
        if (c >= 0x80) {
            const n = std.unicode.utf8ByteSequenceLength(c) catch 0;
            if (n > 0 and i + n <= bytes.len and std.unicode.utf8ValidateSlice(bytes[i..][0..n])) {
                try w.writeAll(bytes[i..][0..n]);
                i += n;
                continue;
            }
        }
        try std.zig.stringEscape(bytes[i..][0..1], w);
        i += 1;
    }
    try w.writeByte('"');
}

pub fn unescapedLen(quoted: []const u8) Error!usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < quoted.len) {
        if (quoted[i] != '\\') {
            n += 1;
            i += 1;
            continue;
        }
        if (i + 1 >= quoted.len) return error.Syntax;
        switch (quoted[i + 1]) {
            'n', 'r', 't', '\\', '"', '\'' => {
                n += 1;
                i += 2;
            },
            'x' => {
                if (i + 4 > quoted.len) return error.Syntax;
                _ = std.fmt.parseUnsigned(u8, quoted[i + 2 .. i + 4], 16) catch return error.Syntax;
                n += 1;
                i += 4;
            },
            'u' => {
                const close = std.mem.indexOfScalarPos(u8, quoted, i, '}') orelse return error.Syntax;
                if (i + 2 >= quoted.len or quoted[i + 2] != '{') return error.Syntax;
                const codepoint = std.fmt.parseUnsigned(u21, quoted[i + 3 .. close], 16) catch return error.Syntax;
                n += std.unicode.utf8CodepointSequenceLength(codepoint) catch return error.Syntax;
                i = close + 1;
            },
            else => return error.Syntax,
        }
    }
    return n;
}

/// Writes what `quoted` spells into `out`, which `unescapedLen` sized.
pub fn unescape(quoted: []const u8, out: []u8) usize {
    var n: usize = 0;
    var i: usize = 0;
    while (i < quoted.len) {
        if (quoted[i] != '\\') {
            out[n] = quoted[i];
            n += 1;
            i += 1;
            continue;
        }
        switch (quoted[i + 1]) {
            'x' => {
                out[n] = std.fmt.parseUnsigned(u8, quoted[i + 2 .. i + 4], 16) catch unreachable;
                n += 1;
                i += 4;
            },
            'u' => {
                const close = std.mem.indexOfScalarPos(u8, quoted, i, '}').?;
                const codepoint = std.fmt.parseUnsigned(u21, quoted[i + 3 .. close], 16) catch unreachable;
                n += std.unicode.utf8Encode(codepoint, out[n..]) catch unreachable;
                i = close + 1;
            },
            else => |c| {
                out[n] = switch (c) {
                    'n' => '\n',
                    'r' => '\r',
                    't' => '\t',
                    else => c,
                };
                n += 1;
                i += 2;
            },
        }
    }
    return n;
}
