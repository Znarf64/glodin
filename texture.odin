package glodin

import "base:intrinsics"

import "core:image"
import "core:math"
import "core:reflect"
import "core:slice"
import "core:strings"
import "core:os"

import gl "vendor:OpenGL"
import stbi "vendor:stb/image"

Texture :: distinct Index

@(private)
textures: ^Generational_Array(_Texture)

@(private, require_results)
get_texture :: proc(texture: Texture) -> ^_Texture {
	return ga_get(textures, texture)
}

@(private, require_results)
get_texture_handle :: proc(texture: Texture) -> (handle: u32, ok: bool) {
	ptr := ga_get(textures, texture)
	if ptr == nil {
		return
	}
	return ptr.handle, true
}

@(require_results)
_get_texture_handle :: proc(texture: Texture) -> (handle: u32, ok: bool) {
	return get_texture_handle(texture)
}

@(require_results)
get_texture_info :: proc(texture: Texture) -> (info: _Texture, ok: bool) {
	ptr := get_texture(texture)
	if ptr == nil {
		return
	}
	return ptr^, true
}

Texture_Kind :: enum {
	Texture_2D = 0,
	Texture_1D,
	Texture_3D,
	Cube_Map,
	Texture_2D_Array,
	Texture_1D_Array,
	Cube_Map_Array,
}

@(private, rodata)
TEXTURE_KIND_VALUES := [Texture_Kind]u32{
	.Texture_2D       = gl.TEXTURE_2D,
	.Texture_1D       = gl.TEXTURE_1D,
	.Texture_3D       = gl.TEXTURE_3D,
	.Cube_Map         = gl.TEXTURE_CUBE_MAP,
	.Texture_2D_Array = gl.TEXTURE_2D_ARRAY,
	.Texture_1D_Array = gl.TEXTURE_1D_ARRAY,
	.Cube_Map_Array   = gl.TEXTURE_CUBE_MAP_ARRAY,
}

@(private, rodata)
TEXTURE_KIND_VALUES_MULTISAMPLED := #partial[Texture_Kind]u32{
	.Texture_2D       = gl.TEXTURE_2D_MULTISAMPLE,
	.Texture_2D_Array = gl.TEXTURE_2D_MULTISAMPLE_ARRAY,
}

@(private)
_Texture :: struct {
	handle:        u32,
	size:          [2]int,
	layers:        int,
	samples:       int,
	format:        Texture_Format,
	mag_filter:    Texture_Mag_Filter,
	min_filter:    Texture_Min_Filter,
	wrap:          [2]Texture_Wrap,
	border_color:  [4]f32,
	anisotropy:    f32,
	count:         int,
	kind:          Texture_Kind,
}

@(require_results)
create_texture_array :: proc(
	width, height: int,
	count:         int,
	format:        Texture_Format     = .RGBA8,
	layers:        int                = 1,
	samples:       int                = 0,
	mag_filter:    Texture_Mag_Filter = .Linear,
	min_filter:    Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap:          [2]Texture_Wrap    = {},
	border_color:  [4]f32             = {},
	location:                         = #caller_location,
) -> Texture {
	t: _Texture = {
		size         = { width, height, },
		format       = format,
		min_filter   = min_filter,
		mag_filter   = mag_filter,
		count        = count,
		border_color = border_color,
	}

	if samples > 1 {
		samples := check_multisampling_parameters(
			format,
			samples,
			layers,
			mag_filter,
			min_filter,
			wrap,
			border_color,
			location,
		)
		t.samples = samples
		gl.CreateTextures(gl.TEXTURE_2D_MULTISAMPLE_ARRAY, 1, &t.handle)
		gl.TextureStorage3DMultisample(
			t.handle,
			i32(samples),
			u32(format),
			i32(width),
			i32(height),
			i32(count),
			false,
		)
	} else {
		t.samples = 0
		layers := check_texture_layer_count(layers, location, width, height)
		t.layers = layers

		gl.CreateTextures(gl.TEXTURE_2D_ARRAY, 1, &t.handle)
		gl.TextureStorage3D(
			t.handle,
			i32(layers),
			u32(format),
			i32(width),
			i32(height),
			i32(count),
		)

		for w, direction in wrap {
			gl.TextureParameteri(
				t.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
		gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
		gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))

		border_color := border_color
		gl.TextureParameterfv(t.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])
	}

	return Texture(ga_append(textures, t, location))
}

