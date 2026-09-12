// SPDX-License-Identifier: BSL-1.0

const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = reflectModule(b, target, optimize);

    // The C library: `zig build` installs it with the header, for a program
    // written in C to link.
    const lib = b.addLibrary(.{
        .name = "fluxion_reflect",
        .linkage = .static,
        .root_module = cLibraryModule(b, mod, target, optimize),
    });
    lib.installHeadersDirectory(b.path("include"), "", .{});
    b.installArtifact(lib);

    const test_step = b.step("test", "Run the test suite");
    const test_bin_step = b.step("test-bin", "Build the test binaries into zig-out/test, to run on another machine");
    const suites = [_]*std.Build.Step.Compile{
        b.addTest(.{ .name = "fluxion-reflect-tests", .root_module = mod }),
        b.addTest(.{ .name = "fluxion-reflect-c-tests", .root_module = cTestModule(b, mod, target, optimize) }),
    };
    for (suites) |suite| {
        // Android 15 devices page memory 16 KB at a time, and refuse to load
        // a program aligned for 4 KB.
        if (target.result.abi.isAndroid()) suite.link_z_max_page_size = 16384;
        test_step.dependOn(&b.addRunArtifact(suite).step);
        test_bin_step.dependOn(&b.addInstallArtifact(suite, .{ .dest_dir = .{ .override = .{ .custom = "test" } } }).step);
    }
    test_step.dependOn(&wasmCheck(b).step);

    // The same suite under WebAssembly: built for wasm32-wasi and run by
    // Node, which is what a browser build is short of only the page.
    const wasi_step = b.step("test-wasm", "Run the test suite as WebAssembly, under Node");
    const wasi = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .wasi });
    const wasi_mod = reflectModule(b, wasi, optimize);
    for ([_]*std.Build.Module{ wasi_mod, cTestModule(b, wasi_mod, wasi, optimize) }, [_][]const u8{ "fluxion-reflect-tests", "fluxion-reflect-c-tests" }) |m, name| {
        const run = b.addSystemCommand(&.{ "node", "--no-warnings" });
        run.addFileArg(b.path("tests/wasi.mjs"));
        run.addArtifactArg(b.addTest(.{ .name = name, .root_module = m }));
        wasi_step.dependOn(&run.step);
    }

    const docs_lib = b.addLibrary(.{ .name = "fluxion-reflect", .root_module = mod });
    const install_docs = b.addInstallDirectory(.{
        .source_dir = docs_lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.step("docs", "Generate API documentation into zig-out/docs").dependOn(&install_docs.step);

    const examples_wanted = b.option(
        bool,
        "examples",
        "Build the examples, and the test against fluxion-data (pulls fluxion-data)",
    ) orelse (b.pkg_hash.len == 0);
    if (!examples_wanted) return;

    const demo_mod = b.createModule(.{
        .root_source_file = b.path("examples/demo.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fluxion_reflect", .module = mod }},
    });
    const demo = b.addExecutable(.{ .name = "fluxion-reflect-demo", .root_module = demo_mod });
    b.installArtifact(demo);
    const run_demo = b.addRunArtifact(demo);
    run_demo.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_demo.addArgs(args);
    b.step("example", "A tour: descriptors, values, paths, text, calls, the registry, JSON").dependOn(&run_demo.step);
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{
        .name = "fluxion-reflect-demo-tests",
        .root_module = demo_mod,
    })).step);

    const c_demo_mod = b.createModule(.{ .target = target, .optimize = optimize, .link_libc = true });
    c_demo_mod.addCSourceFile(.{ .file = b.path("examples/c_demo.c"), .flags = c_flags });
    c_demo_mod.linkLibrary(lib);
    const c_demo = b.addExecutable(.{ .name = "fluxion-reflect-c-demo", .root_module = c_demo_mod });
    b.installArtifact(c_demo);
    const run_c_demo = b.addRunArtifact(c_demo);
    run_c_demo.step.dependOn(b.getInstallStep());
    b.step("example-c", "A C program describing its own types and reading them back").dependOn(&run_c_demo.step);

    const data = b.lazyDependency("fluxion_data", .{ .target = target, .optimize = optimize }) orelse return;
    test_step.dependOn(&b.addRunArtifact(b.addTest(.{
        .name = "fluxion-reflect-data-tests",
        .root_module = b.createModule(.{
            .root_source_file = b.path("tests/data_compat.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "fluxion_reflect", .module = mod },
                .{ .name = "fluxion_data", .module = data.module("fluxion_data") },
            },
        }),
    })).step);
}

