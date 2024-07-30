const ig = @import("cimgui");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const std = @import("std");

const vec2Zero = std.mem.zeroes(ig.ImVec2);

const state = struct {
    var pass_action: sg.PassAction = .{};
};

const Item = struct {
    path: [:0]const u8,
    name: [:0]const u8,
};

const ItemList = std.ArrayList(Item);

var carList: ItemList = undefined;
var mapList: ItemList = undefined;

var cari: i32 = -1;
var mapi: i32 = -1;

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
    carList = ItemList.init(alloc);
    mapList = ItemList.init(alloc);

    const resPath = "res/";

    var dir = std.fs.cwd().openDir(resPath, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound => @panic("Resource folder " ++ resPath ++ " not found"),
        else => return err,
    };
    defer dir.close();

    try loadFiles(".car.ini", dir, &carList);
    try loadFiles(".map.ini", dir, &mapList);

    std.log.info("-- Ended walking --", .{});

    for (carList.items) |item| {
        std.log.info("name: {s}, ---- full path: {s}", .{ item.name, item.path });
    }
}

fn loadFiles(ext: []const u8, dir: std.fs.Dir, list: *ItemList) !void {
    var walker = try dir.walk(alloc);
    defer walker.deinit();

    while (try walker.next()) |entry| {
        if (entry.kind == .file) {
            if (std.mem.endsWith(u8, entry.path, ext)) {
                std.log.info("Entry: path: {s}, basename: {s}, {}", .{ entry.path, entry.basename, entry.kind });
                try list.append(.{
                    .name = try alloc.dupeZ(u8, entry.basename[0 .. entry.basename.len - ext.len]),
                    .path = try alloc.dupeZ(u8, entry.path),
                });
            }
        }
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

        {
            _ = ig.igBeginTable("carmapstable", 2, 0, vec2Zero, 0);
            defer ig.igEndTable();

            ig.igTableNextRow(0, 0);
            _ = ig.igTableSetColumnIndex(0);

            const listBoxWidth = -std.math.floatMin(f32);
            const listBoxHeight = 10 * ig.igGetTextLineHeightWithSpacing();
            const size: ig.ImVec2 = .{ .x = listBoxWidth, .y = listBoxHeight };

            ig.igSeparatorText("Cars");
            drawListBox("##cars", carList, size, &cari);

            _ = ig.igTableSetColumnIndex(1);

            ig.igSeparatorText("Maps");
            drawListBox("##maps", mapList, size, &mapi);
        }

        _ = ig.igCheckbox("Show full paths", &showFullPaths);

        if (ig.igButton("Launch!", .{ .x = -std.math.floatMin(f32), .y = 0 })) {
            launch() catch unreachable;
        }
    }

    //=== UI CODE ENDS HERE

    // call simgui.render() inside a sokol-gfx pass
    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    simgui.render();
    sg.endPass();
    sg.commit();
}

fn launch() !void {
    if (cari < 0 or mapi < 0) {
        std.log.info("Car or map are not selected!", .{});
        return;
    }

    // NEngine-drive.exe -car "cars/spec17/spec17_gravel.car.ini" -map "maps/finland/finland.map.ini"

    const str = try std.fmt.allocPrint(alloc, "NEngine-drive.exe -car \"{s}\" -map \"{s}\"", .{
        carList.items[@intCast(cari)].path,
        mapList.items[@intCast(mapi)].path,
    });
    defer alloc.free(str);

    std.log.info("Launching: {s}", .{str});

    const argv = [_][]const u8{
        "NEngine-drive.exe",
        "-car",
        carList.items[@intCast(cari)].path,
        "-map",
        mapList.items[@intCast(mapi)].path,
    };

    var process = std.process.Child.init(&argv, alloc);
    try process.spawn();
}

fn drawListBox(id: [:0]const u8, list: ItemList, size: ig.ImVec2, index: *i32) void {
    if (ig.igBeginListBox(id, size)) {
        for (list.items, 0..) |item, i| {
            const isSelected = i == index.*;
            const label = if (showFullPaths) item.path else item.name;
            const shouldBeSelected = ig.igSelectable_Bool(label, isSelected, 0, vec2Zero);

            if (shouldBeSelected)
                index.* = @intCast(i);
        }

        ig.igEndListBox();
    }
}

export fn cleanup() void {
    simgui.shutdown();
    sg.shutdown();

    for (carList.items) |item| {
        alloc.free(item.name);
        alloc.free(item.path);
    }

    for (mapList.items) |item| {
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