set_texture_array_data :: proc {
	set_texture_array_data_at,
	set_texture_array_data_all,
}

set_texture_array_data_at :: proc(ta: Texture, data: $T/[]$E, location := #caller_location) {
	ta := get_texture_array(ta)
	assert(ta.samples == 0, "Cannot set texture data of multisampled texture")
	assert(len(data) == ta.width * ta.height * ta.count)
	format, type := texture_parameters_from_slice(data, location)
	gl.TextureSubImage3D(
		ta.handle,
		0,
		0,
		0,
		i32(ta.width),
		i32(ta.height),
		0,
		format,
		type,
		raw_data(data),
	)
}

set_texture_array_data_all :: proc(ta: Texture, index: int, data: $T/[]$E) {
	texture := get_texture(texture)
	assert(texture.samples == 0, "Cannot set texture data of multisampled texture")
	assert(len(data) == texture.width * texture.height)
	format, type := texture_parameters_from_slice(data)
	gl.TextureSubImage3D(
		texture.handle,
		0,
		0,
		0,
		i32(texture.width),
		i32(texture.height),
		i32(index),
		format,
		type,
		raw_data(data),
	)
}

get_texture_array_data :: proc(ta: Texture, data: $T/[]$E, location := #caller_location) {
	ta := get_texture(tex)^
	assert(len(data) == ta.width * ta.height * ta.count)
	format, type := texture_parameters_from_slice(data, location)
	gl.GetTextureImage(ta.handle, 0, format, type, i32(len(data) * size_of(E)), &data[0])
}

Cube_Map_Face :: enum {
	Positive_X,
	Negative_X,
	Positive_Y,
	Negative_Y,
	Positive_Z,
	Negative_Z,
}

@(private, rodata)
CUBE_MAP_FACE_VALUES := [Cube_Map_Face]u32{
	.Positive_X = gl.TEXTURE_CUBE_MAP_POSITIVE_X,
	.Negative_X = gl.TEXTURE_CUBE_MAP_NEGATIVE_X,
	.Positive_Y = gl.TEXTURE_CUBE_MAP_POSITIVE_Y,
	.Negative_Y = gl.TEXTURE_CUBE_MAP_NEGATIVE_Y,
	.Positive_Z = gl.TEXTURE_CUBE_MAP_POSITIVE_Z,
	.Negative_Z = gl.TEXTURE_CUBE_MAP_NEGATIVE_Z,
}

@(require_results)
create_cube_map :: proc(
	width:      int,
	format:     Texture_Format     = .RGBA8,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Linear_Mipmap_Nearest,
	location := #caller_location,
) -> Texture {
	t: _Texture = {
		size       = width,
		format     = format,
		min_filter = min_filter,
		mag_filter = mag_filter,
		kind       = .Cube_Map,
	}

	gl.CreateTextures(gl.TEXTURE_CUBE_MAP, 1, &t.handle)
	gl.TextureStorage2D(t.handle, 1, u32(format), i32(width), i32(width))
	gl.TextureParameteri(t.handle, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(t.handle, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(t.handle, gl.TEXTURE_WRAP_R, gl.CLAMP_TO_EDGE)
	gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
	gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))
	return Texture(ga_append(textures, t, location))
}

