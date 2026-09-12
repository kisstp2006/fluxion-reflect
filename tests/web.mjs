// SPDX-License-Identifier: BSL-1.0

// Runs the browser build's self-check in Node: the module a page would load,
// with nothing imported, calling what a page would call.
//
//     zig build && node tests/web.mjs zig-out/web/fluxion-reflect-wasm-check.wasm

import { readFile } from "node:fs/promises";

const file = process.argv[2] ?? "zig-out/web/fluxion-reflect-wasm-check.wasm";
const { instance } = await WebAssembly.instantiate(await readFile(file), {});
const failures = instance.exports.check();
const bytes = new Uint8Array(instance.exports.memory.buffer, instance.exports.reportPtr(), instance.exports.reportLen());
process.stdout.write(new TextDecoder().decode(bytes));
console.log(failures === 0 ? "wasm32-freestanding: every check passed" : `wasm32-freestanding: ${failures} failed`);
process.exit(failures === 0 ? 0 : 1);
