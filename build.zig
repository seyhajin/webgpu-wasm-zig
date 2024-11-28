const std = @import("std");
const builtin = @import("builtin");

pub fn build(b: *std.Build) !void {
    const target = b.resolveTargetQuery(.{ .cpu_arch = .wasm32, .os_tag = .emscripten });
    const optimize = b.standardOptimizeOption(.{});

    // Build as static library
    const lib = b.addStaticLibrary(.{
        .name = "webgpu",
        .root_source_file = b.path("main.zig"),
        .target = target,
        .optimize = optimize,
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
        "-Oz",
        "--shell-file=shell.html",
        "-sASYNCIFY",
        "-sUSE_WEBGPU=1",
    });
    emcc_cmd.step.dependOn(&lib.step);

    // `emcc` flags necessary for debug builds
    if (optimize == .Debug or optimize == .ReleaseSafe) {
        emcc_cmd.addArgs(&[_][]const u8{
            "-sUSE_OFFSET_CONVERTER",
            "-sASSERTIONS",
        });
    }

    b.getInstallStep().dependOn(&emcc_cmd.step);
}