@(private, require_results)
texture_parameters_from_slice :: proc(
	data: $T/[]$E,
	internal_format: Texture_Format,
	location: Source_Code_Location,
) -> (
	format, type: u32,
) {
	is_float := is_float_format(internal_format)
	elem_type: typeid
	when intrinsics.type_is_array(E) {
		N :: len(E)
		when N == 1 {
			format = is_float ? gl.RED : gl.RED_INTEGER
		} else when N == 2 {
			format = is_float ? gl.RG : gl.RG_INTEGER
		} else when N == 3 {
			format = is_float ? gl.RGB : gl.RGBA_INTEGER
		} else when N == 4 {
			format = is_float ? gl.RGBA : gl.RGBA_INTEGER
		} else {
			#panic("Invalid texture data type, array size has to be between 1 and 4")
		}
		#assert(
			intrinsics.type_is_float(intrinsics.type_elem_type(E)) ||
			intrinsics.type_is_integer(intrinsics.type_elem_type(E)),
			"Invalid texture data type",
		)
		elem_type = intrinsics.type_elem_type(E)
	} else {
		#assert(
			intrinsics.type_is_float(E) || intrinsics.type_is_integer(E),
			"Invalid texture data type",
		)
		format = is_float ? gl.RED : gl.RED_INTEGER
		elem_type = E
	}

	elem_ti := type_info_of(elem_type)
	#partial switch v in elem_ti.variant {
	case reflect.Type_Info_Integer:
		switch elem_ti.size {
		case 1:
			type = v.signed ? gl.BYTE : gl.UNSIGNED_BYTE
		case 2:
			type = v.signed ? gl.SHORT : gl.UNSIGNED_SHORT
		case 4:
			type = v.signed ? gl.INT : gl.UNSIGNED_INT
		case 8, 16:
			panic("Invalid texture component integer size:", elem_ti.size, location = location)
		}
	case reflect.Type_Info_Float:
		switch elem_ti.size {
		case 2:
			type = gl.HALF_FLOAT
		case 4:
			type = gl.FLOAT
		case 8:
			panic("Invalid texture component float size:", elem_ti.size, location = location)
		}
	case:
		unreachable()
	}

	return
}

set_cube_map_face_texture :: proc(
	cm: Texture,
	face: Cube_Map_Face,
	data: $T/[]$E,
	location := #caller_location,
) {
	cm := get_texture(cm)
	assert(cm.kind == .Cube_Map)
	assert(len(data) == cm.size.x * cm.size.x)
	format, type := texture_parameters_from_slice(data, cm.format, location)
	gl.TextureSubImage3D(
		cm.handle,
		0,
		0,
		0,
		i32(face),
		i32(cm.size.x),
		i32(cm.size.x),
		1,
		format,
		type,
		raw_data(data),
	)
}

get_texture_data :: proc(
	texture: Texture,
	data: $T/[]$E,
	layer := 0,
	location := #caller_location,
) {
	texture := get_texture(texture)^
	assert(
		len(data) == (texture.size.x >> uint(layer)) * (texture.size.y >> uint(layer)),
		location = location,
	)
	format, type := texture_parameters_from_slice(data, texture.format, location)
	gl.GetTextureImage(
		texture.handle,
		i32(layer),
		format,
		type,
		i32(len(data) * size_of(E)),
		&data[0],
	)
}

write_texture_to_png :: proc {
	write_texture_to_png_default,
	_write_texture_to_png,
}

@(private)
write_texture_to_png_default :: proc(tex: Texture, file_name: string) -> bool {
	return _write_texture_to_png(tex, file_name, 4)
}

@(private)
_write_texture_to_png :: proc(
	tex: Texture,
	file_name: string,
	$C: int,
	location := #caller_location,
) -> (
	ok: bool,
) where 1 <=
	C,
	C <=
	4 {
	t := get_texture(tex)
	data := make([][C]byte, t.size.x * t.size.y, context.temp_allocator)
	get_texture_data(tex, data, 0, location)
	return(
		stbi.write_png(
			strings.clone_to_cstring(file_name, context.temp_allocator),
			i32(t.size.x),
			i32(t.size.y),
			i32(C),
			raw_data(data),
			0,
		) !=
		0 \
	)
}

Texture_Component_Type :: enum {
	Color,
	Uint,
	Int,
	S_Norm,
	Float,
	Depth,
	Depth_Stencil,
	Depthf,
	Depthf_Stencil,
	Stencil,
}


