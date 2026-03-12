package glodin

import "core:fmt"
import "core:os"
import "core:reflect"
import "core:strings"
import "core:mem"

import gl "vendor:OpenGL"

Program :: distinct Index

@(private)
programs: ^Generational_Array(_Program)

@(private)
get_program :: proc(program: Program) -> ^_Program {
	return ga_get(programs, program)
}

@(private)
get_program_handle :: proc(program: Program) -> u32 {
	return ga_get(programs, program).handle
}

_get_program_handle :: proc(program: Program) -> u32 {
	return get_program_handle(program)
}

get_program_info :: proc(program: Program) -> _Program {
	return get_program(program)^
}

@(private)
Attribute :: struct {
	name:     string,
	size:     i32,
	location: i32,
	type:     Attribute_Type,
}

@(private)
_Program :: struct {
	using base:           Base_Program,
	valid_vertex_types:   [dynamic]typeid,
	valid_instance_types: [dynamic]typeid,
	attributes:           []Attribute,
}

@(private)
Texture_Binding :: struct {
	location: i32,
	texture:  Texture,
}

@(private)
Uniform_Buffer_Block :: struct {
	name:    string,
	binding: int,
	using _: bit_field int {
		size:    int  | 63,
		is_ssbo: bool | 1,
	},
}

// shared between compute shaders and "normal" programs
@(private)
Base_Program :: struct {
	handle:         u32,
	uniforms:       Uniforms,
	uniform_blocks: []Uniform_Buffer_Block,
	textures:       #soa[dynamic]Texture_Binding,
	arena:          mem.Dynamic_Arena,
}

@(private)
check_program_vertex_type :: proc(
	program:       ^_Program,
	vertex_type:   typeid,
	instance_type: typeid,
	location:      Source_Code_Location,
) {
	for valid in program.valid_vertex_types {
		if valid == vertex_type {
			return
		}
	}
	for valid in program.valid_instance_types {
		if valid == instance_type {
			return
		}
	}

	type_to_attribute_type :: proc(ti: ^reflect.Type_Info) -> (type: Attribute_Type) {
		ti := reflect.type_info_base(ti)
		#partial switch v in ti.variant {
		case reflect.Type_Info_Float:
			switch ti.size {
			case 2:
				panic("Half precision floats are not supported as vertex attributes")
			case 4:
				return .Float
			case 8:
				return .Double
			case:
				unreachable()
			}
		case reflect.Type_Info_Integer:
			assert(ti.size == 4, "Integer vertex attributes have to be 4 bytes")
			return v.signed ? .Int : .Unsigned_Int
		case reflect.Type_Info_Array:
			switch v.count {
			case 2 ..= 4:
				elem := type_to_attribute_type(v.elem)
				#partial switch elem {
				case .Float:
					return Attribute_Type(v.count - 2) + .Float_Vec2
				case .Double:
					return Attribute_Type(v.count - 2) + .Double_Vec2
				case .Int:
					return Attribute_Type(v.count - 2) + .Int_Vec2
				case .Unsigned_Int:
					return Attribute_Type(v.count - 2) + .Unsigned_Int_Vec2
				case:
					unreachable()
				}
			case:
				panic("Invalid array length for vertex attribute:", v.count)
			}
		case reflect.Type_Info_Matrix:
			elem := type_to_attribute_type(v.elem)

			if v.column_count == v.row_count {
				#partial switch elem {
				case .Float:
					return Attribute_Type(v.column_count - 2) + .Float_Mat2
				case .Double:
					return Attribute_Type(v.column_count - 2) + .Double_Mat2
				case:
					unreachable()
				}
			}

			get_matrix_offset :: proc(rows, cols: int) -> u32 {
				tuple := [2]int{rows, cols}
				switch tuple {
				case {2, 3}:
					return 0
				case {2, 4}:
					return 1
				case {3, 2}:
					return 2
				case {3, 4}:
					return 3
				case {4, 2}:
					return 4
				case {4, 3}:
					return 5
				case:
					unreachable()
				}
			}

			#partial switch elem {
			case .Float:
				return Attribute_Type(get_matrix_offset(v.row_count, v.column_count)) + .Float_Mat2
			case .Double:
				return(
					Attribute_Type(get_matrix_offset(v.row_count, v.column_count)) +
					.Double_Mat2 \
				)
			case:
				unreachable()
			}
		case:
			panic("Invalid vertex attribute type:", ti.id)
		}
	}

	for field, i in reflect.struct_fields_zipped(vertex_type) {
		at_type := type_to_attribute_type(reflect.type_info_base(field.type))

		if i >= len(program.attributes) {
			warnf(
				"Unused vertex attribute at index: %v, type: %v, field name: `%v`",
				i,
				field.type,
				field.name,
				location = location,
			)
			continue
		}

		attrib := program.attributes[i]

		if attrib.type == nil {
			warnf(
				"Unused vertex attribute at index: %v, type: %v, field name: `%v`",
				i,
				field.type,
				field.name,
				location = location,
			)
			continue
		}

		if attrib.type != at_type {
			errorf(
				"Program attribute `%v`(`%v`) at index %v expects type %v and size %v, but vertex buffer contains data of type %v(%v)",
				attrib.name,
				field.name,
				i,
				attrib.type,
				attrib.size,
				at_type,
				field.type,
				location = location,
			)
		}
	}

	append(&program.valid_vertex_types, vertex_type)
}

