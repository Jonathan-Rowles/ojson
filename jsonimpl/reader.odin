package jsonimpl

import "base:intrinsics"
import "core:mem"
import "core:simd"
import "core:strings"
import "core:unicode/utf8"

init_reader :: proc(r: ^Reader, size := DEFAULT_READER_SIZE, allocator := context.allocator) {
	r.backing_allocator = allocator
	if size > 0 {
		r.block = make([]byte, size, allocator)
	}
}

INITIAL_ENTRY_DIVISOR :: 32
SCRATCH_DIVISOR :: 16
MIN_SCRATCH_BYTES :: 1024
CARVE_BYTES_PER_ENTRY :: size_of(Lazy_Value) + (size_of(u64) + size_of(u32)) * 2 + size_of(ArrEntry)

scratch_alloc :: proc(r: ^Reader, n: int) -> []byte {
	need := (n + 7) & ~int(7)
	s := &r.scratch
	if s.offset + need <= len(s.base) {
		buf := s.base[s.offset:][:n]
		s.offset += need
		return buf
	}
	if s.overflow_offset + need <= len(s.overflow) {
		buf := s.overflow[s.overflow_offset:][:n]
		s.overflow_offset += need
		return buf
	}
	payload := max(need, len(s.overflow) * 2, 4096)
	raw := make([]byte, size_of(Scratch_Chunk) + payload, r.backing_allocator)
	head := cast(^Scratch_Chunk)raw_data(raw)
	head.next = s.chunks
	head.size = len(raw)
	s.chunks = head
	s.overflow = raw[size_of(Scratch_Chunk):]
	s.overflow_offset = need
	return s.overflow[:n]
}

scratch_make :: proc(r: ^Reader, $T: typeid, count: int) -> []T {
	return mem.slice_data_cast([]T, scratch_alloc(r, count * size_of(T)))
}

scratch_reset :: proc(r: ^Reader) {
	s := &r.scratch
	s.offset = 0
	chunk := s.chunks
	for chunk != nil {
		next := chunk.next
		chunk_bytes := mem.slice_ptr(cast(^byte)chunk, chunk.size)
		delete(chunk_bytes, r.backing_allocator)
		chunk = next
	}
	s.chunks = nil
	s.overflow = nil
	s.overflow_offset = 0
}

grow_slice :: proc(p: ^Parser_State, s: ^[]$T, used: u32, min_cap: u32) {
	new_cap := max(u32(len(s^)) * 2, 64)
	for new_cap < min_cap {
		new_cap *= 2
	}
	grown := make([]T, new_cap, p.allocator)
	copy(grown, s^[:used])
	old := rawptr(raw_data(s^))
	if old != nil && (uintptr(old) < p.block_start || uintptr(old) >= p.block_end) {
		delete(s^, p.allocator)
	}
	s^ = grown
}

@(private)
carve :: proc(block: []byte, off: ^int, $T: typeid, count: u32) -> []T {
	start := off^
	off^ += int(count) * size_of(T)
	return mem.slice_data_cast([]T, block[start:off^])
}

@(private)
carve_parser_buffers :: proc(r: ^Reader, guess: u32) {
	p := &r.parser
	off := 0
	p.values = carve(r.block, &off, Lazy_Value, guess)
	p.kv_keys = carve(r.block, &off, u64, guess)
	p.kv_stack_keys = carve(r.block, &off, u64, guess)
	p.kv_vals = carve(r.block, &off, u32, guess)
	p.kv_stack_vals = carve(r.block, &off, u32, guess)
	p.arr_buffer = carve(r.block, &off, ArrEntry, guess)
	r.scratch.base = r.block[off:]
	p.block_start = uintptr(raw_data(r.block))
	p.block_end = p.block_start + uintptr(len(r.block))
	r.block_cap = guess
}

@(private)
outside_block :: proc(p: ^Parser_State, ptr: rawptr) -> bool {
	return ptr != nil && (uintptr(ptr) < p.block_start || uintptr(ptr) >= p.block_end)
}

