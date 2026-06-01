package glodin

import "core:fmt"
import "core:strings"
import "core:os"
import vmem "core:mem/virtual"

import gl "vendor:OpenGL"

import hep "hephaistos"

@(private, require_results)
hephaistos_compile_shader :: proc(
	source:        string,
	defines:       map[string]hep.Const_Value = {},
	shared_types:  []typeid                   = {},
	allocator       := context.allocator,
	error_allocator := context.allocator,
) -> (
	code:            []u32,
	reflection_info: map[string]hep.Reflection_Info,
	entry_points:    map[string]hep.Entry_Point_Info,
	errors:          []hep.Error,
) {
	tokens: []hep.Token
	tokens, errors = hep.tokenize(source, false, -1, context.temp_allocator, error_allocator)
	if len(errors) != 0 {
		return
	}

	stmts: []^hep.Ast_Stmt
	stmts, errors = hep.parse(tokens, context.temp_allocator, error_allocator)
	if len(errors) != 0 {
		return
	}

	checker: hep.Checker
	checker, errors = hep.check(
		stmts,
		defines,
		shared_types,
		flags           = { .Auto_Map_Locations, .Auto_Bind_Uniforms, .Enable_Reflection, },
		allocator       = context.temp_allocator,
		error_allocator = error_allocator,
	)
	if len(errors) != 0 {
		return
	}

	reflection_info = checker.reflection.interface
	entry_points    = checker.reflection.entry_points

	code = hep.cg_file(&checker, stmts, nil, source, hep.SPIR_V_VERSION_1_0, allocator = allocator)

	return
}

@(require_results)
create_compute_hephaistos :: proc(
	source:       string,
	path:         string                     = "",
	defines:      map[string]hep.Const_Value = {},
	shared_types: []typeid                   = {},
	entry_point := "",
	location    := #caller_location,
) -> (compute: Compute, ok: bool) {
	spirv, reflection_info, entry_points, errors := hephaistos_compile_shader(
		source,
		defines,
		shared_types,
		allocator       = context.temp_allocator,
		error_allocator = context.temp_allocator,
	)
	if len(errors) != 0 {
		lines := strings.split_lines(source, context.temp_allocator)
		for error in errors {
			hep.print_error(os.to_stream(os.stderr), path, lines, error)
		}
		return
	}

	id := Compute(ga_append(computes, _Compute{}, location))
	c  := ga_get(computes, id)

	err := vmem.arena_init_growing(&c.arena)
	assert(err == nil)

	c.textures.allocator = vmem.arena_allocator(&c.arena)

	shader := gl.CreateShader(gl.COMPUTE_SHADER)
	defer gl.DeleteShader(shader)

	gl.ShaderBinary(1, &shader, gl.SHADER_BINARY_FORMAT_SPIR_V, raw_data(spirv), i32(len(spirv)) * size_of(u32))

	c.handle = gl.CreateProgram()

	entry_point := strings.clone_to_cstring(entry_point, context.temp_allocator)

	for name, info in entry_points {
		if entry_point == "" && info.stage == .Compute {
			entry_point = strings.clone_to_cstring(name, context.temp_allocator)
			debugf("implicitly using compute entry point: '%s'", entry_point, location = location)
		}
	}

	gl.SpecializeShader(shader, entry_point, 0, nil, nil)
	gl.AttachShader(c.handle, shader)
	gl.LinkProgram(c.handle)

	status: i32
	gl.GetProgramiv(c.handle, gl.LINK_STATUS, &status)

	gl.GetProgramiv(c.handle, gl.LINK_STATUS, &status)
	if status == 0 {
		max_length: i32
		gl.GetProgramiv(c.handle, gl.INFO_LOG_LENGTH, &max_length)
		error_log := make([]u8, max_length)
		gl.GetProgramInfoLog(c.handle, max_length, &max_length, &error_log[0]);
		fmt.println(cstring(&error_log[0]))
		return
	}

	hephaistos_collect_uniforms(c, reflection_info)

	return id, true
}

