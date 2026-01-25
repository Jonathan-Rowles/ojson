package jsonimpl

import "core:math"
import "core:strconv"
import "core:strings"

parser_parse :: proc(p: ^Parser_State, input: string) -> Error {
	p.input = input
	p.pos = 0
	p.depth = 0
	p.values_len = 0
	p.kv_len = 0
	p.arr_len = 0

	root_idx, err := parse_value(p)
	if err != .OK {
		return err
	}
	p.root = root_idx

	skip_ws(p)
	if p.pos < len(p.input) {
		return .Invalid_JSON
	}

	return .OK
}

parse_value :: proc(p: ^Parser_State) -> (u32, Error) {
	skip_ws(p)
	if p.pos >= len(p.input) {
		return 0, .Invalid_JSON
	}

	p.depth += 1
	if p.depth > MAX_DEPTH {
		return 0, .Invalid_JSON
	}
	defer p.depth -= 1

	c := p.input[p.pos]

	switch c {
	case '{':
		return parse_object(p)
	case '[':
		return parse_array(p)
	case '"':
		return parse_string(p)
	case 't':
		return parse_true(p)
	case 'f':
		return parse_false(p)
	case 'n':
		return parse_null(p)
	case '-', '0' ..= '9':
		return parse_number(p)
	}

	return 0, .Invalid_JSON
}

parse_object :: proc(p: ^Parser_State) -> (u32, Error) {
	p.pos += 1
	skip_ws(p)

	if p.pos >= len(p.input) {
		return 0, .Invalid_JSON
	}

	obj_idx := p.values_len
	assert(obj_idx < u32(len(p.values)), "values buffer overflow")
	p.values_len += 1

	if p.input[p.pos] == '}' {
		p.pos += 1
		p.values[obj_idx] = Lazy_Value {
			type = .Object,
			data = {container = 0},
		}
		return obj_idx, .OK
	}

	kv_count: u32 = 0

	for {
		if p.pos >= len(p.input) || p.input[p.pos] != '"' {
			return 0, .Invalid_JSON
		}

		key, key_err := parse_raw_key(p)
		if key_err != .OK {
			return 0, key_err
		}

		skip_ws(p)
		if p.pos >= len(p.input) || p.input[p.pos] != ':' {
			return 0, .Invalid_JSON
		}
		p.pos += 1

		value_idx, val_err := parse_value(p)
		if val_err != .OK {
			return 0, val_err
		}

		assert(p.kv_len < u32(len(p.kv_buffer)), "kv_buffer overflow")
		p.kv_buffer[p.kv_len] = KV {
			owner_idx = obj_idx,
			key       = key,
			value_idx = value_idx,
		}
		p.kv_len += 1
		kv_count += 1

		skip_ws(p)
		if p.pos >= len(p.input) {
			return 0, .Invalid_JSON
		}

		if p.input[p.pos] == '}' {
			p.pos += 1
			break
		}
		if p.input[p.pos] != ',' {
			return 0, .Invalid_JSON
		}
		p.pos += 1
		skip_ws(p)
	}

	p.values[obj_idx] = Lazy_Value {
		type = .Object,
		data = {container = kv_count},
	}
	return obj_idx, .OK
}

parse_array :: proc(p: ^Parser_State) -> (u32, Error) {
	p.pos += 1
	skip_ws(p)

	if p.pos >= len(p.input) {
		return 0, .Invalid_JSON
	}

	arr_idx := p.values_len
	assert(arr_idx < u32(len(p.values)), "values buffer overflow")
	p.values_len += 1

	if p.input[p.pos] == ']' {
		p.pos += 1
		p.values[arr_idx] = Lazy_Value {
			type = .Array,
			data = {container = 0},
		}
		return arr_idx, .OK
	}

	child_count: u32 = 0

	for {
		value_idx, err := parse_value(p)
		if err != .OK {
			return 0, err
		}

		assert(p.arr_len < u32(len(p.arr_buffer)), "arr_buffer overflow")
		p.arr_buffer[p.arr_len] = ArrEntry {
			owner_idx = arr_idx,
			value_idx = value_idx,
		}
		p.arr_len += 1
		child_count += 1

		skip_ws(p)
		if p.pos >= len(p.input) {
			return 0, .Invalid_JSON
		}

		if p.input[p.pos] == ']' {
			p.pos += 1
			break
		}
		if p.input[p.pos] != ',' {
			return 0, .Invalid_JSON
		}
		p.pos += 1
	}

	p.values[arr_idx] = Lazy_Value {
		type = .Array,
		data = {container = child_count},
	}
	return arr_idx, .OK
}

