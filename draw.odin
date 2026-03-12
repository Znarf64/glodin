package glodin

import "base:intrinsics"

import glm "core:math/linalg/glsl"

import gl "vendor:OpenGL"

Draw_Mode :: enum {
	Lines        = gl.LINES,
	Triangles    = gl.TRIANGLES,
	Points       = gl.POINTS,
	Triangle_Fan = gl.TRIANGLE_FAN,
}

Depth_Func :: enum {
	Less = 0,
	Never,
	Lequal,
	Greater,
	Gequal,
	Equal,
	Notequal,
	Always,
}

DEPTH_FUNC_VALUES := [Depth_Func]u32 {
	.Never    = gl.NEVER,
	.Less     = gl.LESS,
	.Lequal   = gl.LEQUAL,
	.Greater  = gl.GREATER,
	.Gequal   = gl.GEQUAL,
	.Equal    = gl.EQUAL,
	.Notequal = gl.NOTEQUAL,
	.Always   = gl.ALWAYS,
}

Draw_Flag :: enum {
	Depth_Test,
	Stencil_Test,
	Cull_Face,
	Blend,
	Scissor,
	Sample_Shading,
}

@(private, rodata)
DRAW_FLAG_VALUES := [Draw_Flag]u32 {
	.Depth_Test     = gl.DEPTH_TEST,
	.Stencil_Test   = gl.STENCIL_TEST,
	.Cull_Face      = gl.CULL_FACE,
	.Blend          = gl.BLEND,
	.Scissor        = gl.SCISSOR_TEST,
	.Sample_Shading = gl.SAMPLE_SHADING,
}

enable :: proc(flags: ..Draw_Flag) {
	for flag in flags {
		value := DRAW_FLAG_VALUES[flag]
		gl.Enable(value)
	}
}

disable :: proc(flags: ..Draw_Flag) {
	for flag in flags {
		value := DRAW_FLAG_VALUES[flag]
		gl.Disable(value)
	}
}

set_draw_flag :: proc(flag: Draw_Flag, enable: bool) {
	value := DRAW_FLAG_VALUES[flag]
	if enable {
		gl.Enable(value)
	} else {
		gl.Disable(value)
	}
}

set_cull_face :: proc(face: Face) {
	gl.CullFace(FACE_VALUES[face])
}

set_polygon_mode :: proc(mode: Polygon_Mode, face: Face) {
	gl.PolygonMode(FACE_VALUES[face], POLYGON_MODE_VALUES[mode])
}

set_color_mask :: proc(mask: [4]bool, buffer := -1) {
	if buffer != -1 {
		gl.ColorMaski(u32(buffer), expand_values(mask))
	} else {
		gl.ColorMask(expand_values(mask))
	}
}

Stencil_Func :: enum {
	Never,
	Less,
	Lequal,
	Greater,
	Gequal,
	Equal,
	Notequal,
	Always,
}

@(private, rodata)
STENCIL_FUNC_VALUES := [Stencil_Func]u32 {
	.Never    = gl.NEVER,
	.Less     = gl.LESS,
	.Lequal   = gl.LEQUAL,
	.Greater  = gl.GREATER,
	.Gequal   = gl.GEQUAL,
	.Equal    = gl.EQUAL,
	.Notequal = gl.NOTEQUAL,
	.Always   = gl.ALWAYS,
}

Face :: enum {
	Back,
	Front,
}

@(private, rodata)
FACE_VALUES := [Face]u32 {
	.Back  = gl.BACK,
	.Front = gl.FRONT,
}

Polygon_Mode :: enum {
	Fill = 0,
	Point,
	Line,
}

@(private, rodata)
POLYGON_MODE_VALUES := [Polygon_Mode]u32 {
	.Point = gl.POINT,
	.Line  = gl.LINE,
	.Fill  = gl.FILL,
}

set_line_width :: proc(width: f32) {
	gl.LineWidth(width)
}

set_point_size :: proc(size: f32) {
	gl.PointSize(size)
}

Blend_Func :: enum {
	Zero,
	One,
	Src_Color,
	One_Minus_Src_Color,
	Dst_Color,
	One_Minus_Dst_Color,
	Src_Alpha,
	One_Minus_Src_Alpha,
	Dst_Alpha,
	One_Minus_Dst_Alpha,
	Constant_Color,
	One_Minus_Constant_Color,
	Constant_Alpha,
	One_Minus_Constant_Alpha,
	Src_Alpha_Saturate,
	Src1_Color,
	One_Minus_Src1_Color,
	Src1_Alpha,
	One_Minus_Src1_Alpha,
}

