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

DEFAULT_READER_SIZE :: 1024 * 1024
DEFAULT_WRITE_BUFFER_SIZE :: 1024
MAX_DEPTH :: 300

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
		str:       string,
		container: u32,
	},
}

KV :: struct {
	owner_idx: u32,
	key:       string,
	value_idx: u32,
}

ArrEntry :: struct {
	owner_idx: u32,
	value_idx: u32,
}

Parser_State :: struct {
	input:      string,
	pos:        int,
	values:     []Lazy_Value,
	values_len: u32,
	kv_buffer:  []KV,
	kv_len:     u32,
	arr_buffer: []ArrEntry,
	arr_len:    u32,
	root:       u32,
	depth:      int,
}

Reader :: struct {
	parser:            Parser_State,
	arena:             mem.Arena,
	memory:            []byte,
	backing_allocator: mem.Allocator,
	max_cap:           u32,
	buffer_offset:     int,
}

Writer :: struct {
	buffer:    bytes.Buffer,
	allocator: mem.Allocator,
}

destroy :: proc {
	destroy_reader,
	destroy_writer,
}
