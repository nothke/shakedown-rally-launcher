const std = @import("std");
const Build = std.Build;
const OptimizeMode = std.builtin.OptimizeMode;
const ResolvedTarget = Build.ResolvedTarget;
const Dependency = Build.Dependency;
const cimgui = @import("cimgui");

pub fn build(b: *Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // get the matching Zig module name and C header search path for vanilla imgui
    const cimgui_conf = cimgui.getConfig(false);

    // note that the sokol dependency is built with `.with_sokol_imgui = true`
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
    dep_sokol.artifact("sokol_clib").root_module.addIncludePath(dep_cimgui.path(cimgui_conf.include_dir));

    try buildNative(b, target, optimize, dep_sokol, dep_cimgui, cimgui_conf.module_name);
}

fn mainModule(b: *Build, target: ResolvedTarget, optimize: OptimizeMode, dep_sokol: *Dependency, dep_cimgui: *Dependency, cimgui_module: []const u8) *Build.Module {
    return b.createModule(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
            .{ .name = "cimgui", .module = dep_cimgui.module(cimgui_module) },
        },
    });
}

fn buildNative(b: *Build, target: ResolvedTarget, optimize: OptimizeMode, dep_sokol: *Dependency, dep_cimgui: *Dependency, cimgui_module: []const u8) !void {
    const demo = b.addExecutable(.{
        .name = if (optimize != .Debug) "Launcher" else "Launcher-Debug",
        .root_module = mainModule(b, target, optimize, dep_sokol, dep_cimgui, cimgui_module),
    });

    if (optimize != .Debug)
        demo.subsystem = .Windows;

    const exe_check = b.addExecutable(.{
        .name = "check_step",
        .root_module = mainModule(b, target, optimize, dep_sokol, dep_cimgui, cimgui_module),
    });

    const check = b.step("check", "Check if project compiles");
    check.dependOn(&exe_check.step);

    b.installArtifact(demo);
    const runStep = b.step("run", "Run Launcher");
    runStep.dependOn(&b.addRunArtifact(demo).step);
}