@(private, rodata)
BLEND_FUNC_VALUES := [Blend_Func]u32 {
	.Zero                     = gl.ZERO,
	.One                      = gl.ONE,
	.Src_Color                = gl.SRC_COLOR,
	.One_Minus_Src_Color      = gl.ONE_MINUS_SRC_COLOR,
	.Dst_Color                = gl.DST_COLOR,
	.One_Minus_Dst_Color      = gl.ONE_MINUS_DST_COLOR,
	.Src_Alpha                = gl.SRC_ALPHA,
	.One_Minus_Src_Alpha      = gl.ONE_MINUS_SRC_ALPHA,
	.Dst_Alpha                = gl.DST_ALPHA,
	.One_Minus_Dst_Alpha      = gl.ONE_MINUS_DST_ALPHA,
	.Constant_Color           = gl.CONSTANT_COLOR,
	.One_Minus_Constant_Color = gl.ONE_MINUS_CONSTANT_COLOR,
	.Constant_Alpha           = gl.CONSTANT_ALPHA,
	.One_Minus_Constant_Alpha = gl.ONE_MINUS_CONSTANT_ALPHA,
	.Src_Alpha_Saturate       = gl.SRC_ALPHA_SATURATE,
	.Src1_Color               = gl.SRC1_COLOR,
	.One_Minus_Src1_Color     = gl.ONE_MINUS_SRC1_COLOR,
	.Src1_Alpha               = gl.SRC1_ALPHA,
	.One_Minus_Src1_Alpha     = gl.ONE_MINUS_SRC1_ALPHA,
}

set_blend_func :: proc(source, dest: Blend_Func) {
	gl.BlendFunc(BLEND_FUNC_VALUES[source], BLEND_FUNC_VALUES[dest])
}

Blend_Equation :: enum {
	Add,
	Subtract,
	Reverse_Subtract,
	Min,
	Max,
}

@(private, rodata)
BLEND_EQUATION_VALUES := [Blend_Equation]u32 {
	.Add              = gl.FUNC_ADD,
	.Subtract         = gl.FUNC_SUBTRACT,
	.Reverse_Subtract = gl.FUNC_REVERSE_SUBTRACT,
	.Min              = gl.MIN,
	.Max              = gl.MAX,
}

set_blend_equation :: proc(e: Blend_Equation) {
	gl.BlendEquation(BLEND_EQUATION_VALUES[e])
}

set_depth_func :: proc(func: Depth_Func) {
	gl.DepthFunc(DEPTH_FUNC_VALUES[func])
}

set_depth_mask :: proc(enable: bool) {
	gl.DepthMask(enable)
}

set_depth_range :: proc(near, far: f32) {
	gl.DepthRangef(near, far)
}

set_scissor :: proc(rect: Rect) {
	gl.Scissor(
		i32(rect.min.x),
		i32(rect.min.y),
		i32(rect.max.x - rect.min.x),
		i32(rect.max.y - rect.min.y),
	)
}

Stencil_Mask :: bit_set[0 ..< 32;u32]

set_stencil_func :: proc(face: Face, func: Stencil_Func, ref: i32, mask: Stencil_Mask) {
	gl.StencilFuncSeparate(FACE_VALUES[face], STENCIL_FUNC_VALUES[func], ref, transmute(u32)mask)
}

set_stencil_mask :: proc(mask: Stencil_Mask, face: Maybe(Face) = nil) {
	if face, separate := face.?; separate {
		gl.StencilMaskSeparate(FACE_VALUES[face], transmute(u32)mask)
	} else {
		gl.StencilMask(transmute(u32)mask)
	}
}

Stencil_Op :: enum {
	Keep,
	Zero,
	Replace,
	Incr,
	Incr_Wrap,
	Decr,
	Decr_Wrap,
	Invert,
}

@(private, rodata)
STENCIL_OP_VALUES := [Stencil_Op]u32 {
	.Keep      = gl.KEEP,
	.Zero      = gl.ZERO,
	.Replace   = gl.REPLACE,
	.Incr      = gl.INCR,
	.Incr_Wrap = gl.INCR_WRAP,
	.Decr      = gl.DECR,
	.Decr_Wrap = gl.DECR_WRAP,
	.Invert    = gl.INVERT,
}

set_stencil_op :: proc(
	stencil_fail: Stencil_Op,
	depth_fail: Stencil_Op,
	depth_pass: Stencil_Op,
	face: Maybe(Face) = nil,
) {
	if face, separate := face.?; separate {
		gl.StencilOpSeparate(
			FACE_VALUES[face],
			STENCIL_OP_VALUES[stencil_fail],
			STENCIL_OP_VALUES[depth_fail],
			STENCIL_OP_VALUES[depth_pass],
		)
	} else {
		gl.StencilOp(
			STENCIL_OP_VALUES[stencil_fail],
			STENCIL_OP_VALUES[depth_fail],
			STENCIL_OP_VALUES[depth_pass],
		)
	}
}

set_min_sample_shading :: proc(ratio: f32) {
	gl.MinSampleShading(ratio)
}

@(private)
current_framebuffer := max(Framebuffer)

draw :: proc {
	draw_mesh,
	draw_instanced_mesh,
}