parse_string :: proc(p: ^Parser_State) -> (u32, Error) {
	p.pos += 1
	start := p.pos
	rest := p.input[start:]

	n := strings.index_byte(rest, '"')
	if n < 0 {
		return 0, .Invalid_JSON
	}

	if n == 0 || rest[n - 1] != '\\' {
		str := rest[:n]
		p.pos = start + n + 1
		has_escapes := strings.index_byte(str, '\\') >= 0
		type := Value_Type.String if !has_escapes else Value_Type.Raw_String
		return add_value(p, Lazy_Value{type = type, data = {str = str}}), .OK
	}

	for p.pos < len(p.input) {
		c := p.input[p.pos]
		if c == '"' {
			str := p.input[start:p.pos]
			p.pos += 1
			return add_value(p, Lazy_Value{type = .Raw_String, data = {str = str}}), .OK
		}
		if c == '\\' {
			p.pos += 1
			if p.pos >= len(p.input) {
				return 0, .Invalid_JSON
			}
			if p.input[p.pos] == 'u' {
				p.pos += 4
				if p.pos > len(p.input) {
					return 0, .Invalid_JSON
				}
			}
		}
		p.pos += 1
	}

	return 0, .Invalid_JSON
}

parse_raw_key :: proc(p: ^Parser_State) -> (string, Error) {
	p.pos += 1
	start := p.pos
	rest := p.input[start:]

	n := strings.index_byte(rest, '"')
	if n < 0 {
		return "", .Invalid_JSON
	}
	if n == 0 || rest[n - 1] != '\\' {
		p.pos = start + n + 1
		return rest[:n], .OK
	}

	for p.pos < len(p.input) {
		c := p.input[p.pos]
		if c == '"' {
			key := p.input[start:p.pos]
			p.pos += 1
			return key, .OK
		}
		if c == '\\' {
			p.pos += 1
			if p.pos >= len(p.input) {
				return "", .Invalid_JSON
			}
			if p.input[p.pos] == 'u' {
				p.pos += 4
				if p.pos > len(p.input) {
					return "", .Invalid_JSON
				}
			}
		}
		p.pos += 1
	}

	return "", .Invalid_JSON
}

parse_number :: proc(p: ^Parser_State) -> (u32, Error) {
	start := p.pos
	for p.pos < len(p.input) {
		c := p.input[p.pos]
		if (c >= '0' && c <= '9') || c == '.' || c == '-' || c == '+' || c == 'e' || c == 'E' {
			p.pos += 1
		} else {
			break
		}
	}
	if p.pos == start {
		return 0, .Invalid_JSON
	}
	return add_value(p, Lazy_Value{type = .Number, data = {str = p.input[start:p.pos]}}), .OK
}

parse_true :: proc(p: ^Parser_State) -> (u32, Error) {
	if p.pos + 4 > len(p.input) || p.input[p.pos:p.pos + 4] != "true" {
		return 0, .Invalid_JSON
	}
	p.pos += 4
	return add_value(p, Lazy_Value{type = .True}), .OK
}

parse_false :: proc(p: ^Parser_State) -> (u32, Error) {
	if p.pos + 5 > len(p.input) || p.input[p.pos:p.pos + 5] != "false" {
		return 0, .Invalid_JSON
	}
	p.pos += 5
	return add_value(p, Lazy_Value{type = .False}), .OK
}

parse_null :: proc(p: ^Parser_State) -> (u32, Error) {
	if p.pos + 4 > len(p.input) || p.input[p.pos:p.pos + 4] != "null" {
		return 0, .Invalid_JSON
	}
	p.pos += 4
	return add_value(p, Lazy_Value{type = .Null}), .OK
}

add_value :: #force_inline proc(p: ^Parser_State, v: Lazy_Value) -> u32 {
	idx := p.values_len
	assert(idx < u32(len(p.values)), "values buffer overflow")
	p.values[idx] = v
	p.values_len += 1
	return idx
}

