package jsonimpl

import "core:mem"
import "core:strings"
import "core:unicode/utf8"

init_reader :: proc(r: ^Reader, size := DEFAULT_READER_SIZE, allocator := context.allocator) {
	r.backing_allocator = allocator
	r.memory = make([]byte, size, allocator)
	mem.arena_init(&r.arena, r.memory)
	r.max_cap = 0
}

BYTES_PER_ENTRY :: size_of(Lazy_Value) + size_of(KV) + size_of(ArrEntry)

parse :: proc(r: ^Reader, data: []byte) -> Error {
	needed_cap := max(u32(len(data) / 4), 64)

	if needed_cap > r.max_cap {
		needed_bytes := int(needed_cap) * BYTES_PER_ENTRY + len(data) + 64
		if needed_bytes > len(r.memory) {
			delete(r.memory, r.backing_allocator)
			r.memory = make([]byte, needed_bytes, r.backing_allocator)
			mem.arena_init(&r.arena, r.memory)
		} else {
			mem.arena_free_all(&r.arena)
		}
		r.max_cap = needed_cap

		alloc := mem.arena_allocator(&r.arena)
		r.parser.values = make([]Lazy_Value, needed_cap, alloc)
		r.parser.kv_buffer = make([]KV, needed_cap, alloc)
		r.parser.arr_buffer = make([]ArrEntry, needed_cap, alloc)

		r.buffer_offset = r.arena.offset
	} else {
		r.arena.offset = r.buffer_offset
	}

	return parser_parse(&r.parser, string(data))
}

destroy_reader :: proc(r: ^Reader) {
	if r.memory != nil {
		delete(r.memory, r.backing_allocator)
	}
	r^ = {}
}

read_string :: proc(r: ^Reader, key: string) -> (value: string, err: Error) {
	if r.parser.values == nil {
		return "", .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, r.parser.root, key)
	if !found {
		return "", .Key_Not_Found
	}
	#partial switch val.type {
	case .String:
		return val.data.str, .OK
	case .Raw_String:
		return unescape_string(&r.arena, val.data.str), .OK
	}
	return "", .Type_Mismatch
}

read_int :: proc(r: ^Reader, key: string) -> (value: int, err: Error) {
	i, e := read_i64(r, key)
	return int(i), e
}

read_i64 :: proc(r: ^Reader, key: string) -> (value: i64, err: Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, r.parser.root, key)
	if !found {
		return 0, .Key_Not_Found
	}

	#partial switch val.type {
	case .Number, .String, .Raw_String:
	case:
		return 0, .Type_Mismatch
	}
	result, ok := parse_i64_fast(val.data.str)
	if !ok {
		return 0, .Type_Mismatch
	}
	return result, .OK
}

read_f64 :: proc(r: ^Reader, key: string) -> (value: f64, err: Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, r.parser.root, key)
	if !found {
		return 0, .Key_Not_Found
	}

	#partial switch val.type {
	case .Number, .String, .Raw_String:
	case:
		return 0, .Type_Mismatch
	}
	result, ok := parse_f64_fast(val.data.str)
	if !ok {
		return 0, .Type_Mismatch
	}
	return result, .OK
}

read_bool :: proc(r: ^Reader, key: string) -> (value: bool, err: Error) {
	if r.parser.values == nil {
		return false, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, r.parser.root, key)
	if !found {
		return false, .Key_Not_Found
	}
	#partial switch val.type {
	case .True:
		return true, .OK
	case .False:
		return false, .OK
	case .String, .Raw_String:
		if val.data.str == "true" || val.data.str == "1" {
			return true, .OK
		} else if val.data.str == "false" || val.data.str == "0" {
			return false, .OK
		}
	}
	return false, .Type_Mismatch
}

exists :: proc(r: ^Reader, key: string) -> bool {
	if r.parser.values == nil {
		return false
	}

	_, found := get_by_path_from(&r.parser, r.parser.root, key)
	return found
}

is_null :: proc(r: ^Reader, key: string) -> bool {
	if r.parser.values == nil {
		return false
	}

	val, found := get_by_path_from(&r.parser, r.parser.root, key)
	return found && val.type == .Null
}

array_len :: proc(r: ^Reader, key: string) -> (int, Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}
	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, key)
	if !found {
		return 0, .Key_Not_Found
	}
	val := r.parser.values[idx]
	if val.type != .Array {
		return 0, .Type_Mismatch
	}
	return int(val.data.container), .OK
}

