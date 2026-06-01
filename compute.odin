package glodin

import "core:os"
import vmem "core:mem/virtual"

import gl "vendor:OpenGL"

Compute :: distinct Index

@(private)
computes: ^Generational_Array(_Compute)

@(private)
get_compute :: proc(compute: Compute) -> ^_Compute {
	return ga_get(computes, compute)
}

@(private)
get_compute_handle :: proc(compute: Compute) -> u32 {
	return ga_get(computes, compute).handle
}

_get_compute_handle :: proc(compute: Compute) -> u32 {
	return get_compute_handle(compute)
}

@(private)
_Compute :: struct {
	using base: Base_Program,
}

@(require_results)
create_compute_file :: proc(
	path: string,
	location := #caller_location,
) -> (
	compute: Compute,
	ok:      bool,
) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return
	}
	return create_compute_source(string(data), location)
}

@(require_results)
create_compute_source :: proc(
	source: string,
	location := #caller_location,
) -> (
	compute: Compute,
	ok: bool,
) {
	id := Compute(ga_append(computes, _Compute{}, location))
	c  := ga_get(computes, id)

	err := vmem.arena_init_growing(&c.arena)
	assert(err == nil)
	c.textures.allocator = vmem.arena_allocator(&c.arena)

	c.handle, ok = gl.load_compute_source(source)
	if !ok {
		error("Failed to compile progam:", gl.get_last_error_messages(), location = location)
		return
	}
	get_uniforms_from_program(c)
	get_uniform_blocks_from_program(c, location)
	return id, true
}

dispatch_compute :: proc(
	compute: Compute,
	groups: [3]int,
	uniforms: []Uniform,
	location := #caller_location,
) {
	c := get_compute(compute)

	gl.UseProgram(c.handle)
	current_program = max(Program)

	for uniform in uniforms {
		_set_uniform(&c.base, uniform, location)
	}

	bind_program_textures(c, location)

	gl.DispatchCompute(u32(groups.x), u32(groups.y), u32(groups.z))
	gl.MemoryBarrier(gl.SHADER_IMAGE_ACCESS_BARRIER_BIT)
}

destroy_compute :: proc(compute: Compute) {
	c := get_compute(compute)
	vmem.arena_destroy(&c.arena)
	gl.DeleteProgram(c.handle)
	ga_remove(computes, compute)
}