hephaistos_collect_uniforms :: proc(
	p:               ^Base_Program,
	reflection_info: map[string]hep.Reflection_Info,
) {
	allocator       := vmem.arena_allocator(&p.arena)
	p.uniforms       = make(Uniforms, len(reflection_info), allocator)
	p.uniform_blocks = make([]Uniform_Buffer_Block, len(reflection_info), allocator)

	n_uniform_blocks := 0

	for name, info in reflection_info {
		#partial switch info.interface {
		case .None:
		case .Uniform:
			hephaistos_type_to_gl :: proc(type: ^hep.Type) -> (gl_type: gl.Uniform_Type) {
				type := hep.base_type(type)

				#partial switch type.kind {
				case .Invalid, .Tuple, .Proc,  .Enum, .Bit_Set:
					panic("???")
				case .Uint:
					gl_type = .UNSIGNED_INT
				case .Int:
					gl_type = .INT
				case .Bool:
					gl_type = .BOOL
				case .Float:
					if type.size == 4 {
						gl_type = .FLOAT
					} else if type.size == 8 {
						gl_type = .DOUBLE
					}

				case .Struct:
					panic("Can not have struct uniforms, prefer using uniform buffers")
				case .Matrix:
					m    := type.variant.(^hep.Type_Matrix)
					elem := m.col_type.elem

					assert(hep.type_matrix_is_square(m))

					#partial switch elem.kind {
					case .Float:
						if elem.size == 4 {
							gl_type = .FLOAT_MAT2
						} else if elem.size == 8 {
							gl_type = .DOUBLE_MAT2
						}
					}

					switch m.cols {
					case 2:
					case 3:
						gl_type += gl.Uniform_Type.FLOAT_MAT3 - gl.Uniform_Type.FLOAT_MAT2
					case 4:
						gl_type += gl.Uniform_Type.FLOAT_MAT4 - gl.Uniform_Type.FLOAT_MAT2
					}

					// TODO: non-square matrices
				case .Array:
					elem := hep.type_array_elem(type)
					#partial switch elem.kind {
					case .Int:
						gl_type = .INT_VEC2
					case .Uint:
						gl_type = .UNSIGNED_INT_VEC2
					case .Bool:
						gl_type = .BOOL_VEC2
					case .Float:
						if elem.size == 4 {
							gl_type = .FLOAT_VEC2
						} else if elem.size == 8 {
							gl_type = .DOUBLE_VEC2
						}
					}

					gl_type += auto_cast (hep.type_array_len(type) - 2)
				case .Buffer:
					panic("Can not have buffer uniforms, prefer using shader storage buffers")
				case .Sampler:
					sampler := type.variant.(^hep.Type_Image)
					switch sampler.dimensions {
					case 1:
						gl_type = .SAMPLER_1D
					case 2:
						gl_type = .SAMPLER_2D
					case 3:
						gl_type = .SAMPLER_3D
					}
					texel := sampler.texel_type
					if texel.kind == .Array {
						texel = hep.type_array_elem(texel)
					}
					#partial switch sampler.texel_type.kind {
					case .Int:
						gl_type += gl.Uniform_Type.INT_SAMPLER_2D          - gl.Uniform_Type.SAMPLER_2D
					case .Uint:
						gl_type += gl.Uniform_Type.UNSIGNED_INT_SAMPLER_2D - gl.Uniform_Type.SAMPLER_2D
					}
				case .Image:
					image := type.variant.(^hep.Type_Image)
					switch image.dimensions {
					case 1:
						gl_type = .IMAGE_1D
					case 2:
						gl_type = .IMAGE_2D
					case 3:
						gl_type = .IMAGE_3D
					}
					texel := image.texel_type
					if texel.kind == .Array {
						texel = hep.type_array_elem(texel)
					}
					#partial switch image.texel_type.kind {
					case .Int:
						gl_type += gl.Uniform_Type.INT_IMAGE_2D          - gl.Uniform_Type.IMAGE_2D
					case .Uint:
						gl_type += gl.Uniform_Type.UNSIGNED_INT_IMAGE_2D - gl.Uniform_Type.IMAGE_2D
					}
				}

				return
			}
			gl_type := hephaistos_type_to_gl(info.type)
			assert(gl_type != nil, "Something went wrong with determining uniform types, the implementation sucks. Using uniform buffers / shader storage buffers is much more reliable")
			p.uniforms[name] = {
				info = {
					location = i32(info.location),
					size     = i32(info.type.size),
					name     = name,
					kind     = gl_type,
				},
			}
		case .Uniform_Buffer, .Storage_Buffer:
			p.uniform_blocks[n_uniform_blocks] = {
				name    = name,
				binding = int(info.binding),
				size    = info.type.size,
				is_ssbo = info.interface == .Storage_Buffer,
			}
			n_uniform_blocks += 1
		case:
			errorf("%s are not supported in OpenGL", info.interface)
		}
	}

	p.uniform_blocks = p.uniform_blocks[:n_uniform_blocks]
}

