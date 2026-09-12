# Fluxion Reflect

Zig types, read and written at run time - from Zig and from C, on every
platform Fluxion runs on, the browser included. For Zig 0.16.

| Piece | What it is |
| --- | --- |
| `typeOf(T)` → `Type` | A descriptor of any Zig type, made at compile time and kept in the binary: fields and offsets, enum members, union arms, methods, defaults, attributes. |
| `Value` | A descriptor and an address: read, write, convert, walk into, compare, hash, print and parse a value whose type is known only at run time. |
| `Registry` | Types by name and by id, types built from their Zig spelling (`[]const Vec2`), types described from C, functions by name. |
| `json` | Values as JSON and CBOR through [Fluxion JSON](https://github.com/kisstp2006/fluxion-json), spelt exactly as it spells the Zig type. |
| `attr` | Attributes worth one spelling: `Range`, `Doc`, `Label`, `Hidden`, `ReadOnly`. |
| `c` | The C API in [`include/fluxion_reflect.h`](include/fluxion_reflect.h) - a header per part under [`include/fluxion_reflect/`](include/fluxion_reflect) - over the same descriptors. |

Zig's reflection happens at compile time and is gone by the time the program
runs. An inspector, a console, a scene file, a script binding or a plugin
needs it afterwards, for types it was not compiled against. This turns what
`@typeInfo` knows into data - and because that data is laid out as C lays it
out, a C program reads the same descriptors, and can describe its own.

```zig
const reflect = @import("fluxion_reflect");

var player: Player = .{};
const v = reflect.Value.of(&player);

try (try v.path("stats.health")).setFloat(80);           // by name, at run time
try v.parse(".{ .name = \"Grace\", .team = .blue }", .{}); // as a console types it
try v.call("heal", &.{.of(&amount)}, null);                // a method, by name
std.debug.print("{f}\n", .{v});                            // .{ .name = "Grace", ... }

const text = try reflect.json.stringify(gpa, v, .{ .indent = 2 });
```

## Install

```bash
zig fetch --save git+https://github.com/kisstp2006/fluxion-reflect
```

Or, for a checkout next to your project, add to `build.zig.zon`:

```zig
.dependencies = .{
    .fluxion_reflect = .{ .path = "../fluxion-reflect" },
},
```

Either way, wire it up in `build.zig`:

```zig
const fluxion = b.dependency("fluxion_reflect", .{
    .target = target,
    .optimize = optimize,
});
exe_mod.addImport("fluxion_reflect", fluxion.module("fluxion_reflect"));
```

A C program links the static library instead, which `zig build` installs
with the header into `zig-out/lib` and `zig-out/include`.

Three dependencies come with it, fetched the same way and needing nothing
from you: [Fluxion Hash](https://github.com/kisstp2006/fluxion-hash),
[Fluxion Text](https://github.com/kisstp2006/fluxion-text) and
[Fluxion JSON](https://github.com/kisstp2006/fluxion-json). What each is for
is at the end.

## Describing a type

```zig
const t = reflect.typeOf(Player);   // *const reflect.Type
t.name.slice();                     // "game.Player", or its reflect_name
t.size;                             // @sizeOf(Player)
for (t.fields()) |f| {
    // f.name, f.type, f.offset, f.default, f.attributes
}
t.field("health").?.type.kind;      // .float
```

A descriptor is the address of a constant made for that one type, so it
costs nothing to ask for and asking twice gives the same pointer. It points
at the descriptors of the types inside it, and a type that points at itself -
a list node's `?*Node` - closes into a cycle, the way the type itself does.

Every kind a value can have at run time is described: integers of any width,
floats, pointers of every size, slices, arrays, vectors, structs (auto,
`extern` and `packed`, tuples too), enums, unions (tagged, bare, `extern`,
`packed`), optionals, error unions and sets, function types, opaques. A
`type` that has to exist at run time - in a comptime field, in an attribute -
becomes a `*const Type`, of kind `.type`.

**Where Zig does not fix a layout, the descriptor carries a small function
that knows it.** Where a `?T` keeps its flag, where a tagged union keeps its
tag, what a slice is made of: Zig chooses per type and says nothing, so
guessing would be a bug on the next compiler. Each such type gets a handful of
functions made for it alone, called through the C calling convention so they
work the same from C. Everything with a fixed layout - integers, structs,
arrays, `extern` anything - is read by offset.

A type shapes its descriptor with declarations, as fluxion-json's `json_*`
ones shape its JSON:

```zig
const Player = struct {
    name: []const u8 = "Ada",
    health: f32 = 100,
    cache: u32 = 0,

    pub const reflect_name = "Player";   // stable across moving the file
    pub const reflect_attributes = .{attr.Doc{ .text = "Someone in the game" }};
    pub const reflect_fields = .{
        .health = .{ attr.Range{ .min = 0, .max = 200 } },
        .cache = .{attr.Hidden{}},
    };
    pub const reflect_methods = .{ .heal, .respawn };   // or .{ .heal = .{attr.Doc{...}} }

    pub fn heal(self: *Player, amount: f32) f32 { ... }
    pub fn respawn(self: *Player) void { ... }
};
```

- **`reflect_name`** is the name, and the name is the identity: `Type.id` is
  it hashed, the same number in every build and on every machine, which is
  what a file or a network message can refer to. Without one it is
  `@typeName`, which changes when the type moves to another file.
- **`reflect_fields`** is checked: naming a field the type does not have is a
  compile error, not a silent nothing.
- **Attributes are values of any type**, found by their type:
  `t.field("health").?.attribute(attr.Range)`. Anonymous ones work too - a
  `comptime_int` becomes an `i64`, an enum literal its name, a `type` its
  descriptor.
- **Methods are opt-in.** Listing every public function would compile every
  one of them, and every function they reach, into every program that
  reflects the type.
- **`reflect_opaque = true`** stops the description there: size and name, no
  insides. For a type whose insides are nobody's business.

## Values

```zig
const v = reflect.Value.of(&player);            // through a *const T it is read-only
const hp = try v.field("health");               // a Value too
try hp.setFloat(80);                            // or setInt, setBool, setString
hp.toFloat(f64);                                // ?f64: converted where nothing is lost
hp.get(f32);                                    // ?f32: exactly this type or nothing
try (try v.path("inventory[2].name")).setString("rope");
```

Paths are Zig's own syntax: `.field`, `[i]`, `.?` to unwrap, `.*` to
dereference, and a pointer to one value followed on the way as Zig follows it,
so `owner.name` reads through `owner: *Player`. When one fails,
`reflect.explainPath` says why in words, with the name that was probably
meant:

```
stats is a game.Stats, which has no field helth - did you mean health?
```

What a `Value` does with each kind, briefly:

| | |
| --- | --- |
| numbers | `setInt` and `setFloat` convert, and refuse what does not fit: 300 into a `u8`, 1.5 into an integer |
| enums | by member name or by number; a number no member has is refused unless the enum is non-exhaustive |
| packed structs | their fields are bit fields: read and written in place, a bit at a time, on either endianness |
| optionals | `isNull`, `unwrap`, `unwrapOrInit` (made from the payload's default), `setNull` |
| tagged unions | `active`, `payload`, `activate("arm")` - another arm's field is refused, not read |
| error unions | `unwrap`, `errorName`, `setError("NotFound")` |
| slices | `len`, `index`, `setSliceRaw`; a `[]const u8` is text |
| vectors | `index` where items are whole bytes, `getElement` and `setElement` everywhere |

`Value.create(gpa, t)` makes a new one on the heap holding the type's default:
its declared field defaults, then zero, false, null, empty, an enum's first
member.

`eql` and `hash` compare what the value holds - field by field, slices by
their items, single pointers by what they point at, floats by their bits -
and `hash` gives the number [Fluxion Hash](https://github.com/kisstp2006/fluxion-hash)'s
`hashValue` gives the Zig value, so a value hashes the same whether it is
reached through reflection or not.

## Text

`{f}` writes a value as ZON writes it, and `parse` reads it back:

```zig
std.debug.print("{f}\n", .{v});
// .{ .name = "Ada", .health = 100, .team = .red, .target = null }

try v.parse(".{ .health = 50, .team = blue }", .{});   // only the fields it names change
```

Numbers in any base with underscores, `inf` and `nan`, strings with Zig's
escapes, enum literals with or without the dot, `error.Name`, `null`,
`@enumFromInt(7)`. Strings and slices read into a slice need an allocator:
pass an arena as `.allocator`. With `.diagnostics`, a failure says where, and
suggests the name that was meant.

## Calling

```zig
var amount: f32 = 25;
var healed: f32 = undefined;
try v.call("heal", &.{.of(&amount)}, .of(&healed));
```

Arguments are values. One of the parameter's type is passed as it is; where
the parameter is a pointer to it - `self: *Player` - it is passed by address;
numbers, bools and enums are converted to the parameter's kind; text goes to
a `[]const u8`. A read-only value is refused where a `*T` is wanted. The
function is called through a small function generated for its type, so a
function pointer stored in a field can be called the same way:
`fieldValue.callPointer(args, result)`.

## A registry

```zig
var registry: reflect.Registry = .init(gpa);
defer registry.deinit();
_ = try registry.add(Player);

registry.find("Player");                  // by name
registry.findId(id);                      // by the number a file stored
try registry.resolve("[]const Player");   // built from its Zig spelling
registry.suggest("Plyer");                // "Player"
_ = try registry.addFunction("spawn", spawn);
```

`resolve` builds pointers, slices, arrays and optional pointers of any
registered or primitive type, and names them as the compiler would, so the
built descriptor is the `same` as the one `typeOf` makes for that type. C's
names for the primitives work too: `int`, `float`, `uint16_t`, `size_t`.

Types with no Zig type behind them are described from their layout -
`defineStruct`, `defineEnum`, `defineUnion` - and functions from their
parameter types and an `invoke` that calls them: `defineFunction`. That is
what the C API does for a C program.

Build a registry at startup and read it from anywhere afterwards: nothing is
locked, and only `resolve` changes anything after that.

## JSON and CBOR

```zig
const text = try reflect.json.stringify(gpa, v, .{ .indent = 2 });
try reflect.json.parse(v, text, .{ .allocator = arena });
```

Through [Fluxion JSON](https://github.com/kisstp2006/fluxion-json)'s own
`Writer` and `Reader`, and spelt exactly as it spells the Zig type: the tests
check the text and the CBOR bytes against its `stringify`, for every option,
over hundreds of random values. Its `json_rename`, `json_case`,
`json_ignore` and `json_tag` declarations are honoured - the compiler turns
them into attributes on the descriptor - and a field the text leaves out
takes its default, as `parseAs` gives it, unless `.patch = true` keeps what it
held.

What only compile time can do is refused with `error.Unsupported` rather than
done differently: a type with `toJson` or `fromJson`, and a hash map.

## Fingerprints

`t.fingerprint()` is the number [Fluxion Data](https://github.com/kisstp2006/fluxion-data)
writes at the head of its files, and `t.describe(w)` the text it hashes -
the same, for every type that library writes, and the tests check that. So a
program can tell whether a file holds a type it only met at run time. Past
what fluxion-data writes, the grammar goes on in the same spirit: a pointer
is `*` and the name of what it points at.

## From C

```c
#include "fluxion_reflect.h"

typedef struct Vec2 { float x, y; } Vec2;

fxr_registry *registry = fxr_registry_create();
const fxr_type *f32 = fxr_registry_find(registry, "float");
const fxr_field_desc fields[] = { FXR_FIELD(Vec2, x, f32), FXR_FIELD(Vec2, y, f32) };
const fxr_struct_desc desc = FXR_STRUCT(Vec2, "Vec2", fields);
const fxr_type *vec2;
fxr_registry_define_struct(registry, &desc, &vec2);

Vec2 at = {0};
fxr_value v = fxr_value_make(vec2, &at), y;
fxr_value_path(&v, "y", &y);
fxr_value_set_f64(&y, 2.5);                      /* at.y == 2.5f */

char text[64];
fxr_value_format(&v, text, sizeof text);         /* .{ .x = 0, .y = 2.5 } */
```

**The descriptors are the same bytes on both sides.** Every struct in the
header is laid out as its Zig counterpart, and the suite measures every size,
alignment and offset in C and in Zig and compares them, on each target it
builds for. So C reads `type->info.structure.fields` directly, and a Zig
program hands a `reflect.typeOf(Player)` to C code as it is.

Everything else the Zig API does, the C API does: paths, conversions,
unions and optionals, calls, the registry, text, JSON and CBOR. Functions
return an `fxr_status`; text comes out `snprintf`-style, into a buffer the
caller owns, with the full length returned; strings and slices read in are
allocated from an `fxr_arena` the caller owns. Only `<stdbool.h>`,
`<stddef.h>` and `<stdint.h>` are needed, so the header works with no C
library - in a browser build.

A Zig program with C code beside it puts the functions in its binary with
`comptime { _ = reflect.c; }`.

## Platforms

Nothing here touches an operating system - no files, no threads, no clock -
so it runs wherever Zig does. The suite has been run, not just built, on:

| Target | How |
| --- | --- |
| `x86_64-windows`, `x86-windows` | natively |
| `x86_64-linux-gnu`, `x86-linux-gnu` | WSL - the 32-bit one is where C puts a `uint64_t` in a struct at a four-byte boundary, which the layout check is for |
| `x86_64-linux-android` | the Android emulator, API 35 with 16 KB pages |
| `wasm32-freestanding` | the browser build, run in Node with nothing imported |
| `wasm32-wasi` | the whole suite, in Node's WASI (`zig build test-wasm`) |

It is built for `aarch64` and `arm` Linux and Android, `aarch64` Windows,
`x86_64` and `aarch64` macOS, `riscv64`, and big-endian `powerpc64` Linux,
where the bit fields' byte order has been compiled but not run.

## Limits worth knowing

- **Descriptors are data.** Every type reflected, and every type inside it,
  is a few hundred bytes in the binary, with its default value beside it.
- **`same` is by name.** Two descriptors of one type - from two copies of this
  library, or two binaries - are the same when their name, kind and size
  are. A `reflect_name` given to two types is a clash, which `Registry.add`
  refuses.
- **Error numbers belong to one binary.** An error's name is what travels;
  `anyerror` lists no names, so `setError` needs a named error set.
- **A many-item pointer has no length**, so it is not indexed, followed or
  written out - except as text when it ends in a zero.
- **A bare `union`** does not say which arm is live, so its fields are
  refused; `activate` chooses one. An `extern` union's arms all overlap and
  all read.
- **Borrowed, not copied.** `setString` points a `[]const u8` at the text it
  was given, as Zig would; `parse` and `json.parse` copy into the allocator.

## What it is built on

| | Used for |
| --- | --- |
| [Fluxion Hash](https://github.com/kisstp2006/fluxion-hash) | `Type.id` (xxHash of the name), `fingerprint` (of the schema text, streamed), and `Value.hash`, which agrees with its `hashValue` |
| [Fluxion Text](https://github.com/kisstp2006/fluxion-text) | numbers read from text, and every "did you mean" |
| [Fluxion JSON](https://github.com/kisstp2006/fluxion-json) | `reflect.json`: its `Writer` and `Reader`, JSON text and CBOR |
| [Fluxion Data](https://github.com/kisstp2006/fluxion-data) | only in the tests, fetched lazily: that the fingerprints agree with the ones in its files |

Looked at and not needed: Fluxion Dyn (plugins are the obvious next use - a
game library hands its descriptors to an editor through the C ABI - but that
is the caller's `dlopen`, not this library's), Fluxion Id (a name hashed is
the identity; a random UUID would not survive a rebuild), Fluxion Mem and
Fluxion Encoding (the standard arena and fluxion-json's CBOR cover it).

## Where things are

A file does one job, and one that grew past a few hundred lines became a
directory beside the file that keeps its name - as `std/Build.zig` and
`std/Build/` do.

| | |
| --- | --- |
| [`src/model.zig`](src/model.zig) | What a descriptor holds: `Type`, `Field`, `info.*` - the structs C shares |
| [`src/generate.zig`](src/generate.zig) | Descriptors made at compile time; under [`generate/`](src/generate), the `reflect_*` and `json_*` declarations, the defaults, and the thunks for the layouts Zig does not fix |
| [`src/value.zig`](src/value.zig) | `Value`; under [`value/`](src/value), numbers, truth and text in `scalars.zig`, fields, items, pointers and optionals in `inside.zig` |
| [`src/path.zig`](src/path.zig), [`call.zig`](src/call.zig), [`hash.zig`](src/hash.zig), [`bits.zig`](src/bits.zig) | Paths, calls, `eql` and `hash`, and the bits under a scalar |
| [`src/text.zig`](src/text.zig) | Zig syntax; [`text/`](src/text) writes it, reads it, and spells string literals both ways |
| [`src/json.zig`](src/json.zig) | JSON and CBOR; [`json/`](src/json) writes and reads |
| [`src/Registry.zig`](src/Registry.zig) | The registry; [`Registry/make.zig`](src/Registry/make.zig) makes the descriptors it builds at run time |
| [`src/schema.zig`](src/schema.zig), [`attr.zig`](src/attr.zig) | `describe` and `fingerprint`; the shared attributes |
| [`src/c.zig`](src/c.zig) | The C API; [`c/`](src/c) has a file for each header under [`include/fluxion_reflect/`](include/fluxion_reflect) |
| `src/*_test.zig`, [`tests/`](tests) | The suite, a file per part; [`tests/c/`](tests/c) is the C half of the C API's test, a file per header |

## Build

```bash
zig build              # the C library and header, and the browser check, into zig-out
zig build test         # the suite, the C API from C, and the browser build compiled
zig build test-wasm    # the suite again, as WebAssembly under Node
zig build test-bin     # the test binaries into zig-out/test, to run elsewhere
zig build example      # a tour in Zig
zig build example-c    # a C program describing its own types
zig build docs         # API docs into zig-out/docs
node tests/web.mjs     # after zig build: the browser build's self-check
```

## Requirements

Zig 0.16.0. Node for `test-wasm` and `tests/web.mjs`.

## Licence

`SPDX-License-Identifier: BSL-1.0`

[Boost Software License 1.0](LICENSE) - use it, change it, ship it, in
anything. The one obligation is that the copyright notice and the licence
text travel with the *source*; a binary built from it carries nothing.

Fluxion libraries are licensed by layer: the foundation is CC0, the engine
infrastructure this one belongs to is BSL-1.0 - it builds on three CC0
libraries - and what builds on top of it is BSD.
