const ig = @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const std = @import("std");

const state = struct {
    var pass_action: sg.PassAction = .{};
};

const Item = struct {
    path: [:0]const u8,
    name: [:0]const u8,
};

var carList: std.ArrayList(Item) = undefined;
var mapList: std.ArrayList(Item) = undefined;

var showDemoWindow = true;
var showFullPaths = false;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const alloc = gpa.allocator();

export fn init() void {
    // initialize sokol-gfx
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    // initialize sokol-imgui
    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });

    // initial clear color
    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.5, .b = 1.0, .a = 1.0 },
    };

    const io: *ig.ImGuiIO = ig.igGetIO();
    io.FontGlobalScale = 2;

    findFiles() catch unreachable;
}

fn findFiles() !void {
    carList = std.ArrayList(Item).init(alloc);
    mapList = std.ArrayList(Item).init(alloc);

    const resPath = "res/";

    var dir = std.fs.cwd().openDir(resPath, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => @panic("Resource folder " ++ resPath ++ " not found"),
        else => return err,
    };
    defer dir.close();

    var walker = try dir.walk(alloc);
    defer walker.deinit();

    const carExt = ".car.ini";
    const mapExt = ".map.ini";
    _ = mapExt; // autofix

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.path, carExt)) {
                std.log.info("Entry: path: {s}, basename: {s}, {}", .{ entry.path, entry.basename, entry.kind });
                try carList.append(.{
                    .name = try alloc.dupeZ(u8, entry.basename[0 .. entry.basename.len - carExt.len]),
                    .path = try alloc.dupeZ(u8, entry.path),
                });
            }
        }
    }

    std.log.info("-- Ended walking --", .{});

    for (carList.items) |item| {
        std.log.info("name: {s}, ---- full path: {s}", .{ item.name, item.path });
    }
}

export fn frame() void {
    // call simgui.newFrame() before any ImGui calls
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = 1,
    });

    //=== UI CODE STARTS HERE

    const vec2Zero = std.mem.zeroes(ig.ImVec2);

    ig.igShowDemoWindow(&showDemoWindow);

    const windowFlags =
        ig.ImGuiWindowFlags_NoMove |
        ig.ImGuiWindowFlags_NoResize |
        ig.ImGuiWindowFlags_NoCollapse |
        ig.ImGuiWindowFlags_NoTitleBar;

    const io: *ig.ImGuiIO = ig.igGetIO();
    {
        ig.igSetNextWindowPos(vec2Zero, ig.ImGuiCond_Once, vec2Zero);
        ig.igSetNextWindowSize(io.DisplaySize, ig.ImGuiCond_Always);
        _ = ig.igBegin("Hello Dear ImGui!", 0, windowFlags);
        defer ig.igEnd();

        //_ = ig.igColorEdit3("Background", &state.pass_action.colors[0].clear_value.r, ig.ImGuiColorEditFlags_None);

        {
            _ = ig.igBeginTable("carmapstable", 2, 0, vec2Zero, 0);
            defer ig.igEndTable();

            ig.igTableNextRow(0, 0);
            _ = ig.igTableSetColumnIndex(0);

            const listBoxWidth = -std.math.floatMin(f32);
            const listBoxHeight = 10 * ig.igGetTextLineHeightWithSpacing();
            const size: ig.ImVec2 = .{ .x = listBoxWidth, .y = listBoxHeight };

            if (ig.igBeginListBox("##cars", size)) {
                for (carList.items) |item| {
                    _ = ig.igSelectable_Bool(item.name.ptr, false, 0, vec2Zero);
                }

                ig.igEndListBox();
            }

            _ = ig.igTableSetColumnIndex(1);

            if (ig.igBeginListBox("##maps", size)) {
                _ = ig.igSelectable_Bool("some map", false, 0, vec2Zero);
                ig.igEndListBox();
            }
        }

        _ = ig.igCheckbox("Show full paths", &showFullPaths);

        if (ig.igButton("Launch!", .{ .x = -std.math.floatMin(f32), .y = 0 })) {
            std.log.info("Boom!", .{});
        }
    }

    //=== UI CODE ENDS HERE

    // call simgui.render() inside a sokol-gfx pass
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();

    for (carList.items) |item| {
        alloc.free(item.name);
        alloc.free(item.path);
    }

    carList.deinit();
    mapList.deinit();

    _ = gpa.deinit();
}

export fn event(ev: [*c]const sapp.Event) void {
    // forward input events to sokol-imgui
    _ = simgui.handleEvent(ev.*);
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .window_title = "Shakedown Rally Loader",
        .width = 800,
        .height = 600,
        .icon = .{ .sokol_default = true },
        .logger = .{ .func = slog.func },
        .high_dpi = true,
    });
}