@(require_results)
create_program_hephaistos :: proc(
	source:       string,
	defines:      map[string]hep.Const_Value = {},
	shared_types: []typeid                   = {},
	vertex_entry_point   := "",
	fragment_entry_point := "",
	location             := #caller_location,
) -> (program: Program, ok: bool) {
	id := Program(ga_append(programs, _Program{}, location))
	p  := ga_get(programs, id)

	err := vmem.arena_init_growing(&p.arena)
	assert(err == nil)
	p.textures.allocator             = vmem.arena_allocator(&p.arena)
	p.valid_vertex_types.allocator   = vmem.arena_allocator(&p.arena)
	p.valid_instance_types.allocator = vmem.arena_allocator(&p.arena)

	p.handle = gl.CreateProgram()
	defer if !ok {
		vmem.arena_destroy(&p.arena)
		gl.DeleteProgram(p.handle)
	}

	spirv, reflection_info, entry_points, errors := hephaistos_compile_shader(
		source,
		defines,
		shared_types,
		allocator       = context.temp_allocator,
		error_allocator = context.temp_allocator,
	)

	if len(errors) != 0 {
		lines := strings.split_lines(source, context.temp_allocator)
		for error in errors {
			hep.print_error(os.to_stream(os.stderr), "", lines, error)
		}
		return
	}

	shaders: [2]u32 = {
		gl.CreateShader(gl.VERTEX_SHADER),
		gl.CreateShader(gl.FRAGMENT_SHADER),
	}

	gl.ShaderBinary(len(shaders), &shaders[0], gl.SHADER_BINARY_FORMAT_SPIR_V, raw_data(spirv), i32(len(spirv)) * size_of(u32))

	defer for shader in shaders {
		gl.DeleteShader(shader)
	}

	vertex_entry_point_name   := strings.clone_to_cstring(vertex_entry_point,   context.temp_allocator)
	fragment_entry_point_name := strings.clone_to_cstring(fragment_entry_point, context.temp_allocator)

	for name, info in entry_points {
		if vertex_entry_point_name   == "" && info.stage == .Vertex   {
			vertex_entry_point_name   = strings.clone_to_cstring(name, context.temp_allocator)
			debugf("implicitly using vertex entry point: '%s'", vertex_entry_point_name, location = location)
		}
		if fragment_entry_point_name == "" && info.stage == .Fragment {
			fragment_entry_point_name = strings.clone_to_cstring(name, context.temp_allocator)
			debugf("implicitly using fragment entry point: '%s'", fragment_entry_point_name, location = location)
		}
	}

	if vertex_entry_point_name == "" {
		error("shader is missing a vertex entry point", location = location)
		return
	}

	if fragment_entry_point_name == "" {
		error("shader is missing a fragment entry point", location = location)
		return
	}

	vertex_shader   := shaders[0]
	fragment_shader := shaders[1]

	gl.SpecializeShader(vertex_shader, vertex_entry_point_name, 0, nil, nil)
	gl.AttachShader(p.handle, vertex_shader)

	gl.SpecializeShader(fragment_shader, fragment_entry_point_name, 0, nil, nil)
	gl.AttachShader(p.handle, fragment_shader)

	gl.LinkProgram(p.handle)

	status: i32
	gl.GetProgramiv(p.handle, gl.LINK_STATUS, &status)
	if status == 0 {
		max_length: i32
		gl.GetProgramiv(p.handle, gl.INFO_LOG_LENGTH, &max_length)
		error_log := make([]u8, max_length)
		gl.GetProgramInfoLog(p.handle, max_length, &max_length, &error_log[0]);
		fmt.println(location, cstring(&error_log[0]))
		return
	}

	hephaistos_collect_uniforms(p, reflection_info)
	get_attributes_from_program(p)

	return id, true
}
