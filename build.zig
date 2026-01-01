const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .emscripten });
    const optimize = b.standardOptimizeOption(.{});

    // Build as static library (Zig 0.12+/0.13 API)
    const lib = b.addLibrary(.{
        .name = "webgpu",
        .root_module = b.createModule(.{ .root_source_file = b.path("main.zig"), .target = target, .optimize = optimize }),
        .linkage = .static,
    });
    lib.linkLibC();

    // Get `--sysroot` from command line arguments
    var arg_sysroot: ?[]const u8 = null;
    if (b.sysroot) |sysroot| {
        arg_sysroot = sysroot;
    } else {
        std.log.err("Must provide Emscripten sysroot via '--sysroot [path/to/emsdk]/upstream/emscripten/cache/sysroot'", .{});
        return error.Wasm32SysRootExpected;
    }
    const emcc_include = b.pathJoin(&.{ arg_sysroot.?, "include" });
    lib.addSystemIncludePath(.{ .cwd_relative = emcc_include }); // isystem

    // Add WebGPU headers from emdawnwebgpu port
    // Extract emscripten root from sysroot path (remove /cache/sysroot)
    const emsdk_root = b.pathJoin(&.{ arg_sysroot.?, "..", ".." });
    const webgpu_include = b.pathJoin(&.{ emsdk_root, "cache", "ports", "emdawnwebgpu", "emdawnwebgpu_pkg", "webgpu", "include" });
    lib.addSystemIncludePath(.{ .cwd_relative = webgpu_include });

    // Define `emcc` executable name
    const emcc_exe = switch (builtin.os.tag) {
        .windows => "emcc.bat",
        else => "emcc",
    };

    // Link with Emscripten
    const emcc_cmd = b.addSystemCommand(&[_][]const u8{emcc_exe});
    emcc_cmd.addFileArg(lib.getEmittedBin());
    emcc_cmd.addArgs(&[_][]const u8{
        "-o",
        b.fmt("{s}.html", .{lib.name}),
        "-O0",
        "--shell-file=shell.html",
        "-sASYNCIFY",
        "--use-port=emdawnwebgpu",
    });
    emcc_cmd.step.dependOn(&lib.step);

    // `emcc` flags necessary for debug builds
    if (optimize == .Debug or optimize == .ReleaseSafe) {
        emcc_cmd.addArgs(&[_][]const u8{
            "-sASSERTIONS",
        });
    }

    b.getInstallStep().dependOn(&emcc_cmd.step);
}