object_get_idx :: proc(p: ^Parser_State, obj_idx: u32, key: string) -> (u32, bool) {
	for &kv in p.kv_buffer[:p.kv_len] {
		if kv.owner_idx == obj_idx && kv.key == key {
			return kv.value_idx, true
		}
	}
	if strings.index_byte(key, '\\') >= 0 {
		return 0, false
	}
	for &kv in p.kv_buffer[:p.kv_len] {
		if kv.owner_idx == obj_idx && has_escapes(kv.key) {
			unescaped := unescape_string_temp(kv.key)
			if unescaped == key {
				return kv.value_idx, true
			}
		}
	}

	return 0, false
}

array_get_idx :: proc(p: ^Parser_State, arr_idx: u32, index: int) -> (u32, bool) {
	if index < 0 {
		return 0, false
	}
	count := 0
	for &entry in p.arr_buffer[:p.arr_len] {
		if entry.owner_idx == arr_idx {
			if count == index {
				return entry.value_idx, true
			}
			count += 1
		}
	}
	return 0, false
}

parse_array_idx :: proc(key: string) -> (int, bool) {
	if len(key) == 0 {
		return 0, false
	}
	result := 0
	for c in key {
		if c < '0' || c > '9' {
			return 0, false
		}
		result = result * 10 + int(c - '0')
	}
	return result, true
}

has_escapes :: proc(s: string) -> bool {
	return strings.index_byte(s, '\\') >= 0
}

unescape_string :: proc(arena: ^mem.Arena, s: string) -> string {
	if !has_escapes(s) {
		return s
	}
	buf := make([]byte, len(s), mem.arena_allocator(arena))
	return unescape_to(s, buf)
}

unescape_string_temp :: proc(s: string) -> string {
	if !has_escapes(s) {
		return s
	}
	buf := make([]byte, len(s), context.temp_allocator)
	return unescape_to(s, buf)
}

unescape_to :: proc(s: string, buf: []byte) -> string {
	n := strings.index_byte(s, '\\')
	if n < 0 {
		return s
	}

	copy(buf, s[:n])
	out_pos := n
	pos := n + 1

	for pos < len(s) {
		ch := s[pos]
		pos += 1

		switch ch {
		case '"':
			buf[out_pos] = '"'
			out_pos += 1
		case '\\':
			buf[out_pos] = '\\'
			out_pos += 1
		case '/':
			buf[out_pos] = '/'
			out_pos += 1
		case 'b':
			buf[out_pos] = '\b'
			out_pos += 1
		case 'f':
			buf[out_pos] = '\f'
			out_pos += 1
		case 'n':
			buf[out_pos] = '\n'
			out_pos += 1
		case 'r':
			buf[out_pos] = '\r'
			out_pos += 1
		case 't':
			buf[out_pos] = '\t'
			out_pos += 1
		case 'u':
			if pos + 4 > len(s) {
				buf[out_pos] = '\\'
				buf[out_pos + 1] = 'u'
				out_pos += 2
				continue
			}
			hex := s[pos:pos + 4]
			codepoint, ok := parse_hex4(hex)
			if !ok {
				buf[out_pos] = '\\'
				buf[out_pos + 1] = 'u'
				out_pos += 2
				continue
			}
			pos += 4

			if codepoint >= 0xD800 && codepoint <= 0xDBFF {
				if pos + 6 <= len(s) && s[pos] == '\\' && s[pos + 1] == 'u' {
					hex2 := s[pos + 2:pos + 6]
					low, ok2 := parse_hex4(hex2)
					if ok2 && low >= 0xDC00 && low <= 0xDFFF {
						combined := 0x10000 + ((codepoint - 0xD800) << 10) + (low - 0xDC00)
						encoded, width := utf8.encode_rune(rune(combined))
						copy(buf[out_pos:], encoded[:width])
						out_pos += width
						pos += 6
						continue
					}
				}
			}

			encoded, width := utf8.encode_rune(rune(codepoint))
			copy(buf[out_pos:], encoded[:width])
			out_pos += width
		case:
			buf[out_pos] = '\\'
			buf[out_pos + 1] = ch
			out_pos += 2
		}

		next_escape := strings.index_byte(s[pos:], '\\')
		if next_escape < 0 {
			copy(buf[out_pos:], s[pos:])
			out_pos += len(s) - pos
			break
		}
		copy(buf[out_pos:], s[pos:pos + next_escape])
		out_pos += next_escape
		pos += next_escape + 1
	}

	return string(buf[:out_pos])
}

