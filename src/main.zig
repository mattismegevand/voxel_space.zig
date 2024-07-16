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

const state = struct {
    var pass_action: sg.PassAction = .{};
    var color_map: [*c]u8 = undefined;
    var height_map: [*c]u8 = undefined;
    var img_width: i32 = undefined;
    var img_height: i32 = undefined;
    var smp: sg.Sampler = .{};
    var rendered: bool = false;
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

    var w: c_int = undefined;
    var h: c_int = undefined;
    var n: c_int = undefined;
    state.color_map = c.stbi_load("assets/C1W.png", &w, &h, &n, 0);
    state.height_map = c.stbi_load("assets/D1.png", &w, &h, &n, 0);
    state.img_width = w;
    state.img_height = h;

    state.pass_action.colors[0] = .{
        .load_action = .CLEAR,
        .clear_value = .{ .r = 0.5, .g = 0.8, .b = 0.9, .a = 1 },
    };
}

export fn frame() void {
    const Params = struct {
        var x: f32 = 600;
        var y: f32 = 600;
        var phi: f32 = 0;
        var height: f32 = 50;
        var horizon: f32 = 120;
        var scale_height: f32 = 120;
        var distance: f32 = 300;
    };
    simgui.newFrame(.{
        .width = sapp.width(),
        .height = sapp.height(),
        .delta_time = sapp.frameDuration(),
        .dpi_scale = sapp.dpiScale(),
    });

    Params.x += 1;
    Params.y += 1;

    _ = ig.igBegin("params", 0, ig.ImGuiWindowFlags_None);
    _ = ig.igDragFloat("x", &Params.x, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("y", &Params.y, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("phi", &Params.phi, 0.01, 4, 1, "%f", 0);
    _ = ig.igDragFloat("height", &Params.height, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("horizon", &Params.horizon, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("scale_height", &Params.scale_height, 1, 0, 1000, "%f", 0);
    _ = ig.igDragFloat("distance", &Params.distance, 1, 0, 1000, "%f", 0);
    ig.igEnd();

    drawTerrain(Point{ .x = Params.x, .y = Params.y }, Params.phi, Params.height, Params.horizon, Params.scale_height, Params.distance, sapp.width(), sapp.height());

    sg.beginPass(.{ .action = state.pass_action, .swapchain = sglue.swapchain() });
    sgl.draw();
    simgui.render();
    sg.endPass();
    sg.commit();
}

export fn cleanup() void {
    simgui.shutdown();
    sgl.shutdown();
    sg.shutdown();
}

export fn event(ev: [*c]const sapp.Event) void {
    _ = simgui.handleEvent(ev.*);
}

fn getHeight(p: Point) u8 {
    const x = @mod(@as(i32, @intFromFloat(p.x)), state.img_width);
    const y = @mod(@as(i32, @intFromFloat(p.y)), state.img_height);
    const index = @as(usize, @intCast(y * state.img_width + x));
    return state.height_map[index];
}

fn getColor(p: Point) Color {
    const x = @mod(@as(i32, @intFromFloat(p.x)), state.img_width);
    const y = @mod(@as(i32, @intFromFloat(p.y)), state.img_height);
    const index = @as(usize, @intCast(3 * (y * state.img_width + x)));
    return Color{
        .r = state.color_map[index],
        .g = state.color_map[index + 1],
        .b = state.color_map[index + 2],
    };
}

fn pixelToGL(x: f32, y: f32, screen_width: i32, screen_height: i32) [2]f32 {
    return .{
        x / @as(f32, @floatFromInt(screen_width)) * 2.0 - 1.0,
        1.0 - (y / @as(f32, @floatFromInt(screen_height)) * 2.0),
    };
}

fn drawTerrain(p: Point, phi: f32, height: f32, horizon: f32, scale_height: f32, distance: f32, screen_width: i32, screen_height: i32) void {
    sgl.defaults();
    sgl.beginLines();

    const sinphi: f32 = std.math.sin(phi);
    const cosphi: f32 = std.math.cos(phi);

    var z: f32 = distance;
    while (z > 1) : (z -= 1) {
        var pleft = Point{
            .x = (-cosphi * z - sinphi * z) + p.x,
            .y = (sinphi * z - cosphi * z) + p.y,
        };
        const pright = Point{
            .x = (cosphi * z - sinphi * z) + p.x,
            .y = (-sinphi * z - cosphi * z) + p.y,
        };

        const dx: f32 = (pright.x - pleft.x) / @as(f32, @floatFromInt(screen_width));
        const dy: f32 = (pright.y - pleft.y) / @as(f32, @floatFromInt(screen_width));

        var i: f32 = 0;
        while (i < @as(f32, @floatFromInt(screen_width))) : (i += 1) {
            const height_on_screen = (height - @as(f32, @floatFromInt(getHeight(pleft)))) / z * scale_height + horizon;
            const color = getColor(pleft);
            const start = pixelToGL(i, height_on_screen, screen_width, screen_height);
            const end = pixelToGL(i, @as(f32, @floatFromInt(screen_height)), screen_width, screen_height);

            sgl.v2fC3b(start[0], start[1], color.r, color.g, color.b);
            sgl.v2fC3b(end[0], end[1], color.r, color.g, color.b);

            pleft.x += dx;
            pleft.y += dy;
        }
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
