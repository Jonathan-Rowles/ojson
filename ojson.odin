package ojson

import oj "jsonimpl"

DEFAULT_READER_SIZE :: oj.DEFAULT_READER_SIZE
DEFAULT_WRITE_BUFFER_SIZE :: oj.DEFAULT_WRITE_BUFFER_SIZE

Error :: oj.Error
Reader :: oj.Reader
Writer :: oj.Writer
Value_Type :: oj.Value_Type
Element :: oj.Element
Array_Iterator :: oj.Array_Iterator
Object_Iterator :: oj.Object_Iterator

init_reader :: proc(r: ^Reader, size := DEFAULT_READER_SIZE, allocator := context.allocator) {
	oj.init_reader(r, size, allocator)
}

parse :: proc(r: ^Reader, data: []byte) -> Error {
	return oj.parse(r, data)
}

// Reading by path from the document root.

@(require_results)
read_string_path :: proc(r: ^Reader, path: string) -> (value: string, err: Error) {
	return oj.read_string(r, path)
}

@(require_results)
read_int_path :: proc(r: ^Reader, path: string) -> (value: int, err: Error) {
	return oj.read_int(r, path)
}

@(require_results)
read_i64_path :: proc(r: ^Reader, path: string) -> (value: i64, err: Error) {
	return oj.read_i64(r, path)
}

@(require_results)
read_f64_path :: proc(r: ^Reader, path: string) -> (value: f64, err: Error) {
	return oj.read_f64(r, path)
}

@(require_results)
read_bool_path :: proc(r: ^Reader, path: string) -> (value: bool, err: Error) {
	return oj.read_bool(r, path)
}

@(require_results)
read_raw_path :: proc(r: ^Reader, path: string) -> (value: string, err: Error) {
	return oj.read_raw(r, path)
}

// Reading a named field of an element.

@(require_results)
read_string_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: string, err: Error) {
	return oj.read_string_elem(r, elem, field)
}

@(require_results)
read_int_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: int, err: Error) {
	return oj.read_int_elem(r, elem, field)
}

@(require_results)
read_i64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: i64, err: Error) {
	return oj.read_i64_elem(r, elem, field)
}

@(require_results)
read_f64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: f64, err: Error) {
	return oj.read_f64_elem(r, elem, field)
}

@(require_results)
read_bool_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: bool, err: Error) {
	return oj.read_bool_elem(r, elem, field)
}

@(require_results)
read_raw_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: string, err: Error) {
	return oj.read_raw_elem(r, elem, field)
}

// Reading the value an element itself holds.

@(require_results)
read_string_value :: proc(r: ^Reader, elem: Element) -> (value: string, err: Error) {
	return oj.read_string_value(r, elem)
}

@(require_results)
read_int_value :: proc(r: ^Reader, elem: Element) -> (value: int, err: Error) {
	return oj.read_int_value(r, elem)
}

@(require_results)
read_i64_value :: proc(r: ^Reader, elem: Element) -> (value: i64, err: Error) {
	return oj.read_i64_value(r, elem)
}

@(require_results)
read_f64_value :: proc(r: ^Reader, elem: Element) -> (value: f64, err: Error) {
	return oj.read_f64_value(r, elem)
}

@(require_results)
read_bool_value :: proc(r: ^Reader, elem: Element) -> (value: bool, err: Error) {
	return oj.read_bool_value(r, elem)
}

// One name per type, resolved by argument shape:
//   read_f64(r, "a.b")          value at a path
//   read_f64(r, elem, "field")  named field of an element
//   read_f64(r, elem)           the element's own value
read_string :: proc {
	read_string_path,
	read_string_elem,
	read_string_value,
}

read_int :: proc {
	read_int_path,
	read_int_elem,
	read_int_value,
}

read_i64 :: proc {
	read_i64_path,
	read_i64_elem,
	read_i64_value,
}

read_f64 :: proc {
	read_f64_path,
	read_f64_elem,
	read_f64_value,
}

read_bool :: proc {
	read_bool_path,
	read_bool_elem,
	read_bool_value,
}

read_raw :: proc {
	read_raw_path,
	read_raw_elem,
}

@(require_results)
exists :: proc(r: ^Reader, path: string) -> bool {
	return oj.exists(r, path)
}

@(require_results)
is_null :: proc(r: ^Reader, path: string) -> bool {
	return oj.is_null(r, path)
}

@(require_results)
array_len :: proc(r: ^Reader, path: string) -> (int, Error) {
	return oj.array_len(r, path)
}

// Navigating to elements.

@(require_results)
root_element :: proc(r: ^Reader) -> Element {
	return oj.root_element(r)
}

@(require_results)
element_at :: proc(r: ^Reader, path: string) -> (Element, Error) {
	return oj.element_at(r, path)
}

@(require_results)
element_value_type :: proc(r: ^Reader, elem: Element) -> Value_Type {
	return oj.element_value_type(r, elem)
}

