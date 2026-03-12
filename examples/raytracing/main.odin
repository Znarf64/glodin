package canvas

import "base:runtime"

import "core:fmt"
import glm "core:math/linalg/glsl"
import la "core:math/linalg"
import "core:math/rand"
import "core:slice"
import "core:time"

import "vendor:glfw"
import stbi "vendor:stb/image"

import "input"

import glodin "../.."

position: glm.vec3 = {0, 0, 30}
yaw, pitch: f32

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

main :: proc() {
	ok := glfw.Init()
	assert(bool(ok))
	window := glfw.CreateWindow(900, 600, "", nil, nil)

	input.init(window)
	input.set_mouse_mode(.Captured)

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

	MAX_SPHERES :: 1024
	spheres := make([]Sphere, MAX_SPHERES)

	n_spheres := 1000
	for &s in spheres[:n_spheres] {
		s.position = 100 * ({rand.float32(), rand.float32(), rand.float32()} * 2 - 1)
		s.radius = rand.float32_range(0.5, 1)
	}

	spheres_buffer := glodin.create_uniform_buffer(spheres)
	defer glodin.destroy(spheres_buffer)

	skybox := glodin.create_cube_map(2048)
	defer glodin.destroy(skybox)

	{
		dir := #load_directory("skybox")
		for file in dir {
			data := file.data
			x, y, c: i32
			pixels := cast([^][4]u8)stbi.load_from_memory(
				raw_data(data),
				i32(len(data)),
				&x,
				&y,
				&c,
				4,
			)

			faces: [glodin.Cube_Map_Face]string = {
				.Positive_X = "right.jpg",
				.Negative_X = "left.jpg",
				.Positive_Y = "top.jpg",
				.Negative_Y = "bottom.jpg",
				.Positive_Z = "front.jpg",
				.Negative_Z = "back.jpg",
			}

			for n, f in faces {
				if n == file.name {
					glodin.set_cube_map_face_texture(skybox, f, pixels[:x * y])
					continue
				}
			}
		}

		glodin.generate_mipmaps(skybox)
	}

	MAX_BVH_NODES :: MAX_SPHERES

	bvh_data := make([dynamic]Bvh_Node, MAX_BVH_NODES)
	bvh_buffer := glodin.create_uniform_buffer(bvh_data[:])
	defer glodin.destroy(bvh_buffer)

	((^runtime.Raw_Dynamic_Array)(&bvh_data)).len = 0

	bvh_aabbs := make([]Aabb, MAX_BVH_NODES)

	build_bvh(spheres, &bvh_data, bvh_aabbs, 0, n_spheres)
	bvh_aabbs_buffer := glodin.create_uniform_buffer(bvh_aabbs)
	defer glodin.destroy(bvh_aabbs_buffer)
	glodin.set_uniform_buffer_data(bvh_buffer, bvh_data[:])
	glodin.set_uniform_buffer_data(spheres_buffer, spheres[:])

	material_data := make([][2]glm.vec4, MAX_SPHERES)
	for &m in material_data {
		m[0].r = glm.sqrt(rand.float32())
		m[0].g = glm.sqrt(rand.float32())
		m[0].b = glm.sqrt(rand.float32())

		switch rand.float32() {
		// diffuse
		case 0 ..< 0.25:
			m[0].w = -0
		// metallic
		case 0.25 ..< 0.75:
			m[0].w = +glm.pow(rand.float32(), 2)
		// transparent
		case 0.75 ..< 0.9:
			m[0].w = -glm.pow(rand.float32(), 8)
			m[0].rgb = glm.pow(m[0].rgb, 0.1)
		// emissive
		case:
			m[1].w = 1
			m[1].r = 0.8 + rand.float32() * 1.2
			m[1].g = 0.8 + rand.float32() * 1.2
			m[1].b = 0.8 + rand.float32() * 1.2
		}
	}
	materials_buffer := glodin.create_uniform_buffer(material_data)
	defer glodin.destroy(materials_buffer)

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

	glodin.set_uniforms(program, {
		{ "u_spheres",   spheres_buffer,   },
		{ "u_bvh_nodes", bvh_buffer,       },
		{ "u_bvh_aabbs", bvh_aabbs_buffer, },
		{ "u_materials", materials_buffer, },
		{ "u_skybox",    skybox,           },
	})

	accumulator_create(window_x, window_y)
	accumulator_reset()
	defer accumulator_destroy()

	glodin.enable(.Blend)
	glodin.set_blend_func(.One, .One)
	glodin.set_blend_equation(.Add)

	last_frame_time := time.now()

	frames_since_print: int
	last_print: time.Time

	for !glfw.WindowShouldClose(window) {
		frames_since_print += 1
		if time.duration_seconds(time.since(last_print)) > 1 {
			fmt.println(frames_since_print, "FPS")
			last_print = time.now()
			frames_since_print = 0
		}
		delta_time := f32(time.duration_seconds(time.since(last_frame_time)))
		last_frame_time = time.now()

		forward := glm.vec3{glm.sin(-yaw), 0, -glm.cos(-yaw)}

		SPEED :: 30

		dirty: bool
		if input.get_key(.W) {
			position += SPEED * delta_time * forward
			dirty = true
		}
		if input.get_key(.S) {
			position -= SPEED * delta_time * forward
			dirty = true
		}
		if input.get_key(.A) {
			position -= SPEED * delta_time * glm.cross(forward, glm.vec3{0, 1, 0})
			dirty = true
		}
		if input.get_key(.D) {
			position += SPEED * delta_time * glm.cross(forward, glm.vec3{0, 1, 0})
			dirty = true
		}
		if input.get_key(.E) {
			position.y += SPEED * delta_time
			dirty = true
		}
		if input.get_key(.Q) {
			position.y -= SPEED * delta_time
			dirty = true
		}

		{
			d := -input.get_mouse_relative() * 0.001
			yaw = yaw + d.x
			pitch = clamp(pitch + d.y, -glm.PI / 2, glm.PI / 2)
			if d != 0 {
				dirty = true
			}
		}

		if dirty {
			accumulator_reset()
		}

		accumulator.count += 1

		mat := glm.mat3(la.matrix3_from_euler_angles(0, yaw, pitch, .ZYX))

		glodin.set_uniforms(program, {
			{ "u_aspect_ratio",           f32(window_x) / f32(window_y),                      },
			{ "u_inv_resolution",         glm.vec2{1.0 / f32(window_x), 1.0 / f32(window_y)}, },
			{ "u_noise_source",           rand.int31() & ((2 << 16) - 1),                     },
			{ "u_camera_position",        position,                                           },
			{ "u_camera_rotation_matrix", mat,                                                },
		})

		glodin.enable(.Blend)
		glodin.draw(accumulator.fb, program, quad)
		glodin.disable(.Blend)

		glodin.clear_color(0, 0)
		glodin.set_uniform(program_post, "u_inv_samples", 1.0 / f32(accumulator.count))
		glodin.draw({}, program_post, quad)

		glfw.SwapBuffers(window)
		glfw.PollEvents()
		free_all(context.temp_allocator)
		input.poll()
	}
}

