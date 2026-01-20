package jsonimpl

// TODO

import "core:bytes"
import stdjson "core:encoding/json"

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