create_program_file :: proc(
	vertex_path, fragment_path: string,
	geometry_path: Maybe(string) = nil,
	location := #caller_location,
) -> (program: Program, ok: bool) {
	fragment_source, vertex_source: []byte
	err: os.Error
	fragment_source, err = os.read_entire_file(fragment_path, context.temp_allocator)
	if err != nil do return
	vertex_source, err   = os.read_entire_file(vertex_path,   context.temp_allocator)
	if err != nil do return

	geometry_source: Maybe([]byte) = nil
	if path, ok := geometry_path.?; ok {
		geometry_source, err = os.read_entire_file(path, context.temp_allocator)
		if err != nil do return
	}

	return create_program_source(
		string(vertex_source),
		string(fragment_source),
		transmute(Maybe(string))geometry_source,
		location = location,
	)
}

@(private = "file")
Shader_Type :: enum {
	Vertex,
	Fragment,
	Geometry,
	Compute,
}

@(private = "file")
compile_shader :: proc(
	source: string,
	type:   Shader_Type,
) -> (
	handle: u32,
	ok: bool,
) {
	gl_type: u32
	switch type {
	case .Vertex:
		gl_type = gl.VERTEX_SHADER
	case .Fragment:
		gl_type = gl.FRAGMENT_SHADER
	case .Geometry:
		gl_type = gl.GEOMETRY_SHADER
	case .Compute:
		gl_type = gl.COMPUTE_SHADER
	}
	handle = gl.CreateShader(gl_type)
	if handle == 0 {
		return
	}
	defer if !ok {
		gl.DeleteShader(handle)
	}
	length := i32(len(source))
	data   := cstring(raw_data(source))
	gl.ShaderSource(handle, 1, &data, &length)
	gl.CompileShader(handle)
	status: i32
	gl.GetShaderiv(handle, gl.COMPILE_STATUS, &status)
	if status == 0 {
		max_length: i32
		gl.GetShaderiv(handle, gl.INFO_LOG_LENGTH, &max_length)
		error_log := make([]u8, max_length)
		gl.GetShaderInfoLog(handle, max_length, &max_length, &error_log[0]);
		fmt.printfln("Failed to compile %v shader:\n%v", type, cstring(&error_log[0]))
		return
	}
	ok = true
	return
}

create_program_source :: proc(
	vertex_source, fragment_source: string,
	geometry_source: Maybe(string) = nil,
	location := #caller_location,
) -> (program: Program, ok: bool) {
	id := Program(ga_append(programs, _Program{}, location))
	p  := ga_get(programs, id)

	mem.dynamic_arena_init(&p.arena, alignment = 64)
	p.textures.allocator             = mem.dynamic_arena_allocator(&p.arena)
	p.valid_vertex_types.allocator   = mem.dynamic_arena_allocator(&p.arena)
	p.valid_instance_types.allocator = mem.dynamic_arena_allocator(&p.arena)

	p.handle = gl.CreateProgram()
	defer if !ok {
		mem.dynamic_arena_destroy(&p.arena)
		gl.DeleteProgram(p.handle)
	}
	status: i32

	vertex := compile_shader(vertex_source, .Vertex) or_return
	defer gl.DeleteShader(vertex)
	gl.AttachShader(p.handle, vertex)

	fragment := compile_shader(fragment_source, .Fragment) or_return
	defer gl.DeleteShader(vertex)
	gl.AttachShader(p.handle, fragment)

	has_geometry := false
	geometry: u32
	if geometry_source, ok := geometry_source.?; ok {
		geometry = compile_shader(geometry_source, .Geometry) or_return
		gl.AttachShader(p.handle, geometry)
		has_geometry = true
	}
	defer if has_geometry do gl.DeleteShader(geometry)

	gl.LinkProgram(p.handle)

	gl.GetProgramiv(p.handle, gl.LINK_STATUS, &status)
	if status == 0 {
		max_length: i32
		gl.GetProgramiv(p.handle, gl.INFO_LOG_LENGTH, &max_length)
		error_log := make([]u8, max_length)
		gl.GetProgramInfoLog(p.handle, max_length, &max_length, &error_log[0]);
		fmt.println(location, cstring(&error_log[0]))
		return
	}

	get_uniforms_from_program(p)
	get_uniform_blocks_from_program(p, location)
	get_attributes_from_program(p)

	return id, true
}

