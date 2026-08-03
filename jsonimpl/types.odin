package jsonimpl

import "core:bytes"
import "core:mem"

Error :: enum {
	OK,
	Not_Parsed,
	Key_Not_Found,
	Type_Mismatch,
	Invalid_JSON,
}

DEFAULT_READER_SIZE :: 0
DEFAULT_WRITE_BUFFER_SIZE :: 1024
MAX_DEPTH :: 300

Element :: distinct u32

ELEMENT_INDEX_BITS :: 24
ELEMENT_INDEX_MASK :: u32(1 << ELEMENT_INDEX_BITS) - 1

Value_Type :: enum u8 {
	Null,
	True,
	False,
	Number,
	Raw_String,
	String,
	Array,
	Object,
}

Container :: struct {
	count:         u32,
	entries_begin: u32,
	entries_end:   u32,
}

Lazy_Value :: struct {
	type:      Value_Type,
	input_pos: u32,
	data:      struct #raw_union {
		str:       string,
		container: Container,
	},
}

ArrEntry :: struct {
	owner_idx: u32,
	value_idx: u32,
}

Parser_State :: struct {
	input:         string,
	pos:           int,
	values:        []Lazy_Value,
	values_len:    u32,
	kv_keys:       []u64,
	kv_vals:       []u32,
	kv_len:        u32,
	kv_stack_keys: []u64,
	kv_stack_vals: []u32,
	kv_stack_len:  u32,
	arr_buffer:    []ArrEntry,
	arr_len:       u32,
	root:          u32,
	depth:         int,
	key_hints:     [8]u32,
	allocator:     mem.Allocator,
	block_start:   uintptr,
	block_end:     uintptr,
}

Scratch_Chunk :: struct {
	next: ^Scratch_Chunk,
	size: int,
}

Scratch :: struct {
	base:            []byte,
	offset:          int,
	overflow:        []byte,
	overflow_offset: int,
	chunks:          ^Scratch_Chunk,
}

Reader :: struct {
	parser:            Parser_State,
	scratch:           Scratch,
	block:             []byte,
	block_cap:         u32,
	backing_allocator: mem.Allocator,
	generation:        u32,
}

Array_Iterator :: struct {
	r:       ^Reader,
	arr_idx: u32,
	pos:     u32,
	end:     u32,
}

Object_Iterator :: struct {
	r:   ^Reader,
	pos: u32,
	end: u32,
}

Writer :: struct {
	buffer:    bytes.Buffer,
	allocator: mem.Allocator,
	depth:     int,
	needs_sep: [64]bool,
}

destroy :: proc {
	destroy_reader,
	destroy_writer,
}
