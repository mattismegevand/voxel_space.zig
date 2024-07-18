const ig = @import("cimgui");
const std = @import("std");
const sokol = @import("sokol");
const slog = sokol.log;
const sg = sokol.gfx;
const sapp = sokol.app;
const sgl = sokol.gl;
const sglue = sokol.glue;
const simgui = sokol.imgui;
const c = @cImport({
    @cInclude("stb_image.h");
});

const MOVE_SPEED: f32 = 2.5;
const ROT_SPEED: f32 = 0.1;
const UP_DOWN_SPEED: f32 = 5.0;

const state = struct {
    var allocator: std.mem.Allocator = undefined;
    var map_index: usize = 0;
    var maps: [][]const u8 = undefined;
    var color_map: [*c]u8 = undefined;
    var height_map: [*c]u8 = undefined;
    var img_width: i32 = undefined;
    var img_height: i32 = undefined;
    var ybuffer: [4096]f32 = undefined;
    var animation: bool = true;
    var pass_action: sg.PassAction = .{};
};

const Point = struct {
    x: f32,
    y: f32,
};

const Color = struct {
    r: u8,
    g: u8,
    b: u8,
};

fn loadMap() void {
    if (state.color_map) |ptr| {
        c.stbi_image_free(ptr);
        state.color_map = null;
    }
    if (state.height_map) |ptr| {
        c.stbi_image_free(ptr);
        state.height_map = null;
    }

    const color_filename = std.fmt.allocPrint(state.allocator, "assets/C{d}.png", .{state.map_index + 1}) catch {
        return;
    };
    const height_filename = std.fmt.allocPrint(state.allocator, "assets/D{d}.png", .{state.map_index + 1}) catch {
        return;
    };
    defer state.allocator.free(color_filename);
    defer state.allocator.free(height_filename);

    var w: c_int = undefined;
    var h: c_int = undefined;
    var n: c_int = undefined;

    state.color_map = c.stbi_load(color_filename.ptr, &w, &h, &n, 0);
    state.height_map = c.stbi_load(height_filename.ptr, &w, &h, &n, 0);
    state.img_width = w;
    state.img_height = h;
}

export fn init() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    sgl.setup(.{
        .logger = .{ .func = slog.func },
        .max_vertices = std.math.pow(i32, 2, 20),
    });
    simgui.setup(.{
        .logger = .{ .func = slog.func },
    });

    state.allocator = std.heap.page_allocator;
    state.maps = state.allocator.alloc([]const u8, 25) catch {
        return;
    };
    for (0.., state.maps) |i, *map| {
        map.* = std.fmt.allocPrint(state.allocator, "{d}", .{i + 1}) catch {
            return;
        };
    }

    loadMap();

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.5, .g = 0.8, .b = 0.9, .a = 1 },
    };
}

