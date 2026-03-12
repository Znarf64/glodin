package canvas

import "base:runtime"

import "core:fmt"
import glm "core:math/linalg/glsl"
import "core:time"
@(require) import "core:image/png"

import "vendor:glfw"

import "input"

import glodin "../.."

window_x, window_y: int = 900, 600

program, program_post: glodin.Program

accumulator: Accumulator

Accumulator :: struct {
	fb:      glodin.Framebuffer,
	texture: glodin.Texture,
	count:   int,
}

accumulator_reset :: proc() {
	accumulator.count = 0
	glodin.clear_color(accumulator.fb, 0)
}

accumulator_create :: proc(w, h: int) {
	accumulator.texture = glodin.create_texture(w, h, format = .RGBA32F)
	accumulator.fb = glodin.create_framebuffer({accumulator.texture})
	glodin.set_uniforms(program_post, {{"u_texture", accumulator.texture}})
}

accumulator_destroy :: proc() {
	glodin.destroy(accumulator.texture)
	glodin.destroy(accumulator.fb)
}

mouse_position_buffer: [512]glm.vec2
mouse_position_buffer_index: int

cursor_position_callback :: proc "c" (_: glfw.WindowHandle, x, y: f64) {
	if (mouse_position_buffer_index != 0 && mouse_position_buffer[mouse_position_buffer_index - 1] == glm.vec2{f32(x), f32(y)}) {
		return
	}
	mouse_position_buffer[mouse_position_buffer_index] = glm.vec2{f32(x), f32(y)}
	mouse_position_buffer_index += 1
}

main :: proc() {
	ok := glfw.Init()
	assert(bool(ok))
	window := glfw.CreateWindow(900, 600, "", nil, nil)

	input.init(window)
	input.set_mouse_mode(.Captured)

	glfw.SetCursorPosCallback(window, cursor_position_callback);

	glfw.SetWindowSizeCallback(window, proc "c" (window: glfw.WindowHandle, x, y: i32) {
		window_x, window_y = int(x), int(y)
		context = runtime.default_context()
		accumulator_destroy()
		accumulator_create(window_x, window_y)
		accumulator_reset()
	})

	glodin.init_glfw(window)
	defer glodin.uninit()

	glodin.window_size_callback(900, 600)

	glfw.SwapInterval(0)

	Vertex_2D :: struct {
		position: glm.vec2,
	}

	vertices: []Vertex_2D = {{{0, 0}}, {{0, 1}}, {{1, 1}}, {{0, 0}}, {{1, 0}}, {{1, 1}}}

	quad := glodin.create_mesh(vertices)
	defer glodin.destroy(quad)

	cursor := glodin.create_texture_from_file_data(#load("cursor.png")) or_else panic("Failed to load cursor texture")
	defer glodin.destroy(cursor)
	glodin.set_texture_sampling_state(cursor, .Nearest, .Nearest, wrap = glodin.Texture_Wrap.Clamp_To_Border)

	program = glodin.create_program_source(
		#load("vertex.glsl"),
		#load("fragment.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program)

	program_post = glodin.create_program_source(
		#load("vertex.glsl"),
		#load("post.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program_post)

	glodin.set_uniforms(program, {{"u_texture", cursor}})

	accumulator_create(window_x, window_y)
	accumulator_reset()
	defer accumulator_destroy()

	glodin.enable(.Blend)
	glodin.set_blend_func(.One, .One)
	glodin.set_blend_equation(.Add)

	last_frame_time := time.now()

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()
		input.poll();

		glodin.enable(.Blend)

		for _ in 0 ..< 6 {
			glfw.PollEvents()
			time.sleep(time.Millisecond)
		}

		if (mouse_position_buffer_index <= 1) {
			accumulator.count += 1
			mouse_position := mouse_position_buffer[0]
			glodin.set_uniforms(program, {
					{
						"u_position",
						glm.vec2{1, -1} * mouse_position * glm.vec2{1.0 / f32(window_x), 1.0 / f32(window_y)},
					},
					{
						"u_scale",
						glm.vec2{16, 16} * glm.vec2{1.0 / f32(window_x), 1.0 / f32(window_y)},
					},
				},
			)
			glodin.draw(accumulator.fb, program, quad)
		} else do for i in 0 ..< mouse_position_buffer_index - 1 {
			start := mouse_position_buffer[i]
			end   := mouse_position_buffer[i + 1]
			for i in 0 ..< 10 {
				accumulator.count += 1
				mouse_position := glm.lerp(start, end, f32(i) / 10)
				glodin.set_uniforms(program, {
						{
							"u_position",
							glm.vec2{1, -1} * mouse_position * glm.vec2{1.0 / f32(window_x), 1.0 / f32(window_y)},
						},
						{
							"u_scale",
							glm.vec2{16, 16} * glm.vec2{1.0 / f32(window_x), 1.0 / f32(window_y)},
						},
					},
				)
				glodin.draw(accumulator.fb, program, quad)
			}
		}
		mouse_position_buffer_index = 0

		glodin.disable(.Blend)
		last_frame_time = time.now()

		glodin.clear_color(0, 0)
		glodin.set_uniforms(program_post, {{"u_inv_samples", 1.0 / f32(accumulator.count)}, {"u_scale", glm.vec2(1)}})
		glodin.draw({}, program_post, quad)

		accumulator_reset()

		glfw.SwapBuffers(window)
		free_all(context.temp_allocator)
	}
}