@(require_results)
format_channels :: proc(format: Texture_Format) -> (channels: int) {
	switch format {
	case .R8:
		return 1
	case .R8_SNORM:
		return 1
	case .R16:
		return 1
	case .R16_SNORM:
		return 1
	case .RG8:
		return 2
	case .RG8_SNORM:
		return 2
	case .RG16:
		return 2
	case .RG16_SNORM:
		return 2
	case .R3_G3_B2:
		return 3
	case .RGB4:
		return 3
	case .RGB5:
		return 3
	case .RGB8:
		return 3
	case .RGB8_SNORM:
		return 3
	case .RGB10:
		return 3
	case .RGB12:
		return 3
	case .RGB16_SNORM:
		return 3
	case .RGBA2:
		return 4
	case .RGBA4:
		return 4
	case .RGB5_A1:
		return 4
	case .RGBA8:
		return 4
	case .RGBA8_SNORM:
		return 4
	case .RGB10_A2:
		return 4
	case .RGB10_A2UI:
		return 4
	case .RGBA12:
		return 4
	case .RGBA16:
		return 4
	case .RGBA16_SNORM:
		return 4
	case .SRGB8:
		return 3
	case .SRGB8_ALPHA8:
		return 4
	case .R16F:
		return 1
	case .RG16F:
		return 2
	case .RGB16F:
		return 3
	case .RGBA16F:
		return 4
	case .R32F:
		return 1
	case .RG32F:
		return 2
	case .RGB32F:
		return 3
	case .RGBA32F:
		return 4
	case .R11F_G11F_B10F:
		return 3
	case .RGB9_E5:
		return 3
	case .R8I:
		return 1
	case .R8UI:
		return 1
	case .R16I:
		return 1
	case .R16UI:
		return 1
	case .R32I:
		return 1
	case .R32UI:
		return 1
	case .RG8I:
		return 2
	case .RG8UI:
		return 2
	case .RG16I:
		return 2
	case .RG16UI:
		return 2
	case .RG32I:
		return 2
	case .RG32UI:
		return 2
	case .RGB8I:
		return 3
	case .RGB8UI:
		return 3
	case .RGB16I:
		return 3
	case .RGB16UI:
		return 3
	case .RGB32I:
		return 3
	case .RGB32UI:
		return 3
	case .RGBA8I:
		return 4
	case .RGBA8UI:
		return 4
	case .RGBA16I:
		return 4
	case .RGBA16UI:
		return 4
	case .RGBA32I:
		return 4
	case .RGBA32UI:
		return 4
	case .Depth16:
		return 1
	case .Depth24:
		return 1
	case .Depth32f:
		return 1
	case .Depth24_Stencil8:
		return 2
	case .Depth32f_Stencil8:
		return 2
	case .Stencil8:
		return 1
	}
	unreachable()
}

set_raw_texture_data :: proc(texture: Texture, data: []byte, location := #caller_location) {
	texture := get_texture(texture)
	assert(texture.samples == 0, "Cannot set texture data of multisampled texture")
	assert(len(data) == texture.size.x * texture.size.y)
	format, type := texture_parameters_from_slice(data, texture.format, location)
	gl.TextureSubImage2D(
		texture.handle,
		0,
		0,
		0,
		i32(texture.size.x),
		i32(texture.size.y),
		format,
		type,
		raw_data(data),
	)
}

// if width/height is less than 0, it will be treated as the texture's width/height
set_texture_data :: proc(
	texture: Texture,
	data: $T/[]$E,
	x      := 0,
	y      := 0,
	width  := -1,
	height := -1,
	layer  := 0,
	location := #caller_location,
) {
	texture := get_texture(texture)
	if layer >= texture.layers {
		errorf(
			"Cannot set texture data at layer %v, since it is out of bounds for texture with %v layers",
			layer,
			texture.layers,
		)
		return
	}

	lw, lh := texture.size.x >> uint(layer), texture.size.y >> uint(layer)
	w, h := width, height
	if w < 0 {
		w = lw
	}
	if h < 0 {
		h = lh
	}

	if x < 0 {
		errorf(
			"x parameter of `" + #procedure + "` can not be negative, got: %v",
			x,
			location = location,
		)
	}
	if y < 0 {
		errorf(
			"y parameter of `" + #procedure + "` can not be negative, got: %v",
			y,
			location = location,
		)
	}
	if w + x > texture.size.x {
		errorf(
			"Invalid x dimensions for `" + #procedure + "`: x: %v, width: %v, layer width: %v",
			x,
			width,
			lw,
			location = location,
		)
		return
	}
	if h + y > texture.size.y {
		errorf(
			"Invalid y dimensions for `" + #procedure + "`: y: %v, height: %v, layer height: %v",
			y,
			height,
			lh,
			location = location,
		)
		return
	}

	assert(texture.samples == 0, "Cannot set texture data of multisampled texture")
	assertf(
		len(data) == w * h,
		"Size of data does not match dimensions: %v != %v * %v = %v",
		len(data),
		w,
		h,
		w * h,
	)
	format, type := texture_parameters_from_slice(data, texture.format, location)
	gl.TextureSubImage2D(
		texture.handle,
		i32(layer),
		i32(x),
		i32(y),
		i32(w),
		i32(h),
		format,
		type,
		raw_data(data),
	)
}

