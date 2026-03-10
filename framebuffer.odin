package glodin

import "base:intrinsics"

import "core:mem"
import "core:slice"

import gl "vendor:OpenGL"

@(private)
framebuffer_data_allocator: mem.Allocator

@(private)
root_fb: _Framebuffer

@(private)
framebuffers: ^Generational_Array(_Framebuffer)

Framebuffer :: distinct Index

@(private)
get_framebuffer :: proc(framebuffer: Framebuffer) -> ^_Framebuffer {
	if framebuffer == {} {
		return &root_fb
	}
	fb := ga_get(framebuffers, framebuffer)
	if fb == nil {
		debugf("Framebuffer %v not found", framebuffer)
	}
	return fb
}

@(private)
get_framebuffer_handle :: proc(framebuffer: Framebuffer) -> u32 {
	if framebuffer == {} {
		return 0
	}
	fb := ga_get(framebuffers, framebuffer)
	return fb.handle
}

_get_framebuffer_handle :: proc(framebuffer: Framebuffer) -> u32 {
	fb := ga_get(framebuffers, framebuffer)
	return fb.handle
}

@(private)
_Framebuffer :: struct {
	color_textures:  []Texture,
	depth_texture:   Maybe(Texture),
	stencil_texture: Maybe(Texture),
	width, height:   int,
	samples:         int,
	handle:          u32,
	depth_stencil:   bool,
}

create_framebuffer :: proc(
	color_textures: []Texture,
	depth_texture: Maybe(Texture) = nil,
	stencil_texture: Maybe(Texture) = nil,
	location := #caller_location,
) -> (
	framebuffer: Framebuffer,
) {
	fb: _Framebuffer
	gl.CreateFramebuffers(1, &fb.handle)

	dimensions_resolved: bool

	// Bind the framebuffer instead of using the NamedFramebuffer* function, because of renderdoc
	gl.BindFramebuffer(gl.FRAMEBUFFER, fb.handle)
	current_framebuffer = max(Framebuffer)

	for color_texture, i in color_textures {
		ct := get_texture(color_texture)
		assert(!is_depth_format(ct.format) && (ct.format != .Stencil8), location = location)

		if !dimensions_resolved {
			fb.width  = ct.width
			fb.height = ct.height

			dimensions_resolved = true
		} else {
			assert(fb.width == ct.width && fb.height == ct.height)
		}

		gl.FramebufferTexture(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0 + u32(i), ct.handle, 0)
	}

	buffers := make([]u32, len(color_textures), context.temp_allocator)
	for &b, i in buffers {
		b = gl.COLOR_ATTACHMENT0 + u32(i)
	}
	gl.DrawBuffers(i32(len(buffers)), raw_data(buffers))

	fb.color_textures  = slice.clone(color_textures, framebuffer_data_allocator)
	fb.depth_texture   = depth_texture
	fb.stencil_texture = stencil_texture

	if d, ok := depth_texture.?; ok {
		d := get_texture(d)

		if !dimensions_resolved {
			fb.width = d.width
			fb.height = d.height
			dimensions_resolved = true
		}

		assert(d != nil, "Depth texture attached to framebuffer is invalid", location = location)
		assert(
			d.width == fb.width && d.height == fb.height,
			"Framebuffer textures have to have the same dimensions",
		)
		assert(is_depth_format(d.format))
		if is_depth_stencil_format(d.format) {
			gl.FramebufferTexture(gl.FRAMEBUFFER, gl.DEPTH_STENCIL_ATTACHMENT, d.handle, 0)
			fb.depth_stencil = true
			fb.stencil_texture = depth_texture
		} else {
			gl.FramebufferTexture(gl.FRAMEBUFFER, gl.DEPTH_ATTACHMENT, d.handle, 0)
		}
	}
	stencil: if s, ok := stencil_texture.?; ok {
		if fb.depth_stencil {
			warn(
				"Depth texture format include stencil, which will be ignored since an explicit stencil texture was provided",
				location = location,
			)
		}
		s := get_texture(s)
		if !dimensions_resolved {
			fb.width = s.width
			fb.height = s.height
			dimensions_resolved = true
		}
		assert(is_depth_stencil_format(s.format) || s.format == .Stencil8)
		assert(
			s.width == fb.width && s.height == fb.height,
			"Framebuffer textures have to have the same dimensions",
		)
		if is_depth_stencil_format(s.format) {
			warn(
				"Combined stencil and depth textures should be passed in as depth attachment",
				location = location,
			)
			fb.depth_stencil = false
			fb.stencil_texture = stencil_texture
		}
		gl.FramebufferTexture(gl.FRAMEBUFFER, gl.STENCIL_ATTACHMENT, s.handle, 0)
	}

	status := gl.CheckFramebufferStatus(gl.FRAMEBUFFER)
	if status != gl.FRAMEBUFFER_COMPLETE {
		error("Failed to create framebuffer:", gl.GL_Enum(status), location = location)
	}

	return cast(Framebuffer)ga_append(framebuffers, fb)
}