@(private)
free_escaped_buffers :: proc(r: ^Reader) {
	p := &r.parser
	if outside_block(p, raw_data(p.values)) {
		delete(p.values, p.allocator)
	}
	if outside_block(p, raw_data(p.kv_keys)) {
		delete(p.kv_keys, p.allocator)
	}
	if outside_block(p, raw_data(p.kv_vals)) {
		delete(p.kv_vals, p.allocator)
	}
	if outside_block(p, raw_data(p.kv_stack_keys)) {
		delete(p.kv_stack_keys, p.allocator)
	}
	if outside_block(p, raw_data(p.kv_stack_vals)) {
		delete(p.kv_stack_vals, p.allocator)
	}
	if outside_block(p, raw_data(p.arr_buffer)) {
		delete(p.arr_buffer, p.allocator)
	}
	p.values = nil
	p.kv_keys = nil
	p.kv_vals = nil
	p.kv_stack_keys = nil
	p.kv_stack_vals = nil
	p.arr_buffer = nil
}

parse :: proc(r: ^Reader, data: []byte) -> Error {
	guess := max(u32(len(data) / INITIAL_ENTRY_DIVISOR), 64)

	p := &r.parser
	p.allocator = r.backing_allocator

	scratch_reset(r)

	scratch_bytes := max(len(data) / SCRATCH_DIVISOR, MIN_SCRATCH_BYTES)
	needed := int(guess) * CARVE_BYTES_PER_ENTRY + scratch_bytes
	if needed > len(r.block) {
		free_escaped_buffers(r)
		delete(r.block, r.backing_allocator)
		r.block = make([]byte, needed, r.backing_allocator)
		carve_parser_buffers(r, guess)
	} else if guess > r.block_cap {
		free_escaped_buffers(r)
		carve_parser_buffers(r, guess)
	}

	r.generation += 1

	err := parser_parse(p, string(data))
	r.parse_failed = err != .OK
	return err
}

@(private)
reader_ready :: #force_inline proc(r: ^Reader) -> bool {
	return r.parser.values != nil && !r.parse_failed
}

make_element :: #force_inline proc(r: ^Reader, idx: u32) -> Element {
	when ODIN_DEBUG {
		assert(
			idx <= ELEMENT_INDEX_MASK,
			"ojson: document has too many values for debug element tagging",
		)
		return Element(idx | (r.generation & 0xFF) << ELEMENT_INDEX_BITS)
	} else {
		return Element(idx)
	}
}

element_index :: #force_inline proc(r: ^Reader, elem: Element) -> u32 {
	when ODIN_DEBUG {
		assert(
			u32(elem) >> ELEMENT_INDEX_BITS == r.generation & 0xFF,
			"ojson: Element used after its Reader was re-parsed",
		)
		return u32(elem) & ELEMENT_INDEX_MASK
	} else {
		return u32(elem)
	}
}

destroy_reader :: proc(r: ^Reader) {
	scratch_reset(r)
	free_escaped_buffers(r)
	if r.block != nil {
		delete(r.block, r.backing_allocator)
	}
	r^ = {}
}

@(require_results)
read_string :: proc(r: ^Reader, key: string) -> (value: string, err: Error) {
	if !reader_ready(r) {
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
		return unescape_string(r, val.data.str), .OK
	}
	return "", .Type_Mismatch
}

@(require_results)
read_string_prefix :: proc(r: ^Reader, key: string, limit: int) -> (value: string, err: Error) {
	if !reader_ready(r) {
		return "", .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, r.parser.root, key)
	if !found {
		return "", .Key_Not_Found
	}
	#partial switch val.type {
	case .String, .Raw_String:
		return unescape_string_prefix(r, val.data.str, limit), .OK
	}
	return "", .Type_Mismatch
}

@(require_results)
read_int :: proc(r: ^Reader, key: string) -> (value: int, err: Error) {
	i, e := read_i64(r, key)
	return int(i), e
}