create_texture :: proc {
	create_texture_empty,
	create_texture_from_file,
	create_texture_from_file_data,
}

@(require_results)
create_texture_from_file :: proc(
	path: string,
	layers := 1,
	image_options: image.Options = {},
	location := #caller_location,
) -> (
	texture: Texture,
	ok:      bool,
) {
	data, err := os.read_entire_file(path, context.temp_allocator)
	if err != nil {
		return
	}
	return create_texture_from_file_data(data, path, layers, image_options, location)
}

@(require_results)
create_texture_from_file_data :: proc(
	data: []byte,
	path: string = "",
	layers := 1,
	image_options: image.Options = {},
	location := #caller_location,
) -> (
	texture: Texture,
	ok:      bool,
) {
	img, err := image.load(data, image_options, context.temp_allocator)
	if err != nil {
		errorf(
			"Failed to load image from path '%v', due to error: '%v'",
			path,
			err,
			location = location,
		)
		return
	}
	format: Texture_Format
	switch img.channels {
	case 1:
		format = .R8
	case 2:
		format = .RG8
	case 3:
		format = .RGB8
	case 4:
		format = .RGBA8
	case:
		return
	}
	texture = create_texture(img.width, img.height, format, layers, location = location)
	switch img.channels {
	case 1:
		set_texture_data(texture, slice.reinterpret([][1]byte, img.pixels.buf[:]))
	case 2:
		set_texture_data(texture, slice.reinterpret([][2]byte, img.pixels.buf[:]))
	case 3:
		set_texture_data(texture, slice.reinterpret([][3]byte, img.pixels.buf[:]))
	case 4:
		set_texture_data(texture, slice.reinterpret([][4]byte, img.pixels.buf[:]))
	}
	if layers > 1 {
		generate_mipmaps(texture)
	}

	ok = true
	return
}

set_texture_sampling_state :: proc(
	texture: Texture,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	location := #caller_location,
) {
	t := get_texture(texture)
	if t.samples != 0 {
		error(
			"Multisampled textures cannot be sampled, ignoring sampling state changes",
			location = location,
		)
		return
	}

	for w, direction in wrap {
		if w != t.wrap[direction] {
			gl.TextureParameteri(
				t.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
	}

	if t.mag_filter != mag_filter do gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
	if t.min_filter != min_filter do gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))

	border_color := border_color
	if t.border_color != border_color do gl.TextureParameterfv(t.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])

	t.mag_filter = mag_filter
	t.min_filter = min_filter
	t.wrap = wrap
	t.border_color = border_color
}

@(private = "file", require_results)
check_multisampling_parameters :: proc(
	format:       Texture_Format,
	layers:       int,
	samples:      int,
	mag_filter:   Texture_Mag_Filter = .Linear,
	min_filter:   Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap:         [2]Texture_Wrap    = {},
	border_color: [4]f32             = {},
	location:     Source_Code_Location,
) -> (
	corrected_samples: int,
) {
	corrected_samples = samples
	if intrinsics.count_ones(corrected_samples) != 1 {
		// go down to the next smaller power of two
		new_samples := 1 << uint(63 - intrinsics.count_leading_zeros(corrected_samples))
		errorf(
			"The number of samples for multisampled textures has to be a power of two, got: '%v'. Proceeding with %v samples",
			samples,
			new_samples,
			location = location,
		)
		corrected_samples = new_samples
	}
	max_samples: i32
	if is_depth_format(format) {
		gl.GetIntegerv(gl.MAX_DEPTH_TEXTURE_SAMPLES, &max_samples)
	} else {
		gl.GetIntegerv(gl.MAX_COLOR_TEXTURE_SAMPLES, &max_samples)
	}
	if corrected_samples > int(max_samples) {
		errorf(
			"Number of textures samples requested (%v) exceeds maximum supported value. Proceeding with %v samples.",
			corrected_samples,
			max_samples,
			location = location,
		)
		corrected_samples = int(max_samples)
	}

	if mag_filter != .Linear {
		warnf(
			"Texture sampler state `mag_filter` explictly set to value `%v` for multisampled texture which can not be sampled",
			mag_filter,
			location = location,
		)
	}
	if min_filter != .Nearest_Mipmap_Linear {
		warnf(
			"Texture sampler state `min_filter` explictly set to value `%v` for multisampled texture which can not be sampled",
			min_filter,
			location = location,
		)
	}
	if wrap != {} {
		warnf(
			"Texture sampler state `wrap` explictly set to value `%v` for multisampled texture which can not be sampled",
			wrap,
			location = location,
		)
	}
	if layers != 1 {
		warnf(
			"Multisampled textures cannot be layered, ignoring explicitly set value for layer count. Value: `%v`",
			layers,
			location = location,
		)
	}
	if border_color != {} {
		warnf(
			"Texture sampler state `border_color` explictly set to value `%v` for multisampled texture which can not be sampled",
			border_color,
			location = location,
		)
	}

	return corrected_samples
}