@(private)
Attribute_Type :: enum {
	Float             = gl.FLOAT,
	Float_Vec2        = gl.FLOAT_VEC2,
	Float_Vec3        = gl.FLOAT_VEC3,
	Float_Vec4        = gl.FLOAT_VEC4,
	Float_Mat2        = gl.FLOAT_MAT2,
	Float_Mat3        = gl.FLOAT_MAT3,
	Float_Mat4        = gl.FLOAT_MAT4,
	Float_Mat2x3      = gl.FLOAT_MAT2x3,
	Float_Mat2x4      = gl.FLOAT_MAT2x4,
	Float_Mat3x2      = gl.FLOAT_MAT3x2,
	Float_Mat3x4      = gl.FLOAT_MAT3x4,
	Float_Mat4x2      = gl.FLOAT_MAT4x2,
	Float_Mat4x3      = gl.FLOAT_MAT4x3,
	Int               = gl.INT,
	Int_Vec2          = gl.INT_VEC2,
	Int_Vec3          = gl.INT_VEC3,
	Int_Vec4          = gl.INT_VEC4,
	Unsigned_Int      = gl.UNSIGNED_INT,
	Unsigned_Int_Vec2 = gl.UNSIGNED_INT_VEC2,
	Unsigned_Int_Vec3 = gl.UNSIGNED_INT_VEC3,
	Unsigned_Int_Vec4 = gl.UNSIGNED_INT_VEC4,
	Double            = gl.DOUBLE,
	Double_Vec2       = gl.DOUBLE_VEC2,
	Double_Vec3       = gl.DOUBLE_VEC3,
	Double_Vec4       = gl.DOUBLE_VEC4,
	Double_Mat2       = gl.DOUBLE_MAT2,
	Double_Mat3       = gl.DOUBLE_MAT3,
	Double_Mat4       = gl.DOUBLE_MAT4,
	Double_Mat2x3     = gl.DOUBLE_MAT2x3,
	Double_Mat2x4     = gl.DOUBLE_MAT2x4,
	Double_Mat3x2     = gl.DOUBLE_MAT3x2,
	Double_Mat3x4     = gl.DOUBLE_MAT3x4,
	Double_Mat4x2     = gl.DOUBLE_MAT4x2,
	Double_Mat4x3     = gl.DOUBLE_MAT4x3,
}

@(private)
get_uniform_blocks_from_program :: proc(
	program: ^Base_Program,
	location: Source_Code_Location,
) {
	n_uniform_blocks: i32
	gl.GetProgramInterfaceiv(program.handle, gl.UNIFORM_BLOCK, gl.ACTIVE_RESOURCES, &n_uniform_blocks)
	n_ssbos: i32
	gl.GetProgramInterfaceiv(program.handle, gl.SHADER_STORAGE_BLOCK, gl.ACTIVE_RESOURCES, &n_ssbos)
	blocks := make([dynamic]Uniform_Buffer_Block, 0, int(n_uniform_blocks) + int(n_ssbos), mem.dynamic_arena_allocator(&program.arena))

	get_blocks :: proc(
		program:  ^Base_Program,
		blocks:   ^[dynamic]Uniform_Buffer_Block,
		ssbo:     bool,
		location: Source_Code_Location,
	) {
		interface: u32 = ssbo ? gl.SHADER_STORAGE_BLOCK : gl.UNIFORM_BLOCK

		n: i32
		gl.GetProgramInterfaceiv(program.handle, interface, gl.ACTIVE_RESOURCES, &n)

		max_len: i32
		gl.GetProgramInterfaceiv(program.handle, interface, gl.MAX_NAME_LENGTH, &max_len)

		buf := make([]byte, max_len, context.temp_allocator)

		properties := [?]u32{gl.BUFFER_BINDING, gl.BUFFER_DATA_SIZE, gl.NUM_ACTIVE_VARIABLES}
		values: [len(properties)]i32

		current_binding: u32

		for i in 0 ..< n {
			length: i32
			gl.GetProgramResourceName(program.handle, interface, u32(i), max_len, &length, raw_data(buf))
			gl.GetProgramResourceiv(
				program.handle,
				interface,
				u32(i),
				len(properties),
				&properties[0],
				size_of(values),
				nil,
				&values[0],
			)

			// assert(
			// 	values[2] == 1,
			// 	"Please use the predefined UNIFORM_BUFFER(name, type, count) macro to define Uniform Buffers in glsl",
			// 	location,
			// )
			// assert(
			// 	length > len(UNIFORM_BUFFER_PREFIX),
			// 	"Please use the predefined UNIFORM_BUFFER(name, type, count) macro to define Uniform Buffers in glsl",
			// 	location,
			// )
			// assert(
			// 	string(buf[:len(UNIFORM_BUFFER_PREFIX)]) == UNIFORM_BUFFER_PREFIX,
			// 	"Please use the predefined UNIFORM_BUFFER(name, type, count) macro to define Uniform Buffers in glsl",
			// 	location,
			// )

			if values[0] == 0 {
				values[0] = i32(current_binding)
				if ssbo {
					gl.ShaderStorageBlockBinding(program.handle, u32(i), current_binding)
				} else {
					gl.UniformBlockBinding(program.handle, u32(i), current_binding)
				}
				current_binding += 1
			}

			block := Uniform_Buffer_Block {
				name    = strings.clone_from_ptr(
					raw_data(buf),
					int(length),
					mem.dynamic_arena_allocator(&program.arena),
				),
				binding = int(values[0]),
				size    = int(values[1]),
				is_ssbo = ssbo,
			}
			append(blocks, block)
		}
	}

	get_blocks(program, &blocks, false, location)
	get_blocks(program, &blocks, true,  location)

	program.uniform_blocks = blocks[:]
}

