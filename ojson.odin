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

// Lifecycle. Reader and Writer share one shape:
//
//	r: ojson.Reader
//	ojson.init(&r)
//	defer ojson.destroy(&r)

init_reader :: proc(r: ^Reader, size := DEFAULT_READER_SIZE, allocator := context.allocator) {
	oj.init_reader(r, size, allocator)
}

init_writer :: proc(
	w: ^Writer,
	buffer_size := DEFAULT_WRITE_BUFFER_SIZE,
	allocator := context.allocator,
) {
	oj.init_writer(w, buffer_size, allocator)
}

init :: proc {
	init_reader,
	init_writer,
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

// Parsing. The input is not mutated and must outlive the parsed state:
// reads return views into it.

parse_bytes :: proc(r: ^Reader, data: []byte) -> Error {
	return oj.parse(r, data)
}

parse_string :: proc(r: ^Reader, data: string) -> Error {
	return oj.parse(r, transmute([]byte)data)
}

parse :: proc {
	parse_bytes,
	parse_string,
}

// Reading by dot-separated path from the document root, e.g. "items.0.price".

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

// Document queries.

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

// Navigating to elements. An Element is a handle to a value in the parsed
// document; it avoids re-walking a path prefix for every read. Each name
// accepts a path from the root or an Element already in hand.

@(require_results)
root_element :: proc(r: ^Reader) -> Element {
	return oj.root_element(r)
}

@(require_results)
element_at :: proc(r: ^Reader, path: string) -> (Element, Error) {
	return oj.element_at(r, path)
}

// element(r) is the document root, element(r, "a.b") the value at a path.
element :: proc {
	root_element,
	element_at,
}

@(require_results)
element_value_type :: proc(r: ^Reader, elem: Element) -> Value_Type {
	return oj.element_value_type(r, elem)
}

@(require_results)
array_element_path :: proc(r: ^Reader, path: string, index: int) -> (Element, Error) {
	return oj.array_element(r, path, index)
}

@(require_results)
array_element_from :: proc(r: ^Reader, elem: Element, index: int) -> (Element, Error) {
	return oj.array_element_from(r, elem, index)
}

array_element :: proc {
	array_element_path,
	array_element_from,
}

@(require_results)
obj_element_path :: proc(r: ^Reader, path: string, key: string) -> (Element, Error) {
	return oj.obj_element(r, path, key)
}

@(require_results)
obj_element_from :: proc(r: ^Reader, elem: Element, key: string) -> (Element, Error) {
	return oj.obj_element_from(r, elem, key)
}

obj_element :: proc {
	obj_element_path,
	obj_element_from,
}

// Allocating collectors. These build a slice in the reader arena; prefer the
// iterators below when you are only walking the container once.

@(require_results)
array_elements_path :: proc(r: ^Reader, path: string) -> ([]Element, Error) {
	return oj.array_elements(r, path)
}

@(require_results)
array_elements_from :: proc(r: ^Reader, elem: Element) -> ([]Element, Error) {
	return oj.array_elements_from(r, elem)
}

array_elements :: proc {
	array_elements_path,
	array_elements_from,
}

@(require_results)
object_keys :: proc(r: ^Reader, elem: Element) -> []string {
	return oj.object_keys(r, elem)
}

// Non-allocating iteration.
//
//	it, _ := ojson.array_iter(&r, "items")
//	for item in ojson.next(&it) { ... }
//
//	oit := ojson.object_iter(&r, elem)
//	for key, value in ojson.next(&oit) { ... }

@(require_results)
array_iter_elem :: proc(r: ^Reader, elem: Element) -> Array_Iterator {
	return oj.array_iter(r, elem)
}

@(require_results)
array_iter_at :: proc(r: ^Reader, path: string) -> (Array_Iterator, Error) {
	return oj.array_iter_at(r, path)
}

array_iter :: proc {
	array_iter_elem,
	array_iter_at,
}

@(require_results)
object_iter_elem :: proc(r: ^Reader, elem: Element) -> Object_Iterator {
	return oj.object_iter(r, elem)
}

@(require_results)
object_iter_at :: proc(r: ^Reader, path: string) -> (Object_Iterator, Error) {
	return oj.object_iter_at(r, path)
}

object_iter :: proc {
	object_iter_elem,
	object_iter_at,
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

@(require_results)
unescape_string :: proc(r: ^Reader, s: string) -> string {
	return oj.unescape_string(r, s)
}

@(require_results)
parse_int_key :: proc($T: typeid, key: string) -> (value: T, ok: bool) {
	return oj.parse_int_key(T, key)
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

// Building JSON. Commas between values are inserted automatically.

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

write_u64 :: proc(w: ^Writer, v: u64) {
	oj.write_u64(w, v)
}

write_key_i64 :: proc(w: ^Writer, k: i64) {
	oj.write_key_i64(w, k)
}

write_key_u64 :: proc(w: ^Writer, k: u64) {
	oj.write_key_u64(w, k)
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

// Object key and value in one call.

write_field_string :: proc(w: ^Writer, key: string, v: string) {
	oj.write_key(w, key)
	oj.write_string(w, v)
}

write_field_int :: proc(w: ^Writer, key: string, v: int) {
	oj.write_key(w, key)
	oj.write_int(w, v)
}

write_field_f32 :: proc(w: ^Writer, key: string, v: f32) {
	oj.write_key(w, key)
	oj.write_f32(w, v)
}

write_field_f64 :: proc(w: ^Writer, key: string, v: f64) {
	oj.write_key(w, key)
	oj.write_f64(w, v)
}

write_field_bool :: proc(w: ^Writer, key: string, v: bool) {
	oj.write_key(w, key)
	oj.write_bool(w, v)
}

write_field_null :: proc(w: ^Writer, key: string) {
	oj.write_key(w, key)
	oj.write_null(w)
}

write_field_raw :: proc(w: ^Writer, key: string, json: string) {
	oj.write_key(w, key)
	oj.write_raw(w, json)
}

// One name per value type, resolved by argument shape:
//   write(&w, "Alice")       a value
//   write(&w, "age", 30)     object key + value
// Float literals would be ambiguous with both f32 and f64 in the group, so
// only f64 is a member; use write_f32/write_field_f32 directly for f32.
// The raw and null variants stay standalone: their string arguments would
// collide with the string value and field members.
write :: proc {
	write_string,
	write_int,
	write_f64,
	write_bool,
	write_field_string,
	write_field_int,
	write_field_f64,
	write_field_bool,
}

writer_reset :: proc(w: ^Writer) {
	oj.writer_reset(w)
}

@(require_results)
writer_string :: proc(w: ^Writer) -> string {
	return oj.writer_string(w)
}

marshal_to :: proc(w: ^Writer, value: any, pretty := false) -> (result: []byte, err: Error) {
	return oj.marshal_to(w, value, pretty)
}

pretty_print :: proc(data: []byte, allocator := context.allocator) -> (string, Error) {
	return oj.pretty_print(data, allocator)
}

// One-shot convenience functions. Each parses with a temporary reader;
// get_string clones the value with the given allocator and the caller owns it.

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