parse_hex4 :: proc(s: string) -> (u32, bool) {
	if len(s) < 4 {
		return 0, false
	}
	result: u32 = 0
	for i in 0 ..< 4 {
		c := s[i]
		digit: u32
		switch c {
		case '0' ..= '9':
			digit = u32(c - '0')
		case 'a' ..= 'f':
			digit = u32(c - 'a' + 10)
		case 'A' ..= 'F':
			digit = u32(c - 'A' + 10)
		case:
			return 0, false
		}
		result = (result << 4) | digit
	}
	return result, true
}

get_string :: proc(data: []byte, key: string, allocator := context.allocator) -> (string, Error) {
	r: Reader
	init_reader(&r, max(len(data) * 4, 4096), allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return "", err
	}
	return read_string(&r, key)
}

get_int :: proc(data: []byte, key: string, allocator := context.allocator) -> (int, Error) {
	r: Reader
	init_reader(&r, max(len(data) * 4, 4096), allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return 0, err
	}
	return read_int(&r, key)
}

get_i64 :: proc(data: []byte, key: string, allocator := context.allocator) -> (i64, Error) {
	r: Reader
	init_reader(&r, max(len(data) * 4, 4096), allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return 0, err
	}
	return read_i64(&r, key)
}

get_f64 :: proc(data: []byte, key: string, allocator := context.allocator) -> (f64, Error) {
	r: Reader
	init_reader(&r, max(len(data) * 4, 4096), allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return 0, err
	}
	return read_f64(&r, key)
}

get_bool :: proc(data: []byte, key: string, allocator := context.allocator) -> (bool, Error) {
	r: Reader
	init_reader(&r, max(len(data) * 4, 4096), allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return false, err
	}

	return read_bool(&r, key)
}

root_element :: proc(r: ^Reader) -> Element {
	return Element(r.parser.root)
}

element_at :: proc(r: ^Reader, path: string) -> (Element, Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	if len(path) == 0 {
		return Element(r.parser.root), .OK
	}

	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, path)
	if !found {
		return 0, .Key_Not_Found
	}

	return Element(idx), .OK
}

array_elements :: proc(r: ^Reader, path: string) -> ([]Element, Error) {
	if r.parser.values == nil {
		return nil, .Not_Parsed
	}

	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, path)
	if !found {
		return nil, .Key_Not_Found
	}

	val := r.parser.values[idx]
	if val.type != .Array {
		return nil, .Type_Mismatch
	}

	return collect_array_elements(r, idx, val.data.container), .OK
}

array_element :: proc(r: ^Reader, path: string, index: int) -> (Element, Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, path)
	if !found {
		return 0, .Key_Not_Found
	}

	val := r.parser.values[idx]
	if val.type != .Array {
		return 0, .Type_Mismatch
	}

	if index < 0 || index >= int(val.data.container) {
		return 0, .Key_Not_Found
	}

	elem_idx, elem_found := array_get_idx(&r.parser, idx, index)
	if !elem_found {
		return 0, .Key_Not_Found
	}

	return Element(elem_idx), .OK
}

obj_element :: proc(r: ^Reader, path: string, key: string) -> (Element, Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, path)
	if !found {
		return 0, .Key_Not_Found
	}

	val := r.parser.values[idx]
	if val.type != .Object {
		return 0, .Type_Mismatch
	}

	elem_idx, elem_found := object_get_idx(&r.parser, idx, key)
	if !elem_found {
		return 0, .Key_Not_Found
	}

	return Element(elem_idx), .OK
}

obj_element_from :: proc(r: ^Reader, elem: Element, key: string) -> (Element, Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val := r.parser.values[u32(elem)]
	if val.type != .Object {
		return 0, .Type_Mismatch
	}

	elem_idx, found := object_get_idx(&r.parser, u32(elem), key)
	if !found {
		return 0, .Key_Not_Found
	}

	return Element(elem_idx), .OK
}

array_element_from :: proc(r: ^Reader, elem: Element, index: int) -> (Element, Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val := r.parser.values[u32(elem)]
	if val.type != .Array {
		return 0, .Type_Mismatch
	}

	if index < 0 || index >= int(val.data.container) {
		return 0, .Key_Not_Found
	}

	elem_idx, found := array_get_idx(&r.parser, u32(elem), index)
	if !found {
		return 0, .Key_Not_Found
	}

	return Element(elem_idx), .OK
}

array_elements_from :: proc(r: ^Reader, elem: Element) -> ([]Element, Error) {
	if r.parser.values == nil {
		return nil, .Not_Parsed
	}

	val := r.parser.values[u32(elem)]
	if val.type != .Array {
		return nil, .Type_Mismatch
	}

	return collect_array_elements(r, u32(elem), val.data.container), .OK
}