@(private = "file", require_results)
check_texture_layer_count :: proc(
	layers: int,
	location: Source_Code_Location,
	dimensions: ..int,
) -> (
	corrected: int,
) {
	max_mips := max_texture_mipmaps(..dimensions)
	if layers == 0 {
		errorf(
			"Layer count has to be at least one, was %v proceeding with 1",
			layers,
			location = location,
		)
		return 1
	}
	if layers < 1 {
		debugf(
			"Layer count below 0, using maximum number of mipmaps for dimensions, which is %v",
			max_mips,
			location = location,
		)
		return max_mips
	}

	return layers
}

generate_mipmaps :: proc(texture: Texture, location := #caller_location) {
	handle, ok := get_texture_handle(texture)
	if !ok {
		error("Can not generate texture mipmaps: Invalid texture handle", location = location)
		return
	}
	gl.GenerateTextureMipmap(handle)
}

@(require_results)
create_texture_with_data :: proc(
	width, height: int,
	data: $T/[]$E,
	format: Texture_Format = .RGBA8,
	layers: int = 1,
	samples: int = 0,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	location := #caller_location,
) -> Texture {
	texture := create_texture_empty(
		width,
		height,
		format,
		layers,
		samples,
		mag_filter,
		min_filter,
		wrap,
		border_color,
		location,
	)

	set_texture_data(texture, data)

	return texture
}

@(require_results)
create_texture_empty :: proc(
	width, height: int,
	format: Texture_Format = .RGBA8,
	layers: int = 1,
	samples: int = 0,
	mag_filter: Texture_Mag_Filter = .Linear,
	min_filter: Texture_Min_Filter = .Nearest_Mipmap_Linear,
	wrap: [2]Texture_Wrap = {},
	border_color: [4]f32 = {},
	location := #caller_location,
) -> Texture {
	t: _Texture = {
		size         = { width, height, },
		format       = format,
		min_filter   = min_filter,
		mag_filter   = mag_filter,
		border_color = border_color,
	}

	if samples > 1 {
		samples := check_multisampling_parameters(
			format,
			layers,
			samples,
			mag_filter,
			min_filter,
			wrap,
			border_color,
			location,
		)
		t.samples = samples
		gl.CreateTextures(gl.TEXTURE_2D_MULTISAMPLE, 1, &t.handle)
		gl.TextureStorage2DMultisample(
			t.handle,
			i32(samples),
			u32(format),
			i32(width),
			i32(height),
			false,
		)
	} else {
		t.samples = 0
		layers   := check_texture_layer_count(layers, location, width, height)
		t.layers  = layers

		gl.CreateTextures(gl.TEXTURE_2D, 1, &t.handle)
		gl.TextureStorage2D(t.handle, i32(layers), u32(format), i32(width), i32(height))

		for w, direction in wrap {
			gl.TextureParameteri(
				t.handle,
				GL_TEXTURE_WRAP_DIRECTION[direction],
				GL_TEXTURE_WRAP[w],
			)
		}
		gl.TextureParameteri(t.handle, gl.TEXTURE_MAG_FILTER, i32(mag_filter))
		gl.TextureParameteri(t.handle, gl.TEXTURE_MIN_FILTER, i32(min_filter))
		gl.TextureParameterf(t.handle, gl.TEXTURE_MAX_ANISOTROPY, 16)

		border_color := border_color
		gl.TextureParameterfv(t.handle, gl.TEXTURE_BORDER_COLOR, &border_color[0])
	}

	return Texture(ga_append(textures, t, location))
}

