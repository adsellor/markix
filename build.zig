const std = @import("std");

pub fn build(build_context: *std.Build) void {
    const target = build_context.standardTargetOptions(.{});
    const optimize = build_context.standardOptimizeOption(.{});
    const module = build_context.createModule(.{
        .root_source_file = build_context.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const executable = build_context.addExecutable(.{
        .name = "markix",
        .root_module = module,
    });
    build_context.installArtifact(executable);

    const rss_module = build_context.createModule(.{
        .root_source_file = build_context.path("src/rss_main.zig"),
        .target = target,
        .optimize = optimize,
    });
    const rss_executable = build_context.addExecutable(.{
        .name = "markix-rss",
        .root_module = rss_module,
    });
    build_context.installArtifact(rss_executable);

    const run_command = build_context.addRunArtifact(executable);
    run_command.step.dependOn(build_context.getInstallStep());
    const run_step = build_context.step("run", "Run markix");
    run_step.dependOn(&run_command.step);

    const run_rss_command = build_context.addRunArtifact(rss_executable);
    run_rss_command.step.dependOn(build_context.getInstallStep());
    const run_rss_step = build_context.step("run-rss", "Run the Markix RSS reader");
    run_rss_step.dependOn(&run_rss_command.step);

    const test_module = build_context.createModule(.{
        .root_source_file = build_context.path("src/tests.zig"),
        .target = target,
        .optimize = optimize,
    });
    const unit_tests = build_context.addTest(.{ .root_module = test_module });
    const run_unit_tests = build_context.addRunArtifact(unit_tests);
    const test_step = build_context.step("test", "Run unit tests");
    test_step.dependOn(&run_unit_tests.step);

    const format_check = build_context.addFmt(.{
        .paths = &.{
            build_context.path("build.zig"),
            build_context.path("src"),
        },
        .check = true,
    });
    const check_step = build_context.step("check", "Compile, test, and check formatting");
    check_step.dependOn(&executable.step);
    check_step.dependOn(&rss_executable.step);
    check_step.dependOn(&run_unit_tests.step);
    check_step.dependOn(&format_check.step);
}