skip_ws :: #force_inline proc(p: ^Parser_State) {
	for p.pos < len(p.input) {
		switch p.input[p.pos] {
		case ' ', '\n', '\t', '\r':
			p.pos += 1
		case:
			return
		}
	}
}

float64_pow10 := [17]f64 {
	1e0,
	1e1,
	1e2,
	1e3,
	1e4,
	1e5,
	1e6,
	1e7,
	1e8,
	1e9,
	1e10,
	1e11,
	1e12,
	1e13,
	1e14,
	1e15,
	1e16,
}

parse_i64_fast :: proc(s: string) -> (i64, bool) {
	if len(s) == 0 {
		return 0, false
	}

	i: uint = 0
	minus := s[0] == '-'
	if minus {
		i += 1
		if i >= uint(len(s)) {
			return 0, false
		}
	} else if s[0] == '+' {
		i += 1
		if i >= uint(len(s)) {
			return 0, false
		}
	}

	d: i64 = 0
	j := i
	for i < uint(len(s)) {
		c := s[i]
		if c >= '0' && c <= '9' {
			d = d * 10 + i64(c - '0')
			i += 1
			if i > 18 {
				val, ok := strconv.parse_i64(s)
				return val if ok else 0, ok
			}
			continue
		}
		if c == '.' || c == 'e' || c == 'E' {
			f, ok := parse_f64_fast(s)
			if ok {
				return i64(f), true
			}
			return 0, false
		}
		break
	}

	if i <= j {
		return 0, false
	}
	if i < uint(len(s)) {
		return 0, false
	}

	if minus {
		return -d, true
	}
	return d, true
}

parse_f64_fast :: proc(s: string) -> (f64, bool) {
	if len(s) == 0 {
		return 0, false
	}

	i: uint = 0
	minus := s[0] == '-'
	if minus {
		i += 1
		if i >= uint(len(s)) {
			return 0, false
		}
	} else if s[0] == '+' {
		i += 1
		if i >= uint(len(s)) {
			return 0, false
		}
	}

	d: u64 = 0
	j := i
	for i < uint(len(s)) {
		c := s[i]
		if c >= '0' && c <= '9' {
			d = d * 10 + u64(c - '0')
			i += 1
			if i > 18 {
				val, ok := strconv.parse_f64(s)
				return val if ok else 0, ok
			}
			continue
		}
		break
	}

	if i <= j && (i >= uint(len(s)) || s[i] != '.') {
		return 0, false
	}

	f := f64(d)
	if i >= uint(len(s)) {
		if minus {
			f = -f
		}
		return f, true
	}

	if s[i] == '.' {
		i += 1
		if i >= uint(len(s)) {
			if minus {
				f = -f
			}
			return f, true
		}

		k := i
		for i < uint(len(s)) {
			c := s[i]
			if c >= '0' && c <= '9' {
				d = d * 10 + u64(c - '0')
				i += 1
				if i - j >= uint(len(float64_pow10)) {
					val, ok := strconv.parse_f64(s)
					return val if ok else 0, ok
				}
				continue
			}
			break
		}

		frac_digits := i - k
		if frac_digits > 0 {
			f = f64(d) / float64_pow10[frac_digits]
		}

		if i >= uint(len(s)) {
			if minus {
				f = -f
			}
			return f, true
		}
	}

	if s[i] == 'e' || s[i] == 'E' {
		i += 1
		if i >= uint(len(s)) {
			return 0, false
		}

		exp_minus := false
		if s[i] == '+' || s[i] == '-' {
			exp_minus = s[i] == '-'
			i += 1
			if i >= uint(len(s)) {
				return 0, false
			}
		}

		exp: i16 = 0
		exp_start := i
		for i < uint(len(s)) {
			c := s[i]
			if c >= '0' && c <= '9' {
				exp = exp * 10 + i16(c - '0')
				i += 1
				if exp > 300 {
					val, ok := strconv.parse_f64(s)
					return val if ok else 0, ok
				}
				continue
			}
			break
		}

		if i <= exp_start {
			return 0, false
		}

		if exp_minus {
			exp = -exp
		}
		f *= math.pow(f64(10), f64(exp))

		if i >= uint(len(s)) {
			if minus {
				f = -f
			}
			return f, true
		}
	}

	if i < uint(len(s)) {
		return 0, false
	}

	if minus {
		f = -f
	}
	return f, true
}
