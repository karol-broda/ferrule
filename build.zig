const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("ferrule", .{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
    });

    const exe = b.addExecutable(.{
        .name = "ferrule",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{
                .{ .name = "ferrule", .module = mod },
            },
        }),
    });

    // link LLVM libraries for codegen
    exe.linkLibC();

    // nixos workaround: zig automatically adds -lc++ (libc++) but llvm is built with libstdc++
    // on nixos, directly link libstdc++ and libgcc from the nix store.
    // note: you may see harmless warnings about unrecognized -fmacro-prefix-map flags
    // from nix - these can be ignored, the build still succeeds.
    const gcc_lib_path = std.process.getEnvVarOwned(b.allocator, "NIX_LDFLAGS") catch null;
    var nix_workaround_applied = false;
    if (gcc_lib_path) |flags| {
        defer b.allocator.free(flags);
        // find the gcc lib directory from NIX_LDFLAGS
        var it = std.mem.tokenizeScalar(u8, flags, ' ');
        while (it.next()) |token| {
            if (std.mem.startsWith(u8, token, "-L") and std.mem.indexOf(u8, token, "gcc") != null) {
                const lib_path = token[2..];
                // directly link libstdc++.so
                const libstdcpp_path = b.fmt("{s}/libstdc++.so", .{lib_path});
                exe.addObjectFile(.{ .cwd_relative = libstdcpp_path });
                // also link libgcc for unwind symbols
                const libgcc_path = b.fmt("{s}/libgcc_s.so.1", .{lib_path});
                exe.addObjectFile(.{ .cwd_relative = libgcc_path });
                nix_workaround_applied = true;
                break;
            }
        }
    }

    // for non-nixos systems, use standard c++ library linking
    if (!nix_workaround_applied) {
        exe.linkLibCpp();
    }

    // link individual LLVM component libraries
    exe.linkSystemLibrary("LLVMCore");
    exe.linkSystemLibrary("LLVMSupport");
    exe.linkSystemLibrary("LLVMIRReader");
    exe.linkSystemLibrary("LLVMBitWriter");
    exe.linkSystemLibrary("LLVMRemarks");
    exe.linkSystemLibrary("LLVMBitstreamReader");
    exe.linkSystemLibrary("LLVMBinaryFormat");
    exe.linkSystemLibrary("LLVMTargetParser");
    exe.linkSystemLibrary("LLVMDemangle");

    // link ncurses for terminal support
    exe.linkSystemLibrary("ncurses");

    b.installArtifact(exe);

    // lsp server executable
    const lsp_exe = b.addExecutable(.{
        .name = "ferrule-lsp",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/lsp_server.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });
    b.installArtifact(lsp_exe);

    const run_step = b.step("run", "Run the app");
    const run_cmd = b.addRunArtifact(exe);
    run_step.dependOn(&run_cmd.step);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const mod_tests = b.addTest(.{
        .root_module = mod,
    });
    const run_mod_tests = b.addRunArtifact(mod_tests);

    const exe_tests = b.addTest(.{
        .root_module = exe.root_module,
    });
    const run_exe_tests = b.addRunArtifact(exe_tests);

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
    test_step.dependOn(&run_exe_tests.step);
}