Sphere :: struct {
	position: glm.vec3,
	radius:   f32,
}

Aabb :: struct #align(16) #min_field_align(16) {
	min: glm.vec3,
	max: glm.vec3,
}

get_sphere_aabb :: proc(sphere: Sphere) -> (aabb: Aabb) {
	return {sphere.position - sphere.radius, sphere.position + sphere.radius}
}

aabb_union :: proc(a, b: Aabb) -> Aabb {
	return {glm.min(a.min, b.min), glm.max(a.max, b.max)}
}

Bvh_Node :: struct {
	left, right: i32,
}

build_bvh :: proc(
	spheres: []Sphere,
	nodes: ^[dynamic]Bvh_Node,
	aabbs: []Aabb,
	start, end: int,
	axis := 0,
) -> Aabb {
	span := end - start

	switch span {
	case 1:
		aabb := get_sphere_aabb(spheres[start])
		aabbs[len(nodes)] = aabb
		append(nodes, Bvh_Node{i32(start) + 1, max(i32)})

		return aabb
	case 2:
		l_aabb := get_sphere_aabb(spheres[start])
		r_aabb := get_sphere_aabb(spheres[start + 1])
		aabb := aabb_union(l_aabb, r_aabb)
		aabbs[len(nodes)] = aabb
		append(nodes, Bvh_Node{left = i32(start) + 1, right = i32(start + 1) + 1})

		return aabb
	case 3:
		l_index := len(nodes)
		l_aabb := build_bvh(spheres, nodes, aabbs, start, end - 1, (axis + 1) % 3)
		r_aabb := get_sphere_aabb(spheres[start + 2])
		aabb := aabb_union(l_aabb, r_aabb)
		aabbs[len(nodes)] = aabb
		append(
			nodes,
			Bvh_Node{
				left = -i32(l_index),
				right = i32(start + 1) + 1,
			},
		)

		return aabb
	case:
		sphere_compare :: proc(i, j: Sphere) -> bool {
			return i.position[context.user_index] < j.position[context.user_index]
		}
		context.user_index = axis
		slice.sort_by(spheres[start:end], sphere_compare)

		mid := start + span / 2

		node_index := len(nodes)
		append(nodes, Bvh_Node{})

		l_index := len(nodes)
		l_aabb := build_bvh(spheres, nodes, aabbs, start, mid, (axis + 1) % 3)
		r_index := len(nodes)
		r_aabb := build_bvh(spheres, nodes, aabbs, mid, end, (axis + 1) % 3)

		aabb := aabb_union(r_aabb, l_aabb)

		nodes[node_index] = {
			left  = -i32(l_index),
			right = -i32(r_index),
		}
		aabbs[node_index] = aabb

		return aabb
	}
}