@(require_results)
read_i64 :: proc(r: ^Reader, key: string) -> (value: i64, err: Error) {
	if !reader_ready(r) {
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

@(require_results)
read_f64 :: proc(r: ^Reader, key: string) -> (value: f64, err: Error) {
	if !reader_ready(r) {
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

@(require_results)
read_bool :: proc(r: ^Reader, key: string) -> (value: bool, err: Error) {
	if !reader_ready(r) {
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

@(require_results)
exists :: proc(r: ^Reader, key: string) -> bool {
	if !reader_ready(r) {
		return false
	}

	_, found := get_by_path_from(&r.parser, r.parser.root, key)
	return found
}

@(require_results)
is_null :: proc(r: ^Reader, key: string) -> bool {
	if !reader_ready(r) {
		return false
	}

	val, found := get_by_path_from(&r.parser, r.parser.root, key)
	return found && val.type == .Null
}

@(require_results)
array_len :: proc(r: ^Reader, key: string) -> (int, Error) {
	if !reader_ready(r) {
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
	return int(val.data.container.count), .OK
}

object_member_range :: #force_inline proc(p: ^Parser_State, obj_idx: u32) -> (u32, u32) {
	if obj_idx >= p.values_len {
		return 0, 0
	}
	val := p.values[obj_idx]
	if val.type != .Object {
		return 0, 0
	}
	return val.data.container.entries_begin, val.data.container.entries_end
}

kv_key :: #force_inline proc(p: ^Parser_State, i: u32) -> string {
	packed := p.kv_keys[i]
	return p.input[packed >> 32:(packed >> 32) + (packed & 0xFFFFFFFF)]
}

array_entries :: proc(p: ^Parser_State, arr_idx: u32) -> []ArrEntry {
	if arr_idx >= p.values_len {
		return nil
	}
	val := p.values[arr_idx]
	if val.type != .Array {
		return nil
	}
	return p.arr_buffer[val.data.container.entries_begin:val.data.container.entries_end]
}

object_get_idx :: proc(p: ^Parser_State, obj_idx: u32, key: string) -> (u32, bool) {
	begin, end := object_member_range(p, obj_idx)
	klen := u64(len(key))

	if begin < end {
		packed := p.kv_keys[begin]
		if packed & 0xFFFFFFFF == klen && p.input[packed >> 32:(packed >> 32) + klen] == key {
			return p.kv_vals[begin], true
		}
	}
	if begin + 1 < end {
		packed := p.kv_keys[begin + 1]
		if packed & 0xFFFFFFFF == klen && p.input[packed >> 32:(packed >> 32) + klen] == key {
			return p.kv_vals[begin + 1], true
		}
	}

	first := uint(key[0]) if len(key) > 0 else 0
	hint_slot := (uint(len(key)) * 31 + first) & 7
	hint := p.key_hints[hint_slot]
	if hint >= 2 && begin + hint < end {
		packed := p.kv_keys[begin + hint]
		if packed & 0xFFFFFFFF == klen && p.input[packed >> 32:(packed >> 32) + klen] == key {
			return p.kv_vals[begin + hint], true
		}
	}

	i := begin + 2
	if end - begin >= 16 {
		klen4 := simd.u64x4(klen)
		len_mask: simd.u64x4 : 0xFFFFFFFF
		for i + 4 <= end {
			chunk := intrinsics.unaligned_load(cast(^simd.u64x4)&p.kv_keys[i])
			eq := simd.lanes_eq(chunk & len_mask, klen4)
			if simd.reduce_or(eq) != 0 {
				for j in i ..< i + 4 {
					packed := p.kv_keys[j]
					if packed & 0xFFFFFFFF == klen {
						if p.input[packed >> 32:(packed >> 32) + klen] == key {
							p.key_hints[hint_slot] = j - begin
							return p.kv_vals[j], true
						}
					}
				}
			}
			i += 4
		}
	}
	for ; i < end; i += 1 {
		packed := p.kv_keys[i]
		if packed & 0xFFFFFFFF == klen {
			if p.input[packed >> 32:(packed >> 32) + klen] == key {
				p.key_hints[hint_slot] = i - begin
				return p.kv_vals[i], true
			}
		}
	}
	if strings.index_byte(key, '\\') >= 0 {
		return 0, false
	}
	for m := begin; m < end; m += 1 {
		k := kv_key(p, m)
		if has_escapes(k) {
			unescaped := unescape_string_temp(k)
			if unescaped == key {
				return p.kv_vals[m], true
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
	for &entry in array_entries(p, arr_idx) {
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
	for i in 0 ..< len(key) {
		c := key[i]
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

unescape_string :: proc(r: ^Reader, s: string) -> string {
	if !has_escapes(s) {
		return s
	}
	buf := scratch_alloc(r, len(s))
	return unescape_to(s, buf)
}

unescape_string_prefix :: proc(r: ^Reader, s: string, limit: int) -> string {
	capped := min(len(s), max(limit, 0))
	if capped == 0 {
		return ""
	}
	if !has_escapes(s[:capped]) {
		return s[:capped]
	}
	return unescape_to(s, scratch_alloc(r, capped))
}

unescape_string_temp :: proc(s: string) -> string {
	if !has_escapes(s) {
		return s
	}
	buf := make([]byte, len(s), context.temp_allocator)
	return unescape_to(s, buf)
}

parse_int_key :: proc(
	$T: typeid,
	key: string,
) -> (
	value: T,
	ok: bool,
) where intrinsics.type_is_integer(T) {
	digits := key
	negative := false
	if len(digits) > 0 && digits[0] == '-' {
		negative = true
		digits = digits[1:]
	}
	if len(digits) == 0 {
		return 0, false
	}

	magnitude: u64
	for i in 0 ..< len(digits) {
		c := digits[i]
		if c < '0' || c > '9' {
			return 0, false
		}
		d := u64(c - '0')
		if magnitude > (max(u64) - d) / 10 {
			return 0, false
		}
		magnitude = magnitude * 10 + d
	}

	full := i128(magnitude)
	if negative {
		full = -full
	}
	if full < i128(min(T)) || full > i128(max(T)) {
		return 0, false
	}
	return T(full), true
}

unescape_to :: proc(s: string, buf: []byte) -> string {
	limit := len(buf)
	head := s[:min(len(s), limit)]
	n := strings.index_byte(head, '\\')
	if n < 0 {
		return head
	}

	copy(buf, s[:n])
	out_pos := n
	pos := n + 1

	for pos < len(s) && out_pos < limit {
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
				out_pos += copy(buf[out_pos:], "\\u")
				continue
			}
			hex := s[pos:pos + 4]
			codepoint, ok := parse_hex4(hex)
			if !ok {
				out_pos += copy(buf[out_pos:], "\\u")
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
						out_pos += copy(buf[out_pos:], encoded[:width])
						pos += 6
						continue
					}
				}
			}

			encoded, width := utf8.encode_rune(rune(codepoint))
			out_pos += copy(buf[out_pos:], encoded[:width])
		case:
			literal := [2]byte{'\\', ch}
			out_pos += copy(buf[out_pos:], literal[:])
		}

		tail := s[pos:]
		if len(tail) > limit - out_pos {
			tail = tail[:limit - out_pos]
		}
		next_escape := strings.index_byte(tail, '\\')
		if next_escape < 0 {
			out_pos += copy(buf[out_pos:], tail)
			break
		}
		out_pos += copy(buf[out_pos:], tail[:next_escape])
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

@(require_results)
get_string :: proc(data: []byte, key: string, allocator := context.allocator) -> (string, Error) {
	r: Reader
	init_reader(&r, allocator = allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return "", err
	}
	value, err := read_string(&r, key)
	if err != .OK {
		return "", err
	}
	return strings.clone(value, allocator), .OK
}

@(require_results)
get_int :: proc(data: []byte, key: string, allocator := context.allocator) -> (int, Error) {
	r: Reader
	init_reader(&r, allocator = allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return 0, err
	}
	return read_int(&r, key)
}

@(require_results)
get_i64 :: proc(data: []byte, key: string, allocator := context.allocator) -> (i64, Error) {
	r: Reader
	init_reader(&r, allocator = allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return 0, err
	}
	return read_i64(&r, key)
}

@(require_results)
get_f64 :: proc(data: []byte, key: string, allocator := context.allocator) -> (f64, Error) {
	r: Reader
	init_reader(&r, allocator = allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return 0, err
	}
	return read_f64(&r, key)
}

@(require_results)
get_bool :: proc(data: []byte, key: string, allocator := context.allocator) -> (bool, Error) {
	r: Reader
	init_reader(&r, allocator = allocator)
	defer destroy(&r)
	if err := parse(&r, data); err != .OK {
		return false, err
	}

	return read_bool(&r, key)
}

@(require_results)
root_element :: proc(r: ^Reader) -> Element {
	return make_element(r, r.parser.root)
}

@(require_results)
element_at :: proc(r: ^Reader, path: string) -> (Element, Error) {
	if !reader_ready(r) {
		return 0, .Not_Parsed
	}

	if len(path) == 0 {
		return make_element(r, r.parser.root), .OK
	}

	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, path)
	if !found {
		return 0, .Key_Not_Found
	}

	return make_element(r, idx), .OK
}

@(require_results)
array_elements :: proc(r: ^Reader, path: string) -> ([]Element, Error) {
	if !reader_ready(r) {
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

	return collect_array_elements(r, idx, val.data.container.count), .OK
}

@(require_results)
array_element :: proc(r: ^Reader, path: string, index: int) -> (Element, Error) {
	if !reader_ready(r) {
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

	if index < 0 || index >= int(val.data.container.count) {
		return 0, .Key_Not_Found
	}

	elem_idx, elem_found := array_get_idx(&r.parser, idx, index)
	if !elem_found {
		return 0, .Key_Not_Found
	}

	return make_element(r, elem_idx), .OK
}

@(require_results)
obj_element :: proc(r: ^Reader, path: string, key: string) -> (Element, Error) {
	if !reader_ready(r) {
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

	return make_element(r, elem_idx), .OK
}

@(require_results)
obj_element_from :: proc(r: ^Reader, elem: Element, key: string) -> (Element, Error) {
	if !reader_ready(r) {
		return 0, .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
	if val.type != .Object {
		return 0, .Type_Mismatch
	}

	elem_idx, found := object_get_idx(&r.parser, element_index(r, elem), key)
	if !found {
		return 0, .Key_Not_Found
	}

	return make_element(r, elem_idx), .OK
}

@(require_results)
array_element_from :: proc(r: ^Reader, elem: Element, index: int) -> (Element, Error) {
	if !reader_ready(r) {
		return 0, .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
	if val.type != .Array {
		return 0, .Type_Mismatch
	}

	if index < 0 || index >= int(val.data.container.count) {
		return 0, .Key_Not_Found
	}

	elem_idx, found := array_get_idx(&r.parser, element_index(r, elem), index)
	if !found {
		return 0, .Key_Not_Found
	}

	return make_element(r, elem_idx), .OK
}

@(require_results)
array_elements_from :: proc(r: ^Reader, elem: Element) -> ([]Element, Error) {
	if !reader_ready(r) {
		return nil, .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
	if val.type != .Array {
		return nil, .Type_Mismatch
	}

	return collect_array_elements(r, element_index(r, elem), val.data.container.count), .OK
}

collect_array_elements :: proc(r: ^Reader, arr_idx: u32, count: u32) -> []Element {
	if count == 0 {
		return nil
	}

	result := scratch_make(r, Element, int(count))
	i: u32 = 0
	for &entry in array_entries(&r.parser, arr_idx) {
		if entry.owner_idx == arr_idx {
			result[i] = make_element(r, entry.value_idx)
			i += 1
			if i >= count {
				break
			}
		}
	}

	return result
}

@(require_results)
read_string_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: string, err: Error) {
	if !reader_ready(r) {
		return "", .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, element_index(r, elem), field)
	if !found {
		return "", .Key_Not_Found
	}

	#partial switch val.type {
	case .String:
		return val.data.str, .OK
	case .Raw_String:
		return unescape_string(r, val.data.str), .OK
	}

	return "", .Type_Mismatch
}

@(require_results)
read_string_prefix_elem :: proc(
	r: ^Reader,
	elem: Element,
	field: string,
	limit: int,
) -> (
	value: string,
	err: Error,
) {
	if !reader_ready(r) {
		return "", .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, element_index(r, elem), field)
	if !found {
		return "", .Key_Not_Found
	}

	#partial switch val.type {
	case .String, .Raw_String:
		return unescape_string_prefix(r, val.data.str, limit), .OK
	}

	return "", .Type_Mismatch
}

@(require_results)
read_int_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: int, err: Error) {
	i, e := read_i64_elem(r, elem, field)
	return int(i), e
}

@(require_results)
read_i64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: i64, err: Error) {
	if !reader_ready(r) {
		return 0, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, element_index(r, elem), field)
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

@(require_results)
read_f64_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: f64, err: Error) {
	if !reader_ready(r) {
		return 0, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, element_index(r, elem), field)
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

@(require_results)
read_bool_elem :: proc(r: ^Reader, elem: Element, field: string) -> (value: bool, err: Error) {
	if !reader_ready(r) {
		return false, .Not_Parsed
	}

	val, found := get_by_path_from(&r.parser, element_index(r, elem), field)
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

@(require_results)
read_string_value :: proc(r: ^Reader, elem: Element) -> (value: string, err: Error) {
	if !reader_ready(r) {
		return "", .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
	#partial switch val.type {
	case .String:
		return val.data.str, .OK
	case .Raw_String:
		return unescape_string(r, val.data.str), .OK
	}

	return "", .Type_Mismatch
}

@(require_results)
read_string_prefix_value :: proc(
	r: ^Reader,
	elem: Element,
	limit: int,
) -> (
	value: string,
	err: Error,
) {
	if !reader_ready(r) {
		return "", .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
	#partial switch val.type {
	case .String, .Raw_String:
		return unescape_string_prefix(r, val.data.str, limit), .OK
	}

	return "", .Type_Mismatch
}

@(require_results)
read_int_value :: proc(r: ^Reader, elem: Element) -> (value: int, err: Error) {
	i, e := read_i64_value(r, elem)
	return int(i), e
}

@(require_results)
read_i64_value :: proc(r: ^Reader, elem: Element) -> (value: i64, err: Error) {
	if !reader_ready(r) {
		return 0, .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
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

@(require_results)
read_f64_value :: proc(r: ^Reader, elem: Element) -> (value: f64, err: Error) {
	if !reader_ready(r) {
		return 0, .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
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

@(require_results)
read_bool_value :: proc(r: ^Reader, elem: Element) -> (value: bool, err: Error) {
	if !reader_ready(r) {
		return false, .Not_Parsed
	}

	val := r.parser.values[element_index(r, elem)]
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

@(require_results)
read_raw :: proc(r: ^Reader, path: string) -> (string, Error) {
	if !reader_ready(r) {
		return "", .Not_Parsed
	}
	idx, found := get_idx_by_path_from(&r.parser, r.parser.root, path)
	if !found {
		return "", .Key_Not_Found
	}
	return extract_raw_value(&r.parser, idx)
}

@(require_results)
read_raw_elem :: proc(r: ^Reader, elem: Element, field: string) -> (string, Error) {
	if !reader_ready(r) {
		return "", .Not_Parsed
	}
	idx, found := get_idx_by_path_from(&r.parser, element_index(r, elem), field)
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
		end := start + len(val.data.str) + 2
		if end > len(input) {
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

@(require_results)
element_value_type :: proc(r: ^Reader, elem: Element) -> Value_Type {
	return r.parser.values[element_index(r, elem)].type
}

@(require_results)
array_iter :: proc(r: ^Reader, elem: Element) -> Array_Iterator {
	idx := element_index(r, elem)
	if idx >= r.parser.values_len {
		return {}
	}
	val := r.parser.values[idx]
	if val.type != .Array {
		return {}
	}
	return Array_Iterator {
		r = r,
		arr_idx = idx,
		pos = val.data.container.entries_begin,
		end = val.data.container.entries_end,
	}
}

@(require_results)
array_iter_at :: proc(r: ^Reader, path: string) -> (Array_Iterator, Error) {
	elem, err := element_at(r, path)
	if err != .OK {
		return {}, err
	}
	if element_value_type(r, elem) != .Array {
		return {}, .Type_Mismatch
	}
	return array_iter(r, elem), .OK
}

@(require_results)
next_element :: proc(it: ^Array_Iterator) -> (elem: Element, ok: bool) {
	for it.pos < it.end {
		entry := it.r.parser.arr_buffer[it.pos]
		it.pos += 1
		if entry.owner_idx == it.arr_idx {
			return make_element(it.r, entry.value_idx), true
		}
	}
	return 0, false
}

@(require_results)
object_iter :: proc(r: ^Reader, elem: Element) -> Object_Iterator {
	begin, end := object_member_range(&r.parser, element_index(r, elem))
	return Object_Iterator{r = r, pos = begin, end = end}
}

@(require_results)
object_iter_at :: proc(r: ^Reader, path: string) -> (Object_Iterator, Error) {
	elem, err := element_at(r, path)
	if err != .OK {
		return {}, err
	}
	if element_value_type(r, elem) != .Object {
		return {}, .Type_Mismatch
	}
	return object_iter(r, elem), .OK
}

@(require_results)
next_pair :: proc(it: ^Object_Iterator) -> (key: string, value: Element, ok: bool) {
	if it.pos >= it.end {
		return "", 0, false
	}
	k := kv_key(&it.r.parser, it.pos)
	v := it.r.parser.kv_vals[it.pos]
	it.pos += 1
	return k, make_element(it.r, v), true
}

@(require_results)
object_keys :: proc(r: ^Reader, elem: Element) -> []string {
	val := r.parser.values[element_index(r, elem)]
	if val.type != .Object {
		return nil
	}
	begin, end := object_member_range(&r.parser, element_index(r, elem))
	if begin == end {
		return nil
	}
	result := scratch_make(r, string, int(end - begin))
	for i in begin ..< end {
		result[i - begin] = kv_key(&r.parser, i)
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

get_idx_by_path_from :: #force_inline proc(p: ^Parser_State, start_idx: u32, path: string) -> (u32, bool) {
	if p.values_len == 0 {
		return 0, false
	}
	if path == "" {
		return start_idx, true
	}

	current_idx := start_idx
	remaining := path

	for remaining != "" {
		current := p.values[current_idx]

		#partial switch current.type {
		case .Array:
			if idx, ok := parse_array_idx(remaining); ok {
				return array_get_idx(p, current_idx, idx)
			}
			dot_idx := strings.index_byte(remaining, '.')
			if dot_idx < 0 {
				return 0, false
			}
			idx, ok := parse_array_idx(remaining[:dot_idx])
			if !ok {
				return 0, false
			}
			next_idx, found := array_get_idx(p, current_idx, idx)
			if !found {
				return 0, false
			}
			current_idx = next_idx
			remaining = remaining[dot_idx + 1:]
		case .Object:
			if next_idx, found := object_get_idx(p, current_idx, remaining); found {
				return next_idx, true
			}
			dot_idx := strings.index_byte(remaining, '.')
			if dot_idx < 0 {
				return 0, false
			}
			next_idx, found := object_get_idx(p, current_idx, remaining[:dot_idx])
			if !found {
				return 0, false
			}
			current_idx = next_idx
			remaining = remaining[dot_idx + 1:]
		case:
			return 0, false
		}
	}

	return current_idx, true
}
