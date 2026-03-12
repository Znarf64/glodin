package example

import "base:runtime"

import "core:log"
import la "core:math/linalg"
import glm "core:math/linalg/glsl"
import "core:strings"
import "core:time"

import "vendor:glfw"

import glodin "../.."

program: glodin.Program
program_down: glodin.Program
program_up: glodin.Program
program_post: glodin.Program

quad: glodin.Mesh

main :: proc() {
	context.logger = log.create_console_logger(ODIN_DEBUG ? .Debug : .Error)
	callback_context = context

	window_init()
	defer window_uninit()

	Vertex_2D :: struct {
		position:   [2]f32,
		tex_coords: [2]f32,
	}

	vertices: []Vertex_2D = {
		{ position = { -1, -1, }, tex_coords = { 0, 0, }, },
		{ position = { +1, -1, }, tex_coords = { 1, 0, }, },
		{ position = { -1, +1, }, tex_coords = { 0, 1, }, },
		{ position = { +1, +1, }, tex_coords = { 1, 1, }, },
	}

	indices: []u32 = { 0, 1, 2, 2, 1, 3, }

	quad = glodin.create_mesh(vertices, indices)
	defer glodin.destroy(quad)

	meshes := glodin.create_mesh(#load("cube.glb"), "cube.glb") or_else panic("Failed to load mesh")
	defer for mesh in meshes do glodin.destroy(mesh)
	cube := meshes[0]

	program = glodin.create_program_source(
		#load("shaders/vertex.glsl"),
		#load("shaders/fragment.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program)

	program_down = glodin.create_program_source(
		#load("shaders/post/vertex.glsl"),
		#load("shaders/downsample/downsample.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program_down)

	program_up = glodin.create_program_source(
		#load("shaders/post/vertex.glsl"),
		#load("shaders/upsample/upsample.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program_up)

	program_post = glodin.create_program_source(
		#load("shaders/post/vertex.glsl"),
		#load("shaders/post/fragment.glsl"),
	) or_else panic("Failed to compile program")
	defer glodin.destroy(program_post)

	start_time := time.now()

	total_time: f64
	for !window.should_close {
		_time := f64(time.duration_seconds(time.since(start_time)))
		total_time = _time

		glodin.clear_color(g_buffer.fb, {0.1, 0.1, 0.1, 1})
		glodin.clear_depth(g_buffer.fb, 1)
		glodin.enable(.Depth_Test, .Cull_Face)

		EMISSION :: 8

		update_camera()
		glodin.set_uniforms(program, {
			{ "u_view",        camera.view,        },
			{ "u_perspective", camera.perspective, },
		})

		glodin.set_uniforms(program, {
			{ "u_model",    glm.mat4Translate(RIGHT * 3) * glm.mat4Rotate(UP + RIGHT + FORWARD, 3 + f32(total_time)), },
			{ "u_emission", EMISSION * glm.vec3{1, 0.25, 0.125},                                                      },
		})
		glodin.draw(g_buffer.fb, program, cube)

		glodin.set_uniforms(program, {
			{ "u_model",    glm.mat4Rotate(UP + FORWARD, 1 + f32(total_time)), },
			{ "u_emission", EMISSION * glm.vec3{0.125, 1, 0.25},               },
		})
		glodin.draw(g_buffer.fb, program, cube)

		glodin.set_uniforms(program, {
			{ "u_model",    glm.mat4Translate(LEFT * 3) * glm.mat4Rotate(UP + LEFT + FORWARD, -5 + f32(total_time)), },
			{ "u_emission", EMISSION * glm.vec3{0.125, 0.25, 1},                                                     },
		})
		glodin.draw(g_buffer.fb, program, cube)

		glodin.blit_framebuffers(g_buffer.secondary.fb, g_buffer.primary.fb)

		execute_mip_chain(g_buffer.mip_chain, g_buffer.secondary.color_texture)

		glodin.set_uniforms(program_post, {
			{ "u_texture_color", g_buffer.secondary.color_texture, },
			{ "u_texture_bloom", g_buffer.mip_chain.mips[0],       },
		})
		glodin.disable(.Cull_Face, .Depth_Test)
		glodin.draw({}, program_post, quad)

		window_poll()
	}

	g_buffer_uninit()
}

g_buffer: G_Buffer

Target_Color_Depth :: struct {
	fb:                    glodin.Framebuffer,
	color_texture:         glodin.Texture,
	depth_stencil_texture: glodin.Texture,
}

G_Buffer :: struct {
	// multisampled
	using primary: Target_Color_Depth,
	// not multisampled
	secondary:     Target_Color_Depth,

	mip_chain:     Mip_Chain,
}

RESOLUTION_SCALE :: 1

init_color_depth_target :: proc(target: ^Target_Color_Depth, width, height: int, samples := 0) {
	target.color_texture = glodin.create_texture(
		int(f32(window.width) * RESOLUTION_SCALE),
		int(f32(window.height) * RESOLUTION_SCALE),
		format = .RGBA32F,
		samples = samples,
	)
	target.depth_stencil_texture = glodin.create_texture(
		int(f32(window.width) * RESOLUTION_SCALE),
		int(f32(window.height) * RESOLUTION_SCALE),
		format = .Depth24_Stencil8,
		samples = samples,
	)
	target.fb =
		glodin.create_framebuffer(
			{target.color_texture},
			target.depth_stencil_texture,
		)
}

g_buffer_init :: proc() {
	init_color_depth_target(&g_buffer.primary,   window.width, window.height, 8)
	init_color_depth_target(&g_buffer.secondary, window.width, window.height, 0)
	glodin.set_texture_sampling_state(g_buffer.secondary.color_texture, mag_filter = .Linear)

	n_mips: int
	w := window.width
	h := window.height
	for w > 8 && h > 8 {
		w >>= 1
		h >>= 1
		n_mips += 1
	}
	g_buffer.mip_chain = create_mip_chain(n_mips + 1)
}

g_buffer_uninit :: proc() {
	glodin.destroy(g_buffer.primary.fb)
	glodin.destroy(g_buffer.primary.color_texture)
	glodin.destroy(g_buffer.primary.depth_stencil_texture)

	glodin.destroy(g_buffer.secondary.fb)
	glodin.destroy(g_buffer.secondary.color_texture)
	glodin.destroy(g_buffer.secondary.depth_stencil_texture)

	destroy_mip_chain(g_buffer.mip_chain)
}

g_buffer_resize :: proc() {
	g_buffer_uninit()
	g_buffer_init()
}

Mip_Chain :: struct {
	mips:        []glodin.Texture,
	framebuffer: glodin.Framebuffer,
}

create_mip_chain :: proc(n: int, allocator := context.allocator) -> (mc: Mip_Chain) {
	mc.mips = make([]glodin.Texture, n, allocator)

	w, h := window.width, window.height

	for &m in mc.mips {
		m = glodin.create_texture(
			w,
			h,
			format = .RGBA32F,
			wrap = glodin.Texture_Wrap.Clamp_To_Edge,
		)

		w >>= 1
		h >>= 1
	}

	mc.framebuffer = glodin.create_framebuffer({mc.mips[0]})

	return
}

destroy_mip_chain :: proc(mip_chain: Mip_Chain, allocator := context.allocator) {
	for m in mip_chain.mips {
		glodin.destroy(m)
	}
	glodin.destroy_framebuffer(mip_chain.framebuffer)
	delete(mip_chain.mips, allocator)
}

execute_mip_chain :: proc(mip_chain: Mip_Chain, source: glodin.Texture) {
	size := glodin.get_texture_size_2d(source)
	glodin.set_uniforms(program_down, {
		{ "srcTexture",    source,                   },
		{ "srcResolution", la.array_cast(size, f32), },
	})
	for mip in mip_chain.mips[1:] {
		glodin.set_framebuffer_color_texture(mip_chain.framebuffer, mip)
		glodin.draw(mip_chain.framebuffer, program_down, quad)
		size := glodin.get_texture_size_2d(mip)
		glodin.set_uniforms(program_down, {
			{ "srcTexture",    mip,                      },
			{ "srcResolution", la.array_cast(size, f32), },
		})
	}

	glodin.set_uniforms(program_up, {
		{ "srcTexture",   mip_chain.mips[len(mip_chain.mips) - 1], },
		{ "filterRadius", f32(0.01 / 1000) * f32(window.height),   },
	})
	#reverse for mip in mip_chain.mips[:len(mip_chain.mips) - 1] {
		glodin.set_framebuffer_color_texture(mip_chain.framebuffer, mip)
		glodin.draw(mip_chain.framebuffer, program_up, quad)
		glodin.set_uniform(program_up, "srcTexture", mip)
	}
}

window: Window

Window :: struct {
	handle:        glfw.WindowHandle,
	width, height: int,
	aspect_ratio:  f32,
	should_close:  bool,
}

set_window_title :: proc(title: string) {
	glfw.SetWindowTitle(window.handle, strings.clone_to_cstring(title, context.temp_allocator))
}

window_poll :: proc() {
	glfw.SwapBuffers(window.handle)

	glfw.PollEvents()
	window.should_close = bool(glfw.WindowShouldClose(window.handle))
}

window_init :: proc() {
	if !glfw.Init() {
		log.panic("GLFW has failed to load.")
	}

	window.handle = glfw.CreateWindow(900, 600, "GLODIN", nil, nil)

	if window.handle == nil {
		log.panic("GLFW has failed to load the window.")
	}

	w, h := glfw.GetWindowSize(window.handle)
	window.width = int(w)
	window.height = int(h)
	window.aspect_ratio = f32(w) / f32(h)

	glfw.SetWindowSizeCallback(window.handle, size_callback)

	glfw.MakeContextCurrent(window.handle)

	glodin.init(glfw.gl_set_proc_address)
	g_buffer_init()

	glfw.SwapInterval(0)

	recompute_perspective()
}

window_uninit :: proc() {
	glodin.uninit()
	glfw.DestroyWindow(window.handle)
	glfw.Terminate()
}

callback_context: runtime.Context

@(private = "file")
size_callback :: proc "c" (window_handle: glfw.WindowHandle, width, height: i32) {
	window.width  = max(int(width),  1)
	window.height = max(int(height), 1)
	window.aspect_ratio = f32(width) / f32(height)

	context = callback_context
	g_buffer_resize()
	recompute_perspective()
	glodin.window_size_callback(int(width), int(height))
}

// odinfmt: disable
UP       :: glm.vec3{+0, +1, +0}
DOWN     :: glm.vec3{+0, -1, +0}
FORWARD  :: glm.vec3{+0, +0, -1}
BACKWARD :: glm.vec3{+0, +0, +1}
LEFT     :: glm.vec3{+1, +0, +0}
RIGHT    :: glm.vec3{-1, +0, +0}
// odinfmt: enable

camera: Camera = {
	position = BACKWARD * 5,
	near     = 0.01,
	far      = 1000,
	fov      = 1,
}

Camera :: struct {
	perspective:        glm.mat4,
	view:               glm.mat4,
	position:           glm.vec3,
	forward, up, right: glm.vec3,
	near, far, fov:     f32,
	yaw, pitch:         f32,
}

update_camera :: proc() {
	camera.forward = (get_camera_rotation_matrix() * glm.vec4{0, 0, -1, 0}).xyz
	camera.right = glm.cross(camera.forward, UP)
	camera.up = glm.cross(camera.right, camera.forward)
	recompute_view()
}

get_camera_rotation_matrix :: proc() -> glm.mat4 {
	return la.matrix4_from_euler_angles_f32(
		glm.clamp(camera.pitch, -glm.PI * 0.5, glm.PI * 0.5),
		camera.yaw,
		0,
		.ZYX,
	)
}

recompute_perspective :: proc "contextless" () {
	camera.perspective = glm.mat4Perspective(
		camera.fov,
		window.aspect_ratio,
		camera.near,
		camera.far,
	)
}

recompute_view :: proc() {
	camera.view = glm.mat4LookAt(
		camera.position,
		camera.position + camera.forward,
		glm.vec3{0, 1, 0},
	)
}