collect_array_elements :: proc(r: ^Reader, arr_idx: u32, count: u32) -> []Element {
	if count == 0 {
		return nil
	}

	result := make([]Element, count, mem.arena_allocator(&r.arena))
	i: u32 = 0
	for &entry in r.parser.arr_buffer[:r.parser.arr_len] {
		if entry.owner_idx == arr_idx {
			result[i] = Element(entry.value_idx)
			i += 1
			if i >= count {
				break
			}
		}
	}

	return result
}

read_string_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: string, err: Error) {
	if r.parser.values == nil {
		return "", .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, u32(elem), field)
	if !found {
		return "", .Key_Not_Found
	}

	#partial switch val.type {
	case .String:
		return val.data.str, .OK
	case .Raw_String:
		return unescape_string(&r.arena, val.data.str), .OK
	}

	return "", .Type_Mismatch
}

read_int_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: int, err: Error) {
	i, e := read_i64_elem(r, elem, field)
	return int(i), e
}

read_i64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: i64, err: Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, u32(elem), field)
	if !found {
		return 0, .Key_Not_Found
	}

	#partial switch val.type {
	case .Number, .String, .Raw_String:
	case:
		return 0, .Type_Mismatch
	}

	result, ok := parse_i64_fast(val.data.str)
	if !ok {
		return 0, .Type_Mismatch
	}

	return result, .OK
}

read_f64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: f64, err: Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, u32(elem), field)
	if !found {
		return 0, .Key_Not_Found
	}

	#partial switch val.type {
	case .Number, .String, .Raw_String:
	case:
		return 0, .Type_Mismatch
	}

	result, ok := parse_f64_fast(val.data.str)
	if !ok {
		return 0, .Type_Mismatch
	}

	return result, .OK
}

read_bool_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: bool, err: Error) {
	if r.parser.values == nil {
		return false, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, u32(elem), field)
	if !found {
		return false, .Key_Not_Found
	}

	#partial switch val.type {
	case .True:
		return true, .OK
	case .False:
		return false, .OK
	case .String, .Raw_String:
		if val.data.str == "true" || val.data.str == "1" {
			return true, .OK
		} else if val.data.str == "false" || val.data.str == "0" {
			return false, .OK
		}
	}

	return false, .Type_Mismatch
}

read_string_value :: proc(r: ^Reader, elem: Element) -> (value: string, err: Error) {
	if r.parser.values == nil {
		return "", .Not_Parsed
	}

	val := r.parser.values[u32(elem)]
	#partial switch val.type {
	case .String:
		return val.data.str, .OK
	case .Raw_String:
		return unescape_string(&r.arena, val.data.str), .OK
	}

	return "", .Type_Mismatch
}

read_int_value :: proc(r: ^Reader, elem: Element) -> (value: int, err: Error) {
	i, e := read_i64_value(r, elem)
	return int(i), e
}

read_i64_value :: proc(r: ^Reader, elem: Element) -> (value: i64, err: Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val := r.parser.values[u32(elem)]
	#partial switch val.type {
	case .Number, .String, .Raw_String:
	case:
		return 0, .Type_Mismatch
	}

	result, ok := parse_i64_fast(val.data.str)
	if !ok {
		return 0, .Type_Mismatch
	}

	return result, .OK
}

read_f64_value :: proc(r: ^Reader, elem: Element) -> (value: f64, err: Error) {
	if r.parser.values == nil {
		return 0, .Not_Parsed
	}

	val := r.parser.values[u32(elem)]
	#partial switch val.type {
	case .Number, .String, .Raw_String:
	case:
		return 0, .Type_Mismatch
	}

	result, ok := parse_f64_fast(val.data.str)
	if !ok {
		return 0, .Type_Mismatch
	}

	return result, .OK
}

read_bool_value :: proc(r: ^Reader, elem: Element) -> (value: bool, err: Error) {
	if r.parser.values == nil {
		return false, .Not_Parsed
	}

	val := r.parser.values[u32(elem)]
	#partial switch val.type {
	case .True:
		return true, .OK
	case .False:
		return false, .OK
	case .String, .Raw_String:
		if val.data.str == "true" || val.data.str == "1" {
			return true, .OK
		} else if val.data.str == "false" || val.data.str == "0" {
			return false, .OK
		}
	}

	return false, .Type_Mismatch
}