set_framebuffer_color_texture :: proc(framebuffer: Framebuffer, texture: Texture, index := 0) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(!is_depth_format(tex.format) && (tex.format != .Stencil8))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		// panic("Wrong texture size for framebuffer")
		gl.Viewport(0, 0, i32(tex.width), i32(tex.height))
		framebuffer.width = tex.width
		framebuffer.height = tex.height
	} // else 
	{
		gl.NamedFramebufferTexture(framebuffer.handle, gl.COLOR_ATTACHMENT0, tex.handle, 0)
		framebuffer.color_textures[index] = texture
	}
}

set_framebuffer_depth_texture :: proc(framebuffer: Framebuffer, texture: Texture) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(is_depth_format(tex.format))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		panic("Wrong texture size for framebuffer")
	} else {
		gl.NamedFramebufferTexture(framebuffer.handle, gl.DEPTH_ATTACHMENT, tex.handle, 0)
		framebuffer.depth_texture = texture
	}
}

set_framebuffer_stencil_texture :: proc(framebuffer: Framebuffer, texture: Texture) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(tex.format == .Stencil8 || is_depth_stencil_format(tex.format))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		panic("Wrong texture size for framebuffer")
	} else {
		gl.NamedFramebufferTexture(framebuffer.handle, gl.STENCIL_ATTACHMENT, tex.handle, 0)
		framebuffer.stencil_texture = texture
	}
}

set_framebuffer_depth_stencil_texture :: proc(framebuffer: Framebuffer, texture: Texture) {
	framebuffer := get_framebuffer(framebuffer)
	tex := get_texture(texture)
	assert(is_depth_stencil_format(tex.format))
	if framebuffer.width != tex.width || framebuffer.height != tex.height {
		panic("Wrong texture size for framebuffer")
	} else {
		gl.NamedFramebufferTexture(framebuffer.handle, gl.DEPTH_STENCIL_ATTACHMENT, tex.handle, 0)
		framebuffer.stencil_texture = texture
		framebuffer.depth_texture = texture
	}
}

destroy_framebuffer :: #force_inline proc(framebuffer: Framebuffer) {
	f := get_framebuffer(framebuffer)
	gl.DeleteFramebuffers(1, &f.handle)
	delete(f.color_textures, framebuffer_data_allocator)

	ga_remove(framebuffers, framebuffer)
}

Rect :: struct {
	min, max: [2]int,
}

blit_framebuffers :: proc {
	blit_framebuffer_regions,
	blit_entire_framebuffer,
}

@(require_results)
get_framebuffer_size :: proc(fb: Framebuffer) -> (width, height: int) {
	if fb == 0 {
		return root_fb.width, root_fb.height
	}
	fb := get_framebuffer(fb)
	return fb.width, fb.height
}

blit_entire_framebuffer :: proc(
	dst, src: Framebuffer,
	buffers := Draw_Buffers{.Color},
	filter: Texture_Mag_Filter = .Nearest,
) {
	src_rect, dst_rect: Rect
	src_rect.max.x, src_rect.max.y = get_framebuffer_size(src)
	dst_rect.max.x, dst_rect.max.y = get_framebuffer_size(dst)
	blit_framebuffer_regions(dst, src, dst_rect, src_rect, buffers, filter)
}

