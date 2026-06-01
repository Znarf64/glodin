package glodin

import gl "vendor:OpenGL"

@(private)
Texture_Sampling_Parameters :: struct {
	mag_filter:   Texture_Mag_Filter,
	min_filter:   Texture_Min_Filter,
	wrap:         [2]Texture_Wrap,
	border_color: [4]f32,
	anisotropy:   f32,
}

Sampler :: distinct Index

@(private)
samplers: ^Generational_Array(_Sampler)

@(private, require_results)
get_sampler :: proc(sampler: Sampler) -> ^_Sampler {
	return ga_get(samplers, sampler)
}

@(private, require_results)
get_sampler_texture :: proc(sampler: Sampler) -> Texture {
	return ga_get(samplers, sampler).texture
}

@(require_results)
_get_sampler_handle :: proc(sampler: Sampler) -> Texture {
	return get_sampler_texture(sampler)
}

@(private)
_Sampler :: struct {
	handle:  u32,
	texture: Texture,
	using _: Texture_Sampling_Parameters,
}

@(require_results)
create_sampler :: proc(
	texture: Texture,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	anisotropy: f32,
	location := #caller_location,
) -> Sampler {
	s: _Sampler = {
		texture      = texture,
		mag_filter   = mag_filter,
		min_filter   = min_filter,
		wrap         = wrap,
		border_color = border_color,
		anisotropy   = anisotropy,
	}

	gl.CreateSamplers(1, &s.handle)

	for w, direction in wrap {
		if w != s.wrap[direction] {
			gl.TextureParameteri(
				s.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
	}

	gl.SamplerParameteri(s.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
	gl.SamplerParameteri(s.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))

	border_color := border_color
	gl.SamplerParameterfv(s.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])

	gl.SamplerParameterf(s.handle, gl.TEXTURE_MAX_ANISOTROPY, anisotropy)

	return Sampler(ga_append(samplers, s, location))
}

Texture_Mag_Filter :: enum {
	Nearest = gl.NEAREST,
	Linear  = gl.LINEAR,
}

Texture_Min_Filter :: enum {
	Nearest                = gl.NEAREST,
	Linear                 = gl.LINEAR,
	Nearest_Mipmap_Nearest = gl.NEAREST_MIPMAP_NEAREST,
	Nearest_Mipmap_Linear  = gl.NEAREST_MIPMAP_LINEAR,
	Linear_Mipmap_Nearest  = gl.LINEAR_MIPMAP_NEAREST,
	Linear_Mipmap_Linear   = gl.LINEAR_MIPMAP_LINEAR,
}

@(rodata, private)
GL_TEXTURE_WRAP_DIRECTION := [3]u32{gl.TEXTURE_WRAP_S, gl.TEXTURE_WRAP_T, gl.TEXTURE_WRAP_R}

Texture_Wrap :: enum {
	Repeat = 0,
	Clamp_To_Edge,
	Clamp_To_Border,
	Mirrored_Repeat,
	Mirror_Clamp_To_Edge,
}

@(rodata, private)
GL_TEXTURE_WRAP := [Texture_Wrap]i32 {
	.Clamp_To_Edge        = gl.CLAMP_TO_EDGE,
	.Clamp_To_Border      = gl.CLAMP_TO_BORDER,
	.Mirrored_Repeat      = gl.MIRRORED_REPEAT,
	.Repeat               = gl.REPEAT,
	.Mirror_Clamp_To_Edge = gl.MIRROR_CLAMP_TO_EDGE,
}

