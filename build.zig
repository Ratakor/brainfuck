const std = @import("std");

pub fn build(b: *std.Build) !void {
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

    const run_cmd = b.addRunArtifact(bf);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run a brainfuck program");
    run_step.dependOn(&run_cmd.step);

    const examples_step = b.step("examples", "Compile all the examples");
    examples_step.dependOn(b.getInstallStep());
    const cwd = std.fs.cwd();
    try cwd.makePath("./zig-out/examples");
    var examples_dir = try cwd.openIterableDir("./examples", .{});
    defer examples_dir.close();
    var examples_iterator = examples_dir.iterate();
    while (try examples_iterator.next()) |file| {
        const example_cmd = b.addRunArtifact(bfc);
        const in = try std.fmt.allocPrint(b.allocator, "./examples/{s}", .{file.name});
        const out = try std.fmt.allocPrint(
            b.allocator,
            "./zig-out/examples/{s}",
            // trim .o assuming there is only source files
            .{file.name[0..file.name.len - 2]}
        );
        example_cmd.addArgs(&[_][]const u8{ "-s", "-o", out, in });
        examples_step.dependOn(&example_cmd.step);
        b.allocator.free(in);
        b.allocator.free(out);
    }

    const clean_step = b.step("clean", "Delete all artifacts created by zig build");
    clean_step.dependOn(&b.addRemoveDirTree("zig-cache").step);
    clean_step.dependOn(&b.addRemoveDirTree("zig-out").step);
}