read_raw :: proc(r: ^Reader, path: string) -> (string, Error) {
	if r.parser.values == nil {
		return "", .Not_Parsed
	}
	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, path)
	if !found {
		return "", .Key_Not_Found
	}
	return extract_raw_value(&r.parser, idx)
}

read_raw_elem :: proc(r: ^Reader, elem: Element, field: string) -> (string, Error) {
	if r.parser.values == nil {
		return "", .Not_Parsed
	}
	idx, found := get_idx_by_path_from(&r.parser, u32(elem), field)
	if !found {
		return "", .Key_Not_Found
	}
	return extract_raw_value(&r.parser, idx)
}

@(private)
extract_raw_value :: proc(p: ^Parser_State, idx: u32) -> (string, Error) {
	val := p.values[idx]
	input := p.input
	start := int(val.input_pos)

	#partial switch val.type {
	case .Object, .Array:
		end := scan_container_end(input, start)
		if end < 0 {
			return "", .Invalid_JSON
		}
		return input[start:end], .OK
	case .String, .Raw_String:
		end := scan_string_end(input, start)
		if end < 0 {
			return "", .Invalid_JSON
		}
		return input[start:end], .OK
	case .Number:
		return val.data.str, .OK
	case .True:
		return "true", .OK
	case .False:
		return "false", .OK
	case .Null:
		return "null", .OK
	}
	return "", .Type_Mismatch
}

@(private)
scan_container_end :: proc(input: string, start: int) -> int {
	if start >= len(input) {
		return -1
	}
	open := input[start]
	close: byte = '}' if open == '{' else ']'
	depth := 1
	in_string := false
	i := start + 1
	for i < len(input) && depth > 0 {
		c := input[i]
		if in_string {
			if c == '\\' {
				i += 1
			} else if c == '"' {
				in_string = false
			}
		} else {
			if c == '"' {
				in_string = true
			} else if c == open {
				depth += 1
			} else if c == close {
				depth -= 1
			}
		}
		i += 1
	}
	if depth != 0 {
		return -1
	}
	return i
}

@(private)
scan_string_end :: proc(input: string, start: int) -> int {
	if start >= len(input) || input[start] != '"' {
		return -1
	}
	i := start + 1
	for i < len(input) {
		c := input[i]
		if c == '\\' {
			i += 2
			continue
		}
		if c == '"' {
			return i + 1
		}
		i += 1
	}
	return -1
}

element_value_type :: proc(r: ^Reader, elem: Element) -> Value_Type {
	return r.parser.values[u32(elem)].type
}

object_keys :: proc(r: ^Reader, elem: Element) -> []string {
	val := r.parser.values[u32(elem)]
	if val.type != .Object {
		return nil
	}
	count := 0
	for &kv in r.parser.kv_buffer[:r.parser.kv_len] {
		if kv.owner_idx == u32(elem) {
			count += 1
		}
	}
	if count == 0 {
		return nil
	}
	result := make([]string, count, mem.arena_allocator(&r.arena))
	i := 0
	for &kv in r.parser.kv_buffer[:r.parser.kv_len] {
		if kv.owner_idx == u32(elem) {
			result[i] = kv.key
			i += 1
		}
	}
	return result
}

get_by_path_from :: proc(p: ^Parser_State, start_idx: u32, path: string) -> (Lazy_Value, bool) {
	idx, found := get_idx_by_path_from(p, start_idx, path)
	if !found {
		return {}, false
	}

	return p.values[idx], true
}

get_idx_by_path_from :: proc(p: ^Parser_State, start_idx: u32, path: string) -> (u32, bool) {
	if p.values_len == 0 {
		return 0, false
	}
	if path == "" {
		return start_idx, true
	}

	current_idx := start_idx
	remaining := path

	for remaining != "" {
		dot_idx := strings.index_byte(remaining, '.')
		key: string
		if dot_idx < 0 {
			key = remaining
			remaining = ""
		} else {
			key = remaining[:dot_idx]
			remaining = remaining[dot_idx + 1:]
		}

		current := p.values[current_idx]

		if idx, ok := parse_array_idx(key); ok {
			if current.type != .Array {
				return 0, false
			}
			next_idx, found := array_get_idx(p, current_idx, idx)
			if !found {
				return 0, false
			}
			current_idx = next_idx
			continue
		}

		if current.type != .Object {
			return 0, false
		}
		next_idx, found := object_get_idx(p, current_idx, key)
		if !found {
			return 0, false
		}
		current_idx = next_idx
	}

	return current_idx, true
}
