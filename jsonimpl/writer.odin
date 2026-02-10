package jsonimpl

import "core:bytes"
import stdjson "core:encoding/json"
import "core:unicode/utf8"

// TODO

init_writer :: proc(
	buffer_size := DEFAULT_WRITE_BUFFER_SIZE,
	allocator := context.allocator,
) -> Writer {
	w: Writer
	w.allocator = allocator
	bytes.buffer_init_allocator(&w.buffer, 0, buffer_size, allocator)
	return w
}

marshal_to :: proc(w: ^Writer, value: any, pretty := false) -> (result: []byte, err: Error) {
	bytes.buffer_reset(&w.buffer)

	opts := stdjson.Marshal_Options {
		pretty = pretty,
	}

	stream := bytes.buffer_to_stream(&w.buffer)
	marsh_err := stdjson.marshal_to_writer(stream, value, &opts)
	if marsh_err != nil {
		return nil, .Invalid_JSON
	}

	return bytes.buffer_to_bytes(&w.buffer), .OK
}

destroy_writer :: proc(w: ^Writer) {
	bytes.buffer_destroy(&w.buffer)
}

pretty_print :: proc(data: []byte, allocator := context.allocator) -> (string, Error) {
	parsed, parse_err := stdjson.parse(data, allocator = allocator)
	if parse_err != nil {
		return "", .Invalid_JSON
	}
	defer stdjson.destroy_value(parsed, allocator)

	opts := stdjson.Marshal_Options {
		pretty = true,
	}
	result, marshal_err := stdjson.marshal(parsed, opts, allocator)
	if marshal_err != nil {
		return "", .Invalid_JSON
	}
	return string(result), .OK
}

@(private)
write_sep :: proc(w: ^Writer) {
	if w.needs_sep[w.depth] {
		bytes.buffer_write_byte(&w.buffer, ',')
	}
	w.needs_sep[w.depth] = true
}

write_object_start :: proc(w: ^Writer) {
	write_sep(w)
	bytes.buffer_write_byte(&w.buffer, '{')
	w.depth += 1
	w.needs_sep[w.depth] = false
}

write_object_end :: proc(w: ^Writer) {
	w.depth -= 1
	bytes.buffer_write_byte(&w.buffer, '}')
}

write_array_start :: proc(w: ^Writer) {
	write_sep(w)
	bytes.buffer_write_byte(&w.buffer, '[')
	w.depth += 1
	w.needs_sep[w.depth] = false
}

write_array_end :: proc(w: ^Writer) {
	w.depth -= 1
	bytes.buffer_write_byte(&w.buffer, ']')
}

write_key :: proc(w: ^Writer, k: string) {
	write_sep(w)
	bytes.buffer_write_byte(&w.buffer, '"')
	write_escaped(w, k)
	bytes.buffer_write_byte(&w.buffer, '"')
	bytes.buffer_write_byte(&w.buffer, ':')
	w.needs_sep[w.depth] = false
}

write_string :: proc(w: ^Writer, s: string) {
	write_sep(w)
	bytes.buffer_write_byte(&w.buffer, '"')
	write_escaped(w, s)
	bytes.buffer_write_byte(&w.buffer, '"')
}

write_int :: proc(w: ^Writer, v: int) {
	write_sep(w)
	buf: [20]byte
	n := int_to_buf(buf[:], v)
	bytes.buffer_write(&w.buffer, buf[:n])
}

write_f32 :: proc(w: ^Writer, v: f32) {
	write_sep(w)
	integer := int(v)
	frac := int((v - f32(integer)) * 10)
	if frac < 0 {
		frac = -frac
	}
	buf: [20]byte
	n := int_to_buf(buf[:], integer)
	bytes.buffer_write(&w.buffer, buf[:n])
	bytes.buffer_write_byte(&w.buffer, '.')
	n2 := int_to_buf(buf[:], frac)
	bytes.buffer_write(&w.buffer, buf[:n2])
}

write_bool :: proc(w: ^Writer, v: bool) {
	write_sep(w)
	if v {
		bytes.buffer_write_string(&w.buffer, "true")
	} else {
		bytes.buffer_write_string(&w.buffer, "false")
	}
}

write_null :: proc(w: ^Writer) {
	write_sep(w)
	bytes.buffer_write_string(&w.buffer, "null")
}

write_raw :: proc(w: ^Writer, json: string) {
	write_sep(w)
	bytes.buffer_write_string(&w.buffer, json)
}

writer_reset :: proc(w: ^Writer) {
	bytes.buffer_reset(&w.buffer)
	w.depth = 0
	w.needs_sep[0] = false
}

writer_string :: proc(w: ^Writer) -> string {
	return bytes.buffer_to_string(&w.buffer)
}

@(private)
write_escaped :: proc(w: ^Writer, s: string) {
	for ch in s {
		switch ch {
		case '"':
			bytes.buffer_write_string(&w.buffer, `\"`)
		case '\\':
			bytes.buffer_write_string(&w.buffer, `\\`)
		case '\n':
			bytes.buffer_write_string(&w.buffer, `\n`)
		case '\r':
			bytes.buffer_write_string(&w.buffer, `\r`)
		case '\t':
			bytes.buffer_write_string(&w.buffer, `\t`)
		case:
			if ch < 0x20 {
				// skip control chars
			} else {
				encoded, width := utf8.encode_rune(ch)
				bytes.buffer_write(&w.buffer, encoded[:width])
			}
		}
	}
}

@(private)
int_to_buf :: proc(buf: []byte, val: int) -> int {
	if val == 0 {
		buf[0] = '0'
		return 1
	}

	v := val
	neg := false
	if v < 0 {
		neg = true
		v = -v
	}

	i := len(buf)
	for v > 0 {
		i -= 1
		buf[i] = byte('0' + v % 10)
		v /= 10
	}
	if neg {
		i -= 1
		buf[i] = '-'
	}

	n := len(buf) - i
	if i > 0 {
		for j := 0; j < n; j += 1 {
			buf[j] = buf[i + j]
		}
	}
	return n
}
