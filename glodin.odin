package glodin

import "base:runtime"

import gl "vendor:OpenGL"
import "vendor:glfw"

GLODIN_TRACK_LEAKS :: #config(GLODIN_TRACK_LEAKS, ODIN_DEBUG)

Source_Code_Location :: runtime.Source_Code_Location

@(private)
get_handle :: proc {
	get_program_handle,
	get_compute_handle,
	get_texture_handle,
	get_framebuffer_handle,
}

_get_handle :: proc(x: $T) -> u32 {
	return get_handle(x)
}

destroy :: proc {
	destroy_mesh,
	destroy_instanced_mesh,
	destroy_program,
	destroy_framebuffer,
	destroy_texture,
	destroy_compute,
	destroy_uniform_buffer,
	destroy_indirect_buffer,
}

window_size_callback :: proc "contextless" (width, height: int) {
	root_fb.width = width
	root_fb.height = height

	gl.Viewport(0, 0, i32(width), i32(height))
	current_framebuffer = {}
}

@(private)
prev_framebuffer_size_callback: glfw.FramebufferSizeProc

init_glfw :: proc(window: glfw.WindowHandle, location := #caller_location) {
	prev_framebuffer_size_callback = glfw.SetFramebufferSizeCallback(
		window,
		proc "c" (window: glfw.WindowHandle, width, height: i32) {
			window_size_callback(int(width), int(height))
			if prev_framebuffer_size_callback != nil {
				prev_framebuffer_size_callback(window, width, height)
			}
		},
	)

	glfw.MakeContextCurrent(window)
	init(glfw.gl_set_proc_address, location)

	w, h := glfw.GetWindowSize(window)
	window_size_callback(int(w), int(h))
}

init :: proc(set_proc_address: gl.Set_Proc_Address_Type, location := #caller_location) {
	framebuffer_data_allocator = context.allocator

	framebuffers     = new(type_of(framebuffers^    ))
	textures         = new(type_of(textures^        ))
	meshes           = new(type_of(meshes^          ))
	instanced_meshes = new(type_of(instanced_meshes^))
	programs         = new(type_of(programs^        ))
	computes         = new(type_of(computes^        ))
	uniform_buffers  = new(type_of(uniform_buffers^ ))
	indirect_buffers = new(type_of(indirect_buffers^))

	gl.load_up_to(4, 6, set_proc_address)
	gl.BlendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA)
	gl.PixelStorei(gl.PACK_ALIGNMENT,   1)
	gl.PixelStorei(gl.UNPACK_ALIGNMENT, 1)

	logger_init()

	gl.Enable(gl.TEXTURE_CUBE_MAP_SEAMLESS)

	get_int :: proc(pname: u32) -> (value: int) {
		#assert(size_of(int) == size_of(int))
		gl.GetInteger64v(pname, cast(^i64)&value)
		return value
	}

	max_texture_size           = get_int(gl.MAX_TEXTURE_SIZE)
	max_texture_array_layers   = get_int(gl.MAX_ARRAY_TEXTURE_LAYERS)
	max_cube_map_size          = get_int(gl.MAX_CUBE_MAP_TEXTURE_SIZE)
	max_texture_max_anisotropy = get_int(gl.MAX_TEXTURE_MAX_ANISOTROPY)
	max_texture_units          = get_int(gl.MAX_TEXTURE_IMAGE_UNITS)

	// clamp this so we dont stack overflow when using alloca
	max_texture_units = min(max_texture_units, 128)

	texture_units = make([]Texture, max_texture_units)

	max_uniform_buffer_size        = get_int(gl.MAX_UNIFORM_BLOCK_SIZE)
	max_shader_storage_buffer_size = get_int(gl.MAX_SHADER_STORAGE_BLOCK_SIZE)

	debugf("max_texture_size: %v",               max_texture_size,               location = location)
	debugf("max_cube_map_size: %v",              max_cube_map_size,              location = location)
	debugf("max_texture_array_layers: %v",       max_texture_array_layers,       location = location)
	debugf("max_texture_max_anisotropy: %v",     max_texture_max_anisotropy,     location = location)
	debugf("max_texture_units: %v",              max_texture_units,              location = location)

	debugf("max_uniform_buffer_size: %M",        max_uniform_buffer_size,        location = location)
	debugf("max_shader_storage_buffer_size: %M", max_shader_storage_buffer_size, location = location)
}

uninit :: proc() {
	ga_destroy :: proc(ga: ^Generational_Array($T)) {
		when GLODIN_TRACK_LEAKS || true {
			name: string
			switch typeid_of(T) {
			case Mesh:
				name = "mesh"
			case Texture:
				name = "texture"
			case Compute:
				name = "compute"
			case Sampler:
				name = "sampler"
			case Program:
				name = "program"
			case Framebuffer:
				name = "framebuffer"
			case Uniform_Buffer:
				name = "uniform buffer"
			case Instanced_Mesh:
				name = "instanced mesh"
			}

			iter: int
			for _, fb in ga_iter(ga, &iter) {
				warnf("%s %v was not destroyed", name, fb)
			}
		}
		delete(ga.free)
		free(ga)
	}

	ga_destroy(meshes)
	ga_destroy(textures)
	ga_destroy(computes)
	// ga_destroy(samplers)
	ga_destroy(programs)
	ga_destroy(framebuffers)
	ga_destroy(uniform_buffers)
	ga_destroy(instanced_meshes)
	ga_destroy(indirect_buffers)

	delete(texture_units)

	logger_destroy()
}