@(private)
prepare_drawing :: proc(
	framebuffer: Framebuffer,
	program: Program,
	vertex_type: typeid,
	per_instance_type: typeid,
	location: Source_Code_Location,
) {
	if framebuffer != current_framebuffer {
		current_framebuffer = framebuffer

		framebuffer := get_framebuffer(framebuffer)
		gl.BindFramebuffer(gl.FRAMEBUFFER, framebuffer.handle)
		gl.Viewport(0, 0, i32(framebuffer.size.x), i32(framebuffer.size.y))
	}
	set_program_active(program)

	program := get_program(program)

	bind_program_textures(program, location)

	check_program_vertex_type(program, vertex_type, per_instance_type, location)
}

@(private)
texture_units: []Texture

@(private)
bind_program_textures :: proc(program: ^Base_Program, location: Source_Code_Location) {
	n := len(program.textures)
	assert(n < int(max_texture_units), location = location)

	// is this necessary? No.
	size := n * (size_of(Texture) + size_of(bool)) + int(max_texture_units) * size_of(bool)
	scratch_data := intrinsics.alloca(size, align_of(Texture))
	intrinsics.mem_zero(&scratch_data[0], size)

	textures := ([^]Texture)(scratch_data[:])[:n]
	done := ([^]bool)(scratch_data[n * size_of(Texture):])[:n]
	used := ([^]bool)(scratch_data[n * size_of(Texture) + n:])[:max_texture_units]

	assert(len(textures) * size_of(Texture) + len(done) + len(used) == size)

	n_done := 0

	for texture, i in program.textures {
		for bound, unit in texture_units {
			if bound == texture.texture {
				gl.Uniform1i(texture.location, i32(unit))
				used[unit] = true
				done[i] = true
				n_done += 1
				break
			}
		}
	}

	if n == n_done {
		return
	}

	bind_missing_textures: for texture, i in program.textures {
		if !done[i] {
			for &tex, unit in texture_units {
				if used[unit] do continue
				used[unit] = true

				tex = texture.texture
				gl.Uniform1i(texture.location, i32(unit))

				t := get_texture(texture.texture)
				gl.BindTextureUnit(u32(unit), t.handle)
				if is_valid_compute_shader_input_format(t.format) {
					gl.BindImageTexture(
						u32(unit),
						t.handle,
						0,
						false,
						0,
						gl.READ_WRITE,
						u32(t.format),
					)
				}
				continue bind_missing_textures
			}

			error("Ran out of texture units", location)
		}
	}
}

draw_mesh :: proc(
	framebuffer: Framebuffer,
	program:     Program,
	mesh:        Mesh,
	mode:        Draw_Mode       = .Triangles,
	indirect:    Indirect_Buffer = {},
	count:       int             = -1,
	location := #caller_location,
) {
	mesh := get_mesh(mesh)
	prepare_drawing(framebuffer, program, mesh.vertex_type, nil, location)

	gl.BindVertexArray(mesh.vao)
	if indirect != 0 {
		indirect := get_indirect_buffer(indirect)
		gl.BindBuffer(gl.DRAW_INDIRECT_BUFFER, indirect.handle)

		indirect_count := count >= 0 ? i32(count) : i32(indirect.size) / indirect.stride
		if mesh.ibo == 0 {
			gl.MultiDrawArraysIndirect(u32(mode), nil, indirect_count, indirect.stride)
		} else {
			gl.MultiDrawElementsIndirect(u32(mode), mesh.index_type, nil, indirect_count, indirect.stride)
		}
	} else {
		count := count >= 0 ? i32(count) : mesh.count
		if mesh.ibo == 0 {
			gl.DrawArrays(u32(mode), 0, count)
		} else {
			gl.DrawElements(u32(mode), count, mesh.index_type, nil)
		}
	}
}

draw_instanced_mesh :: proc(
	framebuffer: Framebuffer,
	program: Program,
	instanced_mesh: Instanced_Mesh,
	mode: Draw_Mode = .Triangles,
	location := #caller_location,
) {
	instanced_mesh := get_instanced_mesh(instanced_mesh)
	mesh := get_mesh(instanced_mesh.mesh)
	prepare_drawing(framebuffer, program, mesh.vertex_type, instanced_mesh.instance_type, location)

	gl.BindVertexArray(mesh.vao)
	if mesh.ibo == 0 {
		gl.DrawArraysInstanced(u32(mode), 0, mesh.count, instanced_mesh.instance_count)
	} else {
		gl.DrawElementsInstanced(
			u32(mode),
			mesh.count,
			mesh.index_type,
			nil,
			instanced_mesh.instance_count,
		)
	}
}

clear_color :: proc(framebuffer: Framebuffer, color: glm.vec4, index: int = 0) {
	color := color
	gl.ClearNamedFramebufferfv(
		get_framebuffer_handle(framebuffer),
		gl.COLOR,
		i32(index),
		&color[0],
	)
}

clear_depth :: proc(framebuffer: Framebuffer, depth: f32) {
	depth := depth
	gl.ClearNamedFramebufferfv(get_framebuffer_handle(framebuffer), gl.DEPTH, 0, &depth)
}

clear_stencil :: proc(framebuffer: Framebuffer, value: u32) {
	value := i32(value)
	gl.ClearNamedFramebufferiv(get_framebuffer_handle(framebuffer), gl.STENCIL, 0, &value)
}
