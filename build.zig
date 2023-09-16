const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const bfc = b.addExecutable(.{
        .name = "bfc",
        .root_source_file = .{ .path = "src/bfc.zig" },
        .target = target,
        .optimize = optimize,
    });
    bfc.strip = b.option(bool, "strip", "Strip the binary") orelse switch (optimize) {
        .Debug, .ReleaseSafe => false,
        .ReleaseFast, .ReleaseSmall => true,
    };
    b.installArtifact(bfc);

    const bf_nasm = b.addSystemCommand(
        &[_][]const u8{ "nasm", "-f", "elf64", "-o", "zig-cache/bf.o", "src/bf.s" }
    );
    const bf = b.addExecutable(.{
        .name = "bf",
        .root_source_file = .{ .path = "zig-cache/bf.o" },
        .target = .{ .cpu_arch = .x86_64, .os_tag = .linux },
    });
    bf.step.dependOn(&bf_nasm.step);
    bf.strip = true;
    b.installArtifact(bf);

    const bfc_cmd = b.addRunArtifact(bfc);
    bfc_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        bfc_cmd.addArgs(args);
    }
    const bfc_step = b.step("bfc", "Compile a brainfuck program with bfc");
    bfc_step.dependOn(&bfc_cmd.step);

    const bf_cmd = b.addRunArtifact(bf);
    bf_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        bf_cmd.addArgs(args);
    }
    const bf_step = b.step("bf", "Interprete a brainfuck program with bf");
    bf_step.dependOn(&bf_cmd.step);

    const clean_step = b.step("clean", "Delete all artifacts created by zig build");
    clean_step.dependOn(&b.addRemoveDirTree("zig-cache").step);
    clean_step.dependOn(&b.addRemoveDirTree("zig-out").step);
}