destroy_texture :: #force_inline proc(texture: Texture, location := #caller_location) {
	t, ok := get_texture_handle(texture)
	if !ok {
		error("Tried to delete invalid texture")
		return
	}
	gl.DeleteTextures(1, &t)
	ga_remove(textures, texture)
}

@(require_results)
get_texture_size_2d :: proc(texture: Texture, location := #caller_location) -> [2]int {
	t := get_texture(texture)
	assert(t.kind == .Texture_2D, location = location)
	return t.size
}

copy_texture_data_2d :: proc(
	dst, src:                 Texture,
	#no_broadcast size:       [2]int = -1,
	#no_broadcast src_offset: [2]int = 0,
	#no_broadcast dst_offset: [2]int = 0,
	src_level:                int    = 0,
	dst_level:                int    = 0,
	location := #caller_location,
) {
	dst := get_texture(dst)
	src := get_texture(src)

	size := size
	for &s, i in size {
		max_size := min(dst.size[i] - dst_offset[i], src.size[i] - src_offset[i])
		if s < 0 {
			s = max_size
		} else {
			assert(s <= max_size, location = location)
		}
	}

	assert(dst.kind == .Texture_2D, location = location)
	assert(src.kind == .Texture_2D, location = location)
	gl.CopyImageSubData(
		src.handle,
		gl.TEXTURE_2D,
		i32(src_level),
		i32(src_offset.x),
		i32(src_offset.y),
		0,
		dst.handle,
		gl.TEXTURE_2D,
		i32(dst_level),
		i32(dst_offset.x),
		i32(dst_offset.y),
		0,
		i32(size.x),
		i32(size.y),
		1,
	)
}

Texture_Format :: enum {
	R8                = gl.R8,
	R8_SNORM          = gl.R8_SNORM,
	R16               = gl.R16,
	R16_SNORM         = gl.R16_SNORM,
	RG8               = gl.RG8,
	RG8_SNORM         = gl.RG8_SNORM,
	RG16              = gl.RG16,
	RG16_SNORM        = gl.RG16_SNORM,
	R3_G3_B2          = gl.R3_G3_B2,
	RGB4              = gl.RGB4,
	RGB5              = gl.RGB5,
	RGB8              = gl.RGB8,
	RGB8_SNORM        = gl.RGB8_SNORM,
	RGB10             = gl.RGB10,
	RGB12             = gl.RGB12,
	RGB16_SNORM       = gl.RGB16_SNORM,
	RGBA2             = gl.RGBA2,
	RGBA4             = gl.RGBA4,
	RGB5_A1           = gl.RGB5_A1,
	RGBA8             = gl.RGBA8,
	RGBA8_SNORM       = gl.RGBA8_SNORM,
	RGB10_A2          = gl.RGB10_A2,
	RGB10_A2UI        = gl.RGB10_A2UI,
	RGBA12            = gl.RGBA12,
	RGBA16            = gl.RGBA16,
	RGBA16_SNORM      = gl.RGBA16_SNORM,
	SRGB8             = gl.SRGB8,
	SRGB8_ALPHA8      = gl.SRGB8_ALPHA8,
	R16F              = gl.R16F,
	RG16F             = gl.RG16F,
	RGB16F            = gl.RGB16F,
	RGBA16F           = gl.RGBA16F,
	R32F              = gl.R32F,
	RG32F             = gl.RG32F,
	RGB32F            = gl.RGB32F,
	RGBA32F           = gl.RGBA32F,
	R11F_G11F_B10F    = gl.R11F_G11F_B10F,
	RGB9_E5           = gl.RGB9_E5,
	R8I               = gl.R8I,
	R8UI              = gl.R8UI,
	R16I              = gl.R16I,
	R16UI             = gl.R16UI,
	R32I              = gl.R32I,
	R32UI             = gl.R32UI,
	RG8I              = gl.RG8I,
	RG8UI             = gl.RG8UI,
	RG16I             = gl.RG16I,
	RG16UI            = gl.RG16UI,
	RG32I             = gl.RG32I,
	RG32UI            = gl.RG32UI,
	RGB8I             = gl.RGB8I,
	RGB8UI            = gl.RGB8UI,
	RGB16I            = gl.RGB16I,
	RGB16UI           = gl.RGB16UI,
	RGB32I            = gl.RGB32I,
	RGB32UI           = gl.RGB32UI,
	RGBA8I            = gl.RGBA8I,
	RGBA8UI           = gl.RGBA8UI,
	RGBA16I           = gl.RGBA16I,
	RGBA16UI          = gl.RGBA16UI,
	RGBA32I           = gl.RGBA32I,
	RGBA32UI          = gl.RGBA32UI,
	Depth32f          = gl.DEPTH_COMPONENT32F,
	Depth24           = gl.DEPTH_COMPONENT24,
	Depth16           = gl.DEPTH_COMPONENT16,
	Depth32f_Stencil8 = gl.DEPTH32F_STENCIL8,
	Depth24_Stencil8  = gl.DEPTH24_STENCIL8,
	Stencil8          = gl.STENCIL_INDEX8,
}