@(private)
get_attributes_from_program :: proc(program: ^_Program) {
	n: i32
	gl.GetProgramInterfaceiv(program.handle, gl.PROGRAM_INPUT, gl.ACTIVE_RESOURCES, &n)

	attributes := make([dynamic]Attribute, n, mem.dynamic_arena_allocator(&program.arena))

	max_len: i32
	gl.GetProgramInterfaceiv(program.handle, gl.PROGRAM_INPUT, gl.MAX_NAME_LENGTH, &max_len)

	buf := make([]byte, max_len, context.temp_allocator)

	properties := [?]u32{gl.TYPE, gl.ARRAY_SIZE, gl.LOCATION}
	values: [len(properties)]i32

	for i in 0 ..< n {
		length: i32
		gl.GetProgramResourceName(program.handle, gl.PROGRAM_INPUT, u32(i), max_len, &length, raw_data(buf))
		gl.GetProgramResourceiv(
			program.handle,
			gl.PROGRAM_INPUT,
			u32(i),
			len(properties),
			&properties[0],
			size_of(values),
			nil,
			&values[0],
		)

		if values[2] < 0 {
			continue
		}
		for int(values[2]) >= len(attributes) {
			append(&attributes, Attribute{})
		}
		attributes[values[2]] = {
			name     = strings.clone_from_ptr(raw_data(buf), int(length), mem.dynamic_arena_allocator(&program.arena)),
			size     = values[1],
			type     = Attribute_Type(values[0]),
			location = values[2],
		}
	}

	program.attributes = attributes[:]
}

destroy_program :: #force_inline proc(p: Program) {
	program := get_program(p)
	mem.dynamic_arena_destroy(&program.arena)
	gl.DeleteProgram(program.handle)
	ga_remove(programs, p)
}

@(private)
current_program := max(Program)

@(private)
set_program_active :: proc(program: Program) {
	if program != current_program {
		gl.UseProgram(get_program_handle(program))
		current_program = program
	}
}

@(private)
get_uniforms_from_program :: proc(program: ^Base_Program) {
	uniform_count: i32
	gl.GetProgramiv(program.handle, gl.ACTIVE_UNIFORMS, &uniform_count)

	allocator := mem.dynamic_arena_allocator(&program.arena)

	program.uniforms = make(Uniforms, int(uniform_count), allocator)

	for i in 0 ..< uniform_count {
		uniform_info: gl.Uniform_Info

		length: i32
		cname: [256]u8
		gl.GetActiveUniform(program.handle, u32(i), 256, &length, &uniform_info.size, cast(^u32)&uniform_info.kind, &cname[0])

		uniform_info.location = gl.GetUniformLocation(program.handle, cstring(&cname[0]))
		uniform_info.name = strings.clone(string(cname[:length]), allocator)
		program.uniforms[uniform_info.name] = {uniform_info, 0}
	}

	program.uniforms.allocator = mem.panic_allocator()
}
