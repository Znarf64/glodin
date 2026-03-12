#+private
package glodin

import "base:runtime"

Index :: u32

_Index :: bit_field u32 {
	index:      u16 | 16,
	generation: u16 | 15,
}

@(private = "file")
Generational_Array_Elem :: struct($T: typeid) {
	value: T,
	id:    bit_field u16 {
		generation: u16  | 15,
		alive:      bool | 1,
	},
	location: (runtime.Source_Code_Location when GLODIN_TRACK_LEAKS else struct{}),
}

Generational_Array :: struct($T: typeid) {
	data: #soa[max(u16)]Generational_Array_Elem(T) `fmt:"-"`,
	len:  int,
	free: [dynamic]u16,
}

ga_append :: proc(ga: ^Generational_Array($T), val: T, location: runtime.Source_Code_Location) -> (index: Index) {
	assert(ga != nil)

	_index: _Index
	if idx, ok := pop_safe(&ga.free); ok {
		ga.data[idx].value = val
		ga.data[idx].id.alive = true
		_index.index = u16(idx)
		ga.data[idx].id.generation += 1
		if ga.data[idx].id.generation == 0 {
			ga.data[idx].id.generation = 1
		}
		_index.generation = ga.data[idx].id.generation
		return Index(_index)
	}

	_index.index = u16(ga.len)
	_index.generation = 1
	ga.data[ga.len] = {
		value = val,
		id    = {generation = 1, alive = true},
	}
	when GLODIN_TRACK_LEAKS {
		ga.data[ga.len].location = location
	}
	ga.len += 1
	return Index(_index)
}

ga_remove :: proc(ga: ^Generational_Array($T), index: $I/Index) {
	assert(ga != nil)

	index := _Index(index)
	assert(int(index.index) < len(ga.data))
	id := &ga.data[index.index].id
	assert(id.generation == index.generation && index.generation != 0 && id.alive)
	id.alive = false
	append(&ga.free, u16(index.index))
}

ga_get :: proc(ga: ^Generational_Array($T), index: $I/Index) -> ^T {
	assert(ga != nil)

	index := _Index(index)
	if len(ga.data) > int(index.index) {
		id := ga.data[index.index].id
		if id.generation == index.generation && id.alive && id.generation != 0 {
			return &ga.data[index.index].value
		} else {
			return nil
		}
	} else {
		error(len(ga.data), int(index.index))
		return nil
	}
}

ga_iter :: proc(ga: ^Generational_Array($T), iter: ^int) -> (elem: T, index: Index, cond: bool) {
	assert(ga != nil)
	assert(iter != nil)

	for iter^ < ga.len {
		defer iter^ += 1
		if ga.data[iter^].id.alive {
			elem = ga.data[iter^].value
			index = Index(_Index{index = u16(iter^), generation = ga.data[iter^].id.generation})
			cond = true
			break
		}
	}
	return
}