@(require_results)
is_depth_stencil_format :: proc(format: Texture_Format) -> bool {
	#partial switch format {
	case .Depth32f_Stencil8, .Depth24_Stencil8:
		return true
	case:
		return false
	}
}

@(require_results)
is_depth_format :: proc(format: Texture_Format) -> bool {
	#partial switch format {
	case .Depth32f, .Depth24, .Depth16, .Depth32f_Stencil8, .Depth24_Stencil8:
		return true
	case:
		return false
	}
}

@(require_results)
is_float_format :: proc(format: Texture_Format) -> bool {
	#partial switch format {
	case .R8,
	     .R8_SNORM,
	     .R16,
	     .R16_SNORM,
	     .RG8,
	     .RG8_SNORM,
	     .RG16,
	     .RG16_SNORM,
	     .R3_G3_B2,
	     .RGB4,
	     .RGB5,
	     .RGB8,
	     .RGB8_SNORM,
	     .RGB10,
	     .RGB12,
	     .RGB16_SNORM,
	     .RGBA2,
	     .RGBA4,
	     .RGB5_A1,
	     .RGBA8,
	     .RGBA8_SNORM,
	     .RGB10_A2,
	     .RGB10_A2UI,
	     .RGBA12,
	     .RGBA16,
	     .SRGB8,
	     .SRGB8_ALPHA8,
	     .R16F,
	     .RG16F,
	     .RGB16F,
	     .RGBA16F,
	     .R32F,
	     .RG32F,
	     .RGB32F,
	     .RGBA32F,
	     .R11F_G11F_B10F,
	     .RGB9_E5,
	     .Depth32f,
	     .Depth24,
	     .Depth16,
	     .Depth32f_Stencil8,
	     .Depth24_Stencil8:
		return true
	case:
		return false
	}
}

@(require_results)
is_valid_compute_shader_input_format :: proc(format: Texture_Format) -> bool {
	#partial switch format {
	case .RGBA32F,
	     .RGBA16F,
	     .RG32F,
	     .RG16F,
	     .R11F_G11F_B10F,
	     .R32F,
	     .R16F,
	     .RGBA32UI,
	     .RGBA16UI,
	     .RGB10_A2UI,
	     .RGBA8UI,
	     .RG32UI,
	     .RG16UI,
	     .RG8UI,
	     .R32UI,
	     .R16UI,
	     .R8UI,
	     .RGBA32I,
	     .RGBA16I,
	     .RGBA8I,
	     .RG32I,
	     .RG16I,
	     .RG8I,
	     .R32I,
	     .R16I,
	     .R8I,
	     .RGBA16,
	     .RGB10_A2,
	     .RGBA8,
	     .RG16,
	     .RG8,
	     .R16,
	     .R8,
	     .RGBA16_SNORM,
	     .RGBA8_SNORM,
	     .RG16_SNORM,
	     .RG8_SNORM,
	     .R16_SNORM,
	     .R8_SNORM:
		return true
	case:
		return false
	}
}

@(private)
max_texture_size: int
@(private)
max_cube_map_size: int
@(private)
max_texture_array_layers: int
@(private)
max_texture_max_anisotropy: int
@(private)
max_texture_units: int

// indicates to `create_texture` (and similar procedures), that the maximum number of mipmaps for the specified dimensions should be allocated
MAX_MIPMAPS :: max(int)

@(require_results)
max_texture_mipmaps :: proc(dimensions: ..int) -> (n: int) {
	m: int
	for d in dimensions {
		m = max(m, d)
	}
	return 1 + int(math.floor(math.log2(f64(m))))
}