export fn frame() void {
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    const Params = struct {
        var x: f32 = 200;
        var y: f32 = 200;
        var phi: f32 = 0;
        var height: f32 = 50;
        var horizon: f32 = 120;
        var scale_height: f32 = 120;
        var distance: f32 = 300;
    };

    if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_P, false)) {
        state.animation = !state.animation;
    }

    if (state.animation) {
        Params.x += 1;
        Params.y += 1;
    } else {
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_W, true)) {
            Params.x -= MOVE_SPEED * std.math.sin(Params.phi);
            Params.y -= MOVE_SPEED * std.math.cos(Params.phi);
        }
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_S, true)) {
            Params.x += MOVE_SPEED * std.math.sin(Params.phi);
            Params.y += MOVE_SPEED * std.math.cos(Params.phi);
        }
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_A, true)) {
            Params.x -= MOVE_SPEED * std.math.cos(Params.phi);
            Params.y += MOVE_SPEED * std.math.sin(Params.phi);
        }
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_D, true)) {
            Params.x += MOVE_SPEED * std.math.cos(Params.phi);
            Params.y -= MOVE_SPEED * std.math.sin(Params.phi);
        }
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_Q, true)) {
            Params.phi += ROT_SPEED;
        }
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_E, true)) {
            Params.phi -= ROT_SPEED;
        }
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_Space, true)) {
            Params.height += UP_DOWN_SPEED;
        }
        if (ig.igIsKeyPressed_Bool(ig.ImGuiKey_LeftCtrl, true)) {
            Params.height -= UP_DOWN_SPEED;
        }
    }

    _ = ig.igBegin("params", 0, ig.ImGuiWindowFlags_None);
    if (ig.igBeginCombo("map", @ptrCast(state.maps[state.map_index]), 0)) {
        for (0.., state.maps) |i, elem| {
            const is_selected = (state.map_index == i);
            if (ig.igSelectable_Bool(@ptrCast(elem), is_selected, 0, ig.ImVec2{})) {
                if (state.map_index != i) {
                    state.map_index = i;
                    loadMap();
                }
            }

            if (is_selected) {
                ig.igSetItemDefaultFocus();
            }
        }
        ig.igEndCombo();
    }
    _ = ig.igDragFloat("x", &Params.x, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("y", &Params.y, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("phi", &Params.phi, 0.01, 4, 1, "%f", 0);
    _ = ig.igDragFloat("height", &Params.height, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("horizon", &Params.horizon, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("scale_height", &Params.scale_height, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("distance", &Params.distance, 1, 0, 1000, "%f", 0);
    ig.igEnd();

    drawTerrain(Point{ .x = Params.x, .y = Params.y }, Params.phi, Params.height, Params.horizon, Params.scale_height, Params.distance);

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sgl.draw();
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    for (state.maps) |map| {
        state.allocator.free(map);
    }
    state.allocator.free(state.maps);

    if (state.color_map) |ptr| {
        c.stbi_image_free(ptr);
    }

    if (state.height_map) |ptr| {
        c.stbi_image_free(ptr);
    }

    simgui.shutdown();
    sgl.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    _ = simgui.handleEvent(ev.*);
}

fn getIndex(p: Point, channels: i32) usize {
    const x = @mod(@as(i32, @intFromFloat(p.x)), state.img_width - 1);
    const y = @mod(@as(i32, @intFromFloat(p.y)), state.img_height - 1);
    const index = @as(usize, @intCast(channels * (y * state.img_width + x)));
    return index;
}

fn getHeight(p: Point) u8 {
    return state.height_map[getIndex(p, 1)];
}

fn getColor(p: Point) Color {
    const index = getIndex(p, 3);
    return Color{
        .r = state.color_map[index],
        .g = state.color_map[index + 1],
        .b = state.color_map[index + 2],
    };
}

fn pixelToGL(x: f32, y: f32) [2]f32 {
    return .{
        x / @as(f32, @floatFromInt(sapp.width())) * 2.0 - 1.0,
        1.0 - (y / @as(f32, @floatFromInt(sapp.height())) * 2.0),
    };
}

fn drawTerrain(p: Point, phi: f32, height: f32, horizon: f32, scale_height: f32, distance: f32) void {
    sgl.defaults();
    sgl.beginLines();

    const sinphi: f32 = std.math.sin(phi);
    const cosphi: f32 = std.math.cos(phi);

    for (0..@intCast(sapp.width())) |i| {
        state.ybuffer[i] = @as(f32, @floatFromInt(sapp.height()));
    }

    var dz: f32 = 1;
    var z: f32 = 1;
    while (z < distance) : (z += 1) {
        var pleft = Point{
            .x = (-cosphi * z - sinphi * z) + p.x,
            .y = (sinphi * z - cosphi * z) + p.y,
        };
        const pright = Point{
            .x = (cosphi * z - sinphi * z) + p.x,
            .y = (-sinphi * z - cosphi * z) + p.y,
        };

        const dx: f32 = (pright.x - pleft.x) / @as(f32, @floatFromInt(sapp.width()));
        const dy: f32 = (pright.y - pleft.y) / @as(f32, @floatFromInt(sapp.width()));

        var i: i32 = 0;
        while (i < sapp.width()) : (i += 1) {
            const height_on_screen = (height - @as(f32, @floatFromInt(getHeight(pleft)))) / z * scale_height + horizon;
            const color = getColor(pleft);
            const start = pixelToGL(@as(f32, @floatFromInt(i)), height_on_screen);
            const end = pixelToGL(@as(f32, @floatFromInt(i)), state.ybuffer[@intCast(i)]);

            sgl.v2fC3b(start[0], start[1], color.r, color.g, color.b);
            sgl.v2fC3b(end[0], end[1], color.r, color.g, color.b);

            if (height_on_screen < state.ybuffer[@intCast(i)]) {
                state.ybuffer[@intCast(i)] = height_on_screen;
            }

            pleft.x += dx;
            pleft.y += dy;
        }
        z += dz;
        dz += 0.00;
    }
    sgl.end();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = frame,
        .cleanup_cb = cleanup,
        .event_cb = event,
        .width = 800,
        .height = 800,
        .sample_count = 4,
        .icon = .{ .sokol_default = true },
        .window_title = "voxel_space.zig",
        .logger = .{ .func = slog.func },
    });
}
