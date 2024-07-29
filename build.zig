const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Dependency = Build.Dependency;
const sokol = @import("sokol");

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // note that the sokol dependency is built with `.with_imgui_sokol = true`
    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
        .with_sokol_imgui = true,
    });
    const dep_cimgui = b.dependency("cimgui", .{
        .target = target,
        .optimize = optimize,
    });

    // inject the cimgui header search path into the sokol C library compile step
    const cimgui_root = dep_cimgui.namedWriteFiles("cimgui").getDirectory();
    dep_sokol.artifact("sokol_clib").addIncludePath(cimgui_root);

    // from here on different handling for native vs wasm builds
    try buildNative(b, target, optimize, dep_sokol, dep_cimgui);
}

fn buildNative(b: *Build, target: ResolvedTarget, optimize: OptimizeMode, dep_sokol: *Dependency, dep_cimgui: *Dependency) !void {
    const demo = b.addExecutable(.{
        .name = if (optimize != .Debug) "Launcher" else "Launcher-Debug",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    demo.root_module.addImport("sokol", dep_sokol.module("sokol"));
    demo.root_module.addImport("cimgui", dep_cimgui.module("cimgui"));

    if (optimize != .Debug)
        demo.subsystem = .Windows;

    const exe_check = b.addExecutable(.{
        .name = "check_step",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe_check.root_module.addImport("sokol", dep_sokol.module("sokol"));
    exe_check.root_module.addImport("cimgui", dep_cimgui.module("cimgui"));

    const check = b.step("check", "Check if project compiles");
    check.dependOn(&exe_check.step);

    b.installArtifact(demo);
    var runStep = b.step("run", "Run demo");
    runStep.dependOn(&b.addRunArtifact(demo).step);
}
