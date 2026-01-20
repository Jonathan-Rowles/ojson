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

DEFAULT_READER_ARENA_SIZE :: 4096
DEFAULT_WRITE_BUFFER_SIZE :: 1024
BYTES_PER_VALUE_ESTIMATE :: 32

Element :: distinct u32

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

Lazy_Value :: struct {
	type: Value_Type,
	data: struct #raw_union {
		str: string,
		obj: [dynamic]KV,
		arr: [dynamic]u32,
	},
}

KV :: struct {
	key:       string,
	value_idx: u32,
}

MAX_DEPTH :: 300

Parser_State :: struct {
	input:     string,
	pos:       int,
	values:    [dynamic]Lazy_Value,
	root:      u32,
	depth:     int,
	allocator: mem.Allocator,
}

Reader :: struct {
	parser:            Parser_State,
	arena:             mem.Arena,
	arena_buffer:      []byte,
	backing_allocator: mem.Allocator,
	has_parsed:        bool,
}

Writer :: struct {
	buffer:    bytes.Buffer,
	allocator: mem.Allocator,
}

destroy :: proc {
	destroy_reader,
	destroy_writer,
}