Framebuffer_Attachment :: enum {
	Color_0,
	Color_1,
	Color_2,
	Color_3,
	Color_4,
	Color_5,
	Color_6,
	Color_7,
	Color_8,
	Color_9,
	Color_10,
	Color_11,
	Color_12,
	Color_13,
	Color_14,
	Color_15,
	Color_16,
	Color_17,
	Color_18,
	Color_19,
	Color_20,
	Color_21,
	Color_22,
	Color_23,
	Color_24,
	Color_25,
	Color_26,
	Color_27,
	Color_28,
	Color_29,
	Color_30,
	Color_31,
	Depth,
	Depth_Stencil,
	Stencil,
}

@(private, rodata)
FRAMEBUFFER_ATTACHMENT_VALUES := [Framebuffer_Attachment]u32 {
	.Color_0        = gl.COLOR_ATTACHMENT0,
	.Color_1        = gl.COLOR_ATTACHMENT1,
	.Color_2        = gl.COLOR_ATTACHMENT2,
	.Color_3        = gl.COLOR_ATTACHMENT3,
	.Color_4        = gl.COLOR_ATTACHMENT4,
	.Color_5        = gl.COLOR_ATTACHMENT5,
	.Color_6        = gl.COLOR_ATTACHMENT6,
	.Color_7        = gl.COLOR_ATTACHMENT7,
	.Color_8        = gl.COLOR_ATTACHMENT8,
	.Color_9        = gl.COLOR_ATTACHMENT9,
	.Color_10       = gl.COLOR_ATTACHMENT10,
	.Color_11       = gl.COLOR_ATTACHMENT11,
	.Color_12       = gl.COLOR_ATTACHMENT12,
	.Color_13       = gl.COLOR_ATTACHMENT13,
	.Color_14       = gl.COLOR_ATTACHMENT14,
	.Color_15       = gl.COLOR_ATTACHMENT15,
	.Color_16       = gl.COLOR_ATTACHMENT16,
	.Color_17       = gl.COLOR_ATTACHMENT17,
	.Color_18       = gl.COLOR_ATTACHMENT18,
	.Color_19       = gl.COLOR_ATTACHMENT19,
	.Color_20       = gl.COLOR_ATTACHMENT20,
	.Color_21       = gl.COLOR_ATTACHMENT21,
	.Color_22       = gl.COLOR_ATTACHMENT22,
	.Color_23       = gl.COLOR_ATTACHMENT23,
	.Color_24       = gl.COLOR_ATTACHMENT24,
	.Color_25       = gl.COLOR_ATTACHMENT25,
	.Color_26       = gl.COLOR_ATTACHMENT26,
	.Color_27       = gl.COLOR_ATTACHMENT27,
	.Color_28       = gl.COLOR_ATTACHMENT28,
	.Color_29       = gl.COLOR_ATTACHMENT29,
	.Color_30       = gl.COLOR_ATTACHMENT30,
	.Color_31       = gl.COLOR_ATTACHMENT31,
	.Depth          = gl.DEPTH_ATTACHMENT,
	.Stencil        = gl.STENCIL_ATTACHMENT,
	.Depth_Stencil  = gl.DEPTH_STENCIL_ATTACHMENT,
}

Draw_Buffer_Bit :: enum {
	Color   = intrinsics.constant_log2(gl.COLOR_BUFFER_BIT),
	Depth   = intrinsics.constant_log2(gl.DEPTH_BUFFER_BIT),
	Stencil = intrinsics.constant_log2(gl.STENCIL_BUFFER_BIT),
}

Draw_Buffers :: bit_set[Draw_Buffer_Bit; u32]

blit_framebuffer_regions :: proc(
	dst, src: Framebuffer,
	dst_rect: Rect,
	src_rect: Rect,
	buffers:  Draw_Buffers       = { .Color, },
	filter:   Texture_Mag_Filter = .Nearest,
) {
	gl.BindFramebuffer(gl.READ_FRAMEBUFFER, get_framebuffer_handle(src))
	gl.BindFramebuffer(gl.DRAW_FRAMEBUFFER, get_framebuffer_handle(dst))

	gl.BlitFramebuffer(
		i32(src_rect.min.x),
		i32(src_rect.min.y),
		i32(src_rect.max.x),
		i32(src_rect.max.y),
		i32(dst_rect.min.x),
		i32(dst_rect.min.y),
		i32(dst_rect.max.x),
		i32(dst_rect.max.y),
		transmute(u32)buffers,
		u32(filter),
	)

	current_framebuffer = max(Framebuffer)
}