fn reflectModule(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const hash = b.dependency("fluxion_hash", .{ .target = target, .optimize = optimize });
    const text = b.dependency("fluxion_text", .{ .target = target, .optimize = optimize });
    const json = b.dependency("fluxion_json", .{ .target = target, .optimize = optimize });
    const imports: []const std.Build.Module.Import = &.{
        .{ .name = "fluxion_hash", .module = hash.module("fluxion_hash") },
        .{ .name = "fluxion_text", .module = text.module("fluxion_text") },
        .{ .name = "fluxion_json", .module = json.module("fluxion_json") },
    };
    const options: std.Build.Module.CreateOptions = .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
        .imports = imports,
    };
    // Only the module built for the target asked for is the one consumers
    // import; the others are the same source built for the tests' targets.
    if (b.modules.get("fluxion_reflect") == null) return b.addModule("fluxion_reflect", options);
    return b.createModule(options);
}

/// The root of the C library: a module whose only job is to reach
/// `reflect.c`, which is what puts its exported functions in the archive.
fn cLibraryModule(b: *std.Build, reflect: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    return b.createModule(.{
        .root_source_file = b.addWriteFiles().add("fluxion_reflect_c.zig",
            \\comptime {
            \\    _ = @import("fluxion_reflect").c;
            \\}
        ),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fluxion_reflect", .module = reflect }},
    });
}

const c_flags: []const []const u8 = &.{ "-std=c11", "-Wall", "-Wextra", "-Werror" };

/// The C half of the C API test, one file for each header it tests.
fn addCTest(b: *std.Build, m: *std.Build.Module) void {
    m.addIncludePath(b.path("include"));
    m.addCSourceFiles(.{
        .root = b.path("tests/c"),
        .files = &.{ "check.c", "describe.c", "types.c", "values.c", "calls.c", "json.c", "registry.c", "layouts.c", "run.c" },
        .flags = c_flags,
    });
}

/// The C API from C: `tests/c` beside the Zig half that calls it.
fn cTestModule(b: *std.Build, reflect: *std.Build.Module, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode) *std.Build.Module {
    const m = b.createModule(.{
        .root_source_file = b.path("tests/c_api.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "fluxion_reflect", .module = reflect }},
    });
    addCTest(b, m);
    return m;
}

/// The library and its C API built for a browser, with the C half of the C
/// test beside them, so a change that would not compile for
/// `wasm32-freestanding` fails the suite rather than a page.
fn wasmCheck(b: *std.Build) *std.Build.Step.Compile {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .freestanding });
    const reflect = reflectModule(b, target, .ReleaseSmall);
    const m = b.createModule(.{
        .root_source_file = b.path("tests/wasm_check.zig"),
        .target = target,
        .optimize = .ReleaseSmall,
        .imports = &.{.{ .name = "fluxion_reflect", .module = reflect }},
    });
    addCTest(b, m);
    const check = b.addExecutable(.{ .name = "fluxion-reflect-wasm-check", .root_module = m });
    check.entry = .disabled;
    check.rdynamic = true;
    b.getInstallStep().dependOn(&b.addInstallArtifact(check, .{ .dest_dir = .{ .override = .{ .custom = "web" } } }).step);
    return check;
}