@(require_results)
array_element :: proc(r: ^Reader, path: string, index: int) -> (Element, Error) {
	return oj.array_element(r, path, index)
}

@(require_results)
array_element_from :: proc(r: ^Reader, elem: Element, index: int) -> (Element, Error) {
	return oj.array_element_from(r, elem, index)
}

@(require_results)
obj_element :: proc(r: ^Reader, path: string, key: string) -> (Element, Error) {
	return oj.obj_element(r, path, key)
}

@(require_results)
obj_element_from :: proc(r: ^Reader, elem: Element, key: string) -> (Element, Error) {
	return oj.obj_element_from(r, elem, key)
}

// Allocating collectors. These build a slice in the reader arena; prefer the
// iterators below when you are only walking the container once.

@(require_results)
array_elements :: proc(r: ^Reader, path: string) -> ([]Element, Error) {
	return oj.array_elements(r, path)
}

@(require_results)
array_elements_from :: proc(r: ^Reader, elem: Element) -> ([]Element, Error) {
	return oj.array_elements_from(r, elem)
}

@(require_results)
object_keys :: proc(r: ^Reader, elem: Element) -> []string {
	return oj.object_keys(r, elem)
}

// Non-allocating iteration.
//
//	it := ojson.array_iter(&r, elem)
//	for item in ojson.next(&it) { ... }
//
//	oit := ojson.object_iter(&r, elem)
//	for key, value in ojson.next(&oit) { ... }

@(require_results)
array_iter :: proc(r: ^Reader, elem: Element) -> Array_Iterator {
	return oj.array_iter(r, elem)
}

@(require_results)
array_iter_at :: proc(r: ^Reader, path: string) -> (Array_Iterator, Error) {
	return oj.array_iter_at(r, path)
}

@(require_results)
object_iter :: proc(r: ^Reader, elem: Element) -> Object_Iterator {
	return oj.object_iter(r, elem)
}

@(require_results)
object_iter_at :: proc(r: ^Reader, path: string) -> (Object_Iterator, Error) {
	return oj.object_iter_at(r, path)
}

@(require_results)
next_element :: proc(it: ^Array_Iterator) -> (elem: Element, ok: bool) {
	return oj.next_element(it)
}

@(require_results)
next_pair :: proc(it: ^Object_Iterator) -> (key: string, value: Element, ok: bool) {
	return oj.next_pair(it)
}

next :: proc {
	next_element,
	next_pair,
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

write_object_start :: proc(w: ^Writer) {
	oj.write_object_start(w)
}

write_object_end :: proc(w: ^Writer) {
	oj.write_object_end(w)
}

write_array_start :: proc(w: ^Writer) {
	oj.write_array_start(w)
}

write_array_end :: proc(w: ^Writer) {
	oj.write_array_end(w)
}

write_key :: proc(w: ^Writer, k: string) {
	oj.write_key(w, k)
}

write_string :: proc(w: ^Writer, s: string) {
	oj.write_string(w, s)
}

write_int :: proc(w: ^Writer, v: int) {
	oj.write_int(w, v)
}

write_f32 :: proc(w: ^Writer, v: f32) {
	oj.write_f32(w, v)
}

write_f64 :: proc(w: ^Writer, v: f64) {
	oj.write_f64(w, v)
}

write_bool :: proc(w: ^Writer, v: bool) {
	oj.write_bool(w, v)
}

write_null :: proc(w: ^Writer) {
	oj.write_null(w)
}

write_raw :: proc(w: ^Writer, json: string) {
	oj.write_raw(w, json)
}

writer_reset :: proc(w: ^Writer) {
	oj.writer_reset(w)
}

@(require_results)
writer_string :: proc(w: ^Writer) -> string {
	return oj.writer_string(w)
}

destroy :: proc {
	destroy_reader,
	destroy_writer,
}

// One-shot convenience functions

@(require_results)
get_string :: proc(
	data: []byte,
	key: string,
	allocator := context.allocator,
) -> (
	value: string,
	err: Error,
) {
	return oj.get_string(data, key, allocator)
}

@(require_results)
get_int :: proc(
	data: []byte,
	key: string,
	allocator := context.allocator,
) -> (
	value: int,
	err: Error,
) {
	return oj.get_int(data, key, allocator)
}

@(require_results)
get_i64 :: proc(
	data: []byte,
	key: string,
	allocator := context.allocator,
) -> (
	value: i64,
	err: Error,
) {
	return oj.get_i64(data, key, allocator)
}

@(require_results)
get_f64 :: proc(
	data: []byte,
	key: string,
	allocator := context.allocator,
) -> (
	value: f64,
	err: Error,
) {
	return oj.get_f64(data, key, allocator)
}

@(require_results)
get_bool :: proc(
	data: []byte,
	key: string,
	allocator := context.allocator,
) -> (
	value: bool,
	err: Error,
) {
	return oj.get_bool(data, key, allocator)
}
