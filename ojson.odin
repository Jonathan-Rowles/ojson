package ojson

import oj "jsonimpl"

DEFAULT_READER_ARENA_SIZE :: oj.DEFAULT_READER_ARENA_SIZE
DEFAULT_WRITE_BUFFER_SIZE :: oj.DEFAULT_WRITE_BUFFER_SIZE

Error      :: oj.Error
Reader     :: oj.Reader
Writer     :: oj.Writer
Value_Type :: oj.Value_Type
Element    :: oj.Element

init_reader :: proc(
	arena_size := DEFAULT_READER_ARENA_SIZE,
	allocator := context.allocator,
) -> Reader {
	return oj.init_reader(arena_size, allocator)
}

parse :: proc(r: ^Reader, data: []byte) -> Error {
	return oj.parse(r, data)
}

reset :: proc(r: ^Reader) {
	oj.reset(r)
}

read_string :: proc(r: ^Reader, key: string) -> (value: string, err: Error) {
	return oj.read_string(r, key)
}

read_int :: proc(r: ^Reader, key: string) -> (value: int, err: Error) {
	return oj.read_int(r, key)
}

read_i64 :: proc(r: ^Reader, key: string) -> (value: i64, err: Error) {
	return oj.read_i64(r, key)
}

read_f64 :: proc(r: ^Reader, key: string) -> (value: f64, err: Error) {
	return oj.read_f64(r, key)
}

read_bool :: proc(r: ^Reader, key: string) -> (value: bool, err: Error) {
	return oj.read_bool(r, key)
}

exists :: proc(r: ^Reader, key: string) -> bool {
	return oj.exists(r, key)
}

is_null :: proc(r: ^Reader, key: string) -> bool {
	return oj.is_null(r, key)
}

array_len :: proc(r: ^Reader, key: string) -> (int, Error) {
	return oj.array_len(r, key)
}

root_element :: proc(r: ^Reader) -> Element {
	return oj.root_element(r)
}

element_at :: proc(r: ^Reader, path: string) -> (Element, Error) {
	return oj.element_at(r, path)
}

array_elements :: proc(r: ^Reader, path: string) -> ([]Element, Error) {
	return oj.array_elements(r, path)
}

array_element :: proc(r: ^Reader, path: string, index: int) -> (Element, Error) {
	return oj.array_element(r, path, index)
}

obj_element :: proc(r: ^Reader, path: string, key: string) -> (Element, Error) {
	return oj.obj_element(r, path, key)
}

obj_element_from :: proc(r: ^Reader, elem: Element, key: string) -> (Element, Error) {
	return oj.obj_element_from(r, elem, key)
}

array_element_from :: proc(r: ^Reader, elem: Element, index: int) -> (Element, Error) {
	return oj.array_element_from(r, elem, index)
}

array_elements_from :: proc(r: ^Reader, elem: Element) -> ([]Element, Error) {
	return oj.array_elements_from(r, elem)
}

read_string_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: string, err: Error) {
	return oj.read_string_elem(r, elem, field)
}

read_int_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: int, err: Error) {
	return oj.read_int_elem(r, elem, field)
}

read_i64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: i64, err: Error) {
	return oj.read_i64_elem(r, elem, field)
}

read_f64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: f64, err: Error) {
	return oj.read_f64_elem(r, elem, field)
}

read_bool_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: bool, err: Error) {
	return oj.read_bool_elem(r, elem, field)
}

init_writer :: proc(
	buffer_size := DEFAULT_WRITE_BUFFER_SIZE,
	allocator := context.allocator,
) -> Writer {
	return oj.init_writer(buffer_size, allocator)
}

marshal_to :: proc(w: ^Writer, value: any, pretty := false) -> (result: []byte, err: Error) {
	return oj.marshal_to(w, value, pretty)
}

pretty_print :: proc(data: []byte, allocator := context.allocator) -> (string, Error) {
	return oj.pretty_print(data, allocator)
}

destroy_reader :: proc(r: ^Reader) {
	oj.destroy_reader(r)
}

destroy_writer :: proc(w: ^Writer) {
	oj.destroy_writer(w)
}

destroy :: proc {
	destroy_reader,
	destroy_writer,
}

// One-shot convenience functions
get_string :: proc(
	data: []byte,
	key: string,
	arena_size := DEFAULT_READER_ARENA_SIZE,
	allocator := context.allocator,
) -> (
	value: string,
	err: Error,
) {
	return oj.get_string(data, key, arena_size, allocator)
}

// One-shot convenience functions
get_int :: proc(
	data: []byte,
	key: string,
	arena_size := DEFAULT_READER_ARENA_SIZE,
	allocator := context.allocator,
) -> (
	value: int,
	err: Error,
) {
	return oj.get_int(data, key, arena_size, allocator)
}

// One-shot convenience functions
get_i64 :: proc(
	data: []byte,
	key: string,
	arena_size := DEFAULT_READER_ARENA_SIZE,
	allocator := context.allocator,
) -> (
	value: i64,
	err: Error,
) {
	return oj.get_i64(data, key, arena_size, allocator)
}

// One-shot convenience functions
get_f64 :: proc(
	data: []byte,
	key: string,
	arena_size := DEFAULT_READER_ARENA_SIZE,
	allocator := context.allocator,
) -> (
	value: f64,
	err: Error,
) {
	return oj.get_f64(data, key, arena_size, allocator)
}

// One-shot convenience functions
get_bool :: proc(
	data: []byte,
	key: string,
	arena_size := DEFAULT_READER_ARENA_SIZE,
	allocator := context.allocator,
) -> (
	value: bool,
	err: Error,
) {
	return oj.get_bool(data, key, arena_size, allocator)
}
