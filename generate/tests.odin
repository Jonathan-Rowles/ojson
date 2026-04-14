package generate

import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strings"
import "core:testing"

@(init)
ensure_tokenizer_init :: proc "contextless" () {
	context = {}
	t: tokenizer.Tokenizer
	tokenizer.init(&t, " ", "")
}

@(test)
test_parse_json_tag_simple :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `json:"name"`

	name, omitempty, _, _, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "name")
	testing.expect(t, !omitempty, "should not have omitempty")
}

@(test)
test_parse_json_tag_with_backticks :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = "`json:\"field_name\"`"

	name, _, _, _, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "field_name")
}

@(test)
test_parse_json_tag_with_omitempty :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `json:"value,omitempty"`

	name, omitempty, _, _, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "value")
	testing.expect(t, omitempty, "should have omitempty")
}

@(test)
test_parse_json_tag_without_omitempty :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `json:"value"`

	_, omitempty, _, _, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect(t, !omitempty, "should not have omitempty")
}

@(test)
test_parse_json_tag_no_json :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `xml:"data"`

	_, _, _, _, ok := parse_json_tag(tag)
	testing.expect(t, !ok, "expected no json tag")
}

@(test)
test_parse_json_tag_empty :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = ""

	_, _, _, _, ok := parse_json_tag(tag)
	testing.expect(t, !ok, "expected no json tag")
}

@(test)
test_parse_json_tag_with_raw :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `json:"value,raw"`

	name, _, raw, _, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "value")
	testing.expect(t, raw, "should have raw")
}

@(test)
test_parse_json_tag_raw_and_omitempty :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `json:"input,omitempty,raw"`

	name, omitempty, raw, _, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "input")
	testing.expect(t, omitempty, "should have omitempty")
	testing.expect(t, raw, "should have raw")
}

@(test)
test_type_from_ident :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 4096))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	Test_Case :: struct {
		input:         string,
		expected_kind: Type_Kind,
		expected_name: string,
	}

	cases := []Test_Case {
		{"string", .String, "string"},
		{"int", .Int, "int"},
		{"i8", .I8, "i8"},
		{"i16", .I16, "i16"},
		{"i32", .I32, "i32"},
		{"i64", .I64, "i64"},
		{"uint", .Uint, "uint"},
		{"u8", .U8, "u8"},
		{"u16", .U16, "u16"},
		{"u32", .U32, "u32"},
		{"u64", .U64, "u64"},
		{"f32", .F32, "f32"},
		{"f64", .F64, "f64"},
		{"bool", .Bool, "bool"},
		{"User", .Struct, "User"},
	}

	for tc in cases {
		kind, name, _ := type_from_ident(tc.input, alloc)
		testing.expect_value(t, kind, tc.expected_kind)
		testing.expect_value(t, name, tc.expected_name)
	}
}

@(test)
test_to_snake_case_simple :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 1024))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	result := to_snake_case("User", alloc)
	testing.expect_value(t, result, "user")
}

@(test)
test_to_snake_case_multi_word :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 1024))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	result := to_snake_case("UserProfile", alloc)
	testing.expect_value(t, result, "user_profile")
}

@(test)
test_to_snake_case_all_caps :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 1024))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	result := to_snake_case("API", alloc)
	testing.expect_value(t, result, "api")
}

@(test)
test_to_snake_case_no_double_underscore :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 1024))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	testing.expect_value(
		t,
		to_snake_case("Anthropic_Content_Block", alloc),
		"anthropic_content_block",
	)
	testing.expect_value(t, to_snake_case("OpenAI_Request", alloc), "open_ai_request")
}

@(test)
test_to_snake_case_empty :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 1024))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	result := to_snake_case("", alloc)
	testing.expect_value(t, result, "")
}

@(test)
test_to_snake_case_lowercase :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 1024))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	result := to_snake_case("user", alloc)
	testing.expect_value(t, result, "user")
}

@(test)
test_is_integer_type_true :: proc(t: ^testing.T) {
	testing.expect(t, is_integer_type("int"), "int should be integer")
	testing.expect(t, is_integer_type("i8"), "i8 should be integer")
	testing.expect(t, is_integer_type("i16"), "i16 should be integer")
	testing.expect(t, is_integer_type("i32"), "i32 should be integer")
	testing.expect(t, is_integer_type("i64"), "i64 should be integer")
	testing.expect(t, is_integer_type("u8"), "u8 should be integer")
	testing.expect(t, is_integer_type("u16"), "u16 should be integer")
	testing.expect(t, is_integer_type("u32"), "u32 should be integer")
	testing.expect(t, is_integer_type("u64"), "u64 should be integer")
	testing.expect(t, is_integer_type("uint"), "uint should be integer")
}

@(test)
test_is_integer_type_false :: proc(t: ^testing.T) {
	testing.expect(t, !is_integer_type("string"), "string should not be integer")
	testing.expect(t, !is_integer_type("bool"), "bool should not be integer")
	testing.expect(t, !is_integer_type("f32"), "f32 should not be integer")
	testing.expect(t, !is_integer_type("f64"), "f64 should not be integer")
}

@(test)
test_is_float_type_true :: proc(t: ^testing.T) {
	testing.expect(t, is_float_type("f16"), "f16 should be float")
	testing.expect(t, is_float_type("f32"), "f32 should be float")
	testing.expect(t, is_float_type("f64"), "f64 should be float")
}

@(test)
test_is_float_type_false :: proc(t: ^testing.T) {
	testing.expect(t, !is_float_type("string"), "string should not be float")
	testing.expect(t, !is_float_type("int"), "int should not be float")
	testing.expect(t, !is_float_type("bool"), "bool should not be float")
}

@(test)
test_generate_simple_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "User",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "name",
			json_name = "name",
			type_kind = .String,
			type_name = "string",
		},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "age", json_name = "age", type_kind = .Int, type_name = "int"},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "unmarshal_user"), "should contain unmarshal_user")
	testing.expect(t, strings.contains(code, "read_string"), "should contain read_string")
	testing.expect(t, strings.contains(code, "read_int"), "should contain read_int")
}

@(test)
test_generate_raw_field :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Tool_Use",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "input",
			json_name = "input",
			type_kind = .String,
			type_name = "string",
			raw = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "read_raw_elem"),
		"raw field should read via read_raw_elem",
	)
	testing.expect(
		t,
		strings.contains(code, "write_raw(w, value.input)"),
		"raw field should write via write_raw",
	)
	testing.expect(
		t,
		!strings.contains(code, "read_string_elem(r, elem, \"input\")"),
		"raw field should not use read_string_elem",
	)
	testing.expect(
		t,
		!strings.contains(code, "write_string(w, value.input)"),
		"raw field should not use write_string",
	)
}

@(test)
test_generate_raw_field_omitempty :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Tool",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "cache_control",
			json_name = "cache_control",
			type_kind = .String,
			type_name = "string",
			raw = true,
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, `if value.cache_control != ""`),
		"omitempty check on raw string",
	)
	testing.expect(
		t,
		strings.contains(code, "write_raw(w, value.cache_control)"),
		"raw write guarded by omitempty",
	)
}

@(test)
test_generate_nested_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Order",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "user",
			json_name = "user",
			type_kind = .Struct,
			type_name = "User",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "unmarshal_user"),
		"should contain unmarshal_user call",
	)
}

@(test)
test_generate_integer_cast :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info{odin_name = "count", json_name = "count", type_kind = .U32, type_name = "u32"},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "u32(val)"), "should contain u32 cast")
	testing.expect(t, strings.contains(code, "read_i64"), "should read as i64")
}

@(test)
test_generate_float_cast :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info{odin_name = "value", json_name = "value", type_kind = .F32, type_name = "f32"},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "f32(val)"), "should contain f32 cast")
	testing.expect(t, strings.contains(code, "read_f64"), "should read as f64")
}

@(test)
test_generate_array_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Group",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "users",
			json_name = "users",
			type_kind = .Array_Struct,
			type_name = "slice",
			element_type = "User",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "array_elements_from"), "should get array elements")
	testing.expect(t, strings.contains(code, "make([]User"), "should make User slice")
	testing.expect(t, strings.contains(code, "unmarshal_user"), "should call unmarshal_user")
}

@(test)
test_generate_array_primitive :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "values",
			json_name = "values",
			type_kind = .Array_Primitive,
			type_name = "slice",
			element_type = "int",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "array_elements_from"), "should get array elements")
	testing.expect(t, strings.contains(code, "make([]int"), "should make int slice")
	testing.expect(t, strings.contains(code, "read_int"), "should read int elements")
}

@(test)
test_parse_simple_struct_source :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 32768))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source :=
		`package test

User :: struct {
	name: string ` +
		"`json:\"name\"`" +
		`,
	age:  int    ` +
		"`json:\"age\"`" +
		`,
}
`


	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	structs := make([dynamic]Struct_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			unions := make([dynamic]Union_Info, alloc)
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	testing.expect_value(t, len(structs), 1)
	testing.expect_value(t, structs[0].name, "User")
	testing.expect_value(t, len(structs[0].fields), 2)
	testing.expect_value(t, structs[0].fields[0].odin_name, "name")
	testing.expect_value(t, structs[0].fields[0].json_name, "name")
	testing.expect_value(t, structs[0].fields[0].type_kind, Type_Kind.String)
	testing.expect_value(t, structs[0].fields[1].odin_name, "age")
	testing.expect_value(t, structs[0].fields[1].json_name, "age")
	testing.expect_value(t, structs[0].fields[1].type_kind, Type_Kind.Int)
}

@(test)
test_parse_struct_without_tags :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 32768))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source := `package test

User :: struct {
	name: string,
	age:  int,
}
`


	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	structs := make([dynamic]Struct_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			unions := make([dynamic]Union_Info, alloc)
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	testing.expect_value(t, len(structs), 0)
}

@(test)
test_parse_nested_struct_source :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 65536))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source :=
		`package test

Address :: struct {
	street: string ` +
		"`json:\"street\"`" +
		`,
	city:   string ` +
		"`json:\"city\"`" +
		`,
}

Person :: struct {
	name:    string  ` +
		"`json:\"name\"`" +
		`,
	address: Address ` +
		"`json:\"address\"`" +
		`,
}
`


	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	structs := make([dynamic]Struct_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			unions := make([dynamic]Union_Info, alloc)
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	testing.expect_value(t, len(structs), 2)

	person_idx := -1
	for info, i in structs {
		if info.name == "Person" {
			person_idx = i
			break
		}
	}
	testing.expect(t, person_idx >= 0, "should find Person struct")

	person := structs[person_idx]
	testing.expect_value(t, len(person.fields), 2)

	address_field_idx := -1
	for field, i in person.fields {
		if field.odin_name == "address" {
			address_field_idx = i
			break
		}
	}
	testing.expect(t, address_field_idx >= 0, "should find address field")
	testing.expect_value(t, person.fields[address_field_idx].type_kind, Type_Kind.Struct)
	testing.expect_value(t, person.fields[address_field_idx].type_name, "Address")
}

@(test)
test_parse_array_field :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 32768))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source := `package test

Group :: struct {
	names: []string ` + "`json:\"names\"`" + `,
}
`


	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	structs := make([dynamic]Struct_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			unions := make([dynamic]Union_Info, alloc)
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	testing.expect_value(t, len(structs), 1)
	testing.expect_value(t, len(structs[0].fields), 1)
	testing.expect_value(t, structs[0].fields[0].type_kind, Type_Kind.Array_Primitive)
	testing.expect_value(t, structs[0].fields[0].element_type, "string")
}

@(test)
test_parse_dynamic_array_field :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 32768))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source := `package test

Group :: struct {
	items: [dynamic]int ` + "`json:\"items\"`" + `,
}
`

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	structs := make([dynamic]Struct_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			unions := make([dynamic]Union_Info, alloc)
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	testing.expect_value(t, len(structs), 1)
	testing.expect_value(t, len(structs[0].fields), 1)
	testing.expect_value(t, structs[0].fields[0].type_kind, Type_Kind.Dynamic_Primitive)
	testing.expect_value(t, structs[0].fields[0].element_type, "int")
}

@(test)
test_parse_fixed_array_with_named_constant :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 65536))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	g_constants = make(map[string]int, allocator = alloc)

	source :=
		`package test

MAX_PLAYERS :: 2

Player_State :: struct {
	score: int ` +
		"`json:\"score\"`" +
		`,
}

Round_End_Data :: struct {
	winner_id: int                        ` +
		"`json:\"winner_id\"`" +
		`,
	players:   [MAX_PLAYERS]Player_State  ` +
		"`json:\"players\"`" +
		`,
}
`

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	collect_constants(file.decls[:])

	structs := make([dynamic]Struct_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			unions := make([dynamic]Union_Info, alloc)
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	round_idx := -1
	for info, i in structs {
		if info.name == "Round_End_Data" {
			round_idx = i
			break
		}
	}
	testing.expect(t, round_idx >= 0, "should find Round_End_Data struct")

	round := structs[round_idx]
	players_idx := -1
	for field, i in round.fields {
		if field.odin_name == "players" {
			players_idx = i
			break
		}
	}
	testing.expect(t, players_idx >= 0, "should find players field")

	players := round.fields[players_idx]
	testing.expect_value(t, players.type_kind, Type_Kind.Fixed_Array_Struct)
	testing.expect_value(t, players.array_size, 2)
	testing.expect_value(t, players.element_type, "Player_State")
}

@(test)
test_marshal_simple_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "User",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "name",
			json_name = "name",
			type_kind = .String,
			type_name = "string",
		},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "age", json_name = "age", type_kind = .Int, type_name = "int"},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "marshal_user"), "should contain marshal_user")
	testing.expect(t, strings.contains(code, "write_object_start"), "should start object")
	testing.expect(t, strings.contains(code, "write_object_end"), "should end object")
	testing.expect(t, strings.contains(code, `write_key(w, "name")`), "should write name key")
	testing.expect(
		t,
		strings.contains(code, "write_string(w, value.name)"),
		"should write string field",
	)
	testing.expect(t, strings.contains(code, `write_key(w, "age")`), "should write age key")
	testing.expect(t, strings.contains(code, "write_int(w, value.age)"), "should write int field")
}

@(test)
test_marshal_nested_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Order",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info{odin_name = "id", json_name = "id", type_kind = .Int, type_name = "int"},
	)
	append(
		&info.fields,
		Field_Info {
			odin_name = "user",
			json_name = "user",
			type_kind = .Struct,
			type_name = "User",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "marshal_order"), "should contain marshal_order")
	testing.expect(t, strings.contains(code, `write_key(w, "user")`), "should write user key")
	testing.expect(
		t,
		strings.contains(code, "marshal_user(w, value.user)"),
		"should call nested marshal",
	)
}

@(test)
test_marshal_integer_cast_types :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 16384))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "IntTypes",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info{odin_name = "a", json_name = "a", type_kind = .I8, type_name = "i8"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "b", json_name = "b", type_kind = .I16, type_name = "i16"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "c", json_name = "c", type_kind = .I32, type_name = "i32"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "d", json_name = "d", type_kind = .I64, type_name = "i64"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "e", json_name = "e", type_kind = .U8, type_name = "u8"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "f", json_name = "f", type_kind = .U16, type_name = "u16"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "g", json_name = "g", type_kind = .U32, type_name = "u32"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "h", json_name = "h", type_kind = .U64, type_name = "u64"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "i", json_name = "i", type_kind = .Uint, type_name = "uint"},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.a))"),
		"should cast i8 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.b))"),
		"should cast i16 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.c))"),
		"should cast i32 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.d))"),
		"should cast i64 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.e))"),
		"should cast u8 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.f))"),
		"should cast u16 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.g))"),
		"should cast u32 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.h))"),
		"should cast u64 to int",
	)
	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.i))"),
		"should cast uint to int",
	)
}

@(test)
test_marshal_float_types :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "FloatTypes",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info{odin_name = "a", json_name = "a", type_kind = .F16, type_name = "f16"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "b", json_name = "b", type_kind = .F32, type_name = "f32"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "c", json_name = "c", type_kind = .F64, type_name = "f64"},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "write_f32(w, f32(value.a))"),
		"should cast f16 to f32",
	)
	testing.expect(t, strings.contains(code, "write_f32(w, value.b)"), "should write f32 directly")
	testing.expect(t, strings.contains(code, "write_f64(w, value.c)"), "should write f64")
}

@(test)
test_marshal_bool :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Flags",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "active",
			json_name = "active",
			type_kind = .Bool,
			type_name = "bool",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "write_bool(w, value.active)"),
		"should write bool field",
	)
}

@(test)
test_marshal_enum :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "status",
			json_name = "status",
			type_kind = .Enum,
			type_name = "Status",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.status))"),
		"should cast enum to int",
	)
}

@(test)
test_marshal_distinct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "id",
			json_name = "id",
			type_kind = .Distinct,
			type_name = "Entity_ID",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(value.id))"),
		"should cast distinct to int",
	)
}

@(test)
test_marshal_array_primitive :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "values",
			json_name = "values",
			type_kind = .Array_Primitive,
			type_name = "slice",
			element_type = "int",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, `write_key(w, "values")`), "should write key")
	testing.expect(t, strings.contains(code, "write_array_start"), "should start array")
	testing.expect(t, strings.contains(code, "write_array_end"), "should end array")
	testing.expect(t, strings.contains(code, "for item in value.values"), "should iterate slice")
	testing.expect(t, strings.contains(code, "write_int(w, item)"), "should write int elements")
}

@(test)
test_marshal_array_string :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "tags",
			json_name = "tags",
			type_kind = .Array_Primitive,
			type_name = "slice",
			element_type = "string",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "write_string(w, item)"),
		"should write string elements",
	)
}

@(test)
test_marshal_array_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Group",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "users",
			json_name = "users",
			type_kind = .Array_Struct,
			type_name = "slice",
			element_type = "User",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "write_array_start"), "should start array")
	testing.expect(
		t,
		strings.contains(code, "marshal_user(w, item)"),
		"should marshal each struct",
	)
	testing.expect(t, strings.contains(code, "write_array_end"), "should end array")
}

@(test)
test_marshal_dynamic_primitive :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "items",
			json_name = "items",
			type_kind = .Dynamic_Primitive,
			type_name = "dynamic",
			element_type = "f64",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "write_array_start"), "should start array")
	testing.expect(
		t,
		strings.contains(code, "for item in value.items"),
		"should iterate dynamic array",
	)
	testing.expect(t, strings.contains(code, "write_f64(w, item)"), "should write f64 elements")
	testing.expect(t, strings.contains(code, "write_array_end"), "should end array")
}

@(test)
test_marshal_dynamic_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Team",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "members",
			json_name = "members",
			type_kind = .Dynamic_Struct,
			type_name = "dynamic",
			element_type = "Player",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "for item in value.members"), "should iterate")
	testing.expect(
		t,
		strings.contains(code, "marshal_player(w, item)"),
		"should marshal each struct",
	)
}

@(test)
test_marshal_fixed_array_primitive :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "tags",
			json_name = "tags",
			type_kind = .Fixed_Array_Primitive,
			type_name = "fixed",
			element_type = "string",
			array_size = 5,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "write_array_start"), "should start array")
	testing.expect(
		t,
		strings.contains(code, "for item in value.tags"),
		"should iterate fixed array",
	)
	testing.expect(
		t,
		strings.contains(code, "write_string(w, item)"),
		"should write string elements",
	)
	testing.expect(t, strings.contains(code, "write_array_end"), "should end array")
}

@(test)
test_marshal_fixed_array_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Round",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "players",
			json_name = "players",
			type_kind = .Fixed_Array_Struct,
			type_name = "fixed",
			element_type = "Player",
			array_size = 4,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "for item in value.players"),
		"should iterate fixed array",
	)
	testing.expect(
		t,
		strings.contains(code, "marshal_player(w, item)"),
		"should marshal each struct",
	)
}

@(test)
test_marshal_array_cast_element :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "ids",
			json_name = "ids",
			type_kind = .Array_Primitive,
			type_name = "slice",
			element_type = "u32",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "write_int(w, int(item))"),
		"should cast u32 elements to int",
	)
}

@(test)
test_marshal_array_float_element :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "weights",
			json_name = "weights",
			type_kind = .Array_Primitive,
			type_name = "slice",
			element_type = "f32",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "write_f32(w, item)"), "should write f32 elements")
}

@(test)
test_marshal_different_json_name :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Config",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "max_retries",
			json_name = "maxRetries",
			type_kind = .Int,
			type_name = "int",
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, `write_key(w, "maxRetries")`),
		"should use json name for key",
	)
	testing.expect(
		t,
		strings.contains(code, "value.max_retries"),
		"should use odin name for field access",
	)
}

@(test)
test_marshal_with_ojson_prefix :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "User",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "name",
			json_name = "name",
			type_kind = .String,
			type_name = "string",
		},
	)

	code := generate_code({info}, nil, "gen", "", "../jsonimpl", alloc)

	testing.expect(t, strings.contains(code, "oj.write_object_start"), "should prefix with oj.")
	testing.expect(t, strings.contains(code, "oj.write_string"), "should prefix with oj.")
	testing.expect(t, strings.contains(code, "oj.Writer"), "should use oj.Writer type")
}

@(test)
test_marshal_all_primitives :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 16384))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "AllTypes",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info{odin_name = "s", json_name = "s", type_kind = .String, type_name = "string"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "i", json_name = "i", type_kind = .Int, type_name = "int"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "i64", json_name = "i64", type_kind = .I64, type_name = "i64"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "f32", json_name = "f32", type_kind = .F32, type_name = "f32"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "f64", json_name = "f64", type_kind = .F64, type_name = "f64"},
	)
	append(
		&info.fields,
		Field_Info{odin_name = "b", json_name = "b", type_kind = .Bool, type_name = "bool"},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "write_string(w, value.s)"), "string")
	testing.expect(t, strings.contains(code, "write_int(w, value.i)"), "int")
	testing.expect(t, strings.contains(code, "write_int(w, int(value.i64))"), "i64")
	testing.expect(t, strings.contains(code, "write_f32(w, value.f32)"), "f32")
	testing.expect(t, strings.contains(code, "write_f64(w, value.f64)"), "f64")
	testing.expect(t, strings.contains(code, "write_bool(w, value.b)"), "bool")
}


@(test)
test_marshal_omitempty_string :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "User",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "name",
			json_name = "name",
			type_kind = .String,
			type_name = "string",
		},
	)
	append(
		&info.fields,
		Field_Info {
			odin_name = "email",
			json_name = "email",
			type_kind = .String,
			type_name = "string",
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, `if value.email != ""`), "should check empty string")
	testing.expect(
		t,
		!strings.contains(code, `if value.name != ""`),
		"non-omitempty should not check",
	)
}

@(test)
test_marshal_omitempty_int :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "count",
			json_name = "count",
			type_kind = .Int,
			type_name = "int",
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "if value.count != 0"), "should check zero int")
}

@(test)
test_marshal_omitempty_bool :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Flags",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "active",
			json_name = "active",
			type_kind = .Bool,
			type_name = "bool",
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "if value.active {"), "should check false bool")
}

@(test)
test_marshal_omitempty_f64 :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "score",
			json_name = "score",
			type_kind = .F64,
			type_name = "f64",
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "if value.score != 0"), "should check zero f64")
}

@(test)
test_marshal_omitempty_slice :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "tags",
			json_name = "tags",
			type_kind = .Array_Primitive,
			type_name = "slice",
			element_type = "string",
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "if len(value.tags) > 0"), "should check empty slice")
}

@(test)
test_marshal_omitempty_enum :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "Data",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info {
			odin_name = "status",
			json_name = "status",
			type_kind = .Enum,
			type_name = "Status",
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(
		t,
		strings.contains(code, "if int(value.status) != 0"),
		"should check zero enum",
	)
}

@(test)
test_marshal_omitempty_mixed :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 8192))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	info := Struct_Info {
		name   = "User",
		fields = make([dynamic]Field_Info, alloc),
	}
	append(
		&info.fields,
		Field_Info{odin_name = "id", json_name = "id", type_kind = .Int, type_name = "int"},
	)
	append(
		&info.fields,
		Field_Info {
			odin_name = "nickname",
			json_name = "nickname",
			type_kind = .String,
			type_name = "string",
			omitempty = true,
		},
	)
	append(
		&info.fields,
		Field_Info {
			odin_name = "age",
			json_name = "age",
			type_kind = .Int,
			type_name = "int",
			omitempty = true,
		},
	)

	code := generate_code({info}, nil, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, `write_key(w, "id")`), "id always written")
	testing.expect(
		t,
		strings.contains(code, `if value.nickname != ""`),
		"nickname omitempty check",
	)
	testing.expect(t, strings.contains(code, "if value.age != 0"), "age omitempty check")
}

@(test)
test_parse_omitempty_from_source :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 32768))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source :=
		`package test

User :: struct {
	name:  string ` +
		"`json:\"name\"`" +
		`,
	email: string ` +
		"`json:\"email,omitempty\"`" +
		`,
}
`

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	structs := make([dynamic]Struct_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			unions := make([dynamic]Union_Info, alloc)
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	testing.expect_value(t, len(structs), 1)
	testing.expect_value(t, len(structs[0].fields), 2)
	testing.expect(t, !structs[0].fields[0].omitempty, "name should not be omitempty")
	testing.expect(t, structs[0].fields[1].omitempty, "email should be omitempty")
}

@(test)
test_parse_json_tag_with_union_tag :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 4096))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	tag: tokenizer.Token
	tag.text = `json:"type,tag=text"`

	name, _, _, union_tag, ok := parse_json_tag(tag, alloc)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "type")
	testing.expect_value(t, union_tag, "text")
}

@(test)
test_parse_json_tag_omitempty_and_union_tag :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 4096))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	tag: tokenizer.Token
	tag.text = `json:"kind,omitempty,tag=circle"`

	name, omitempty, _, union_tag, ok := parse_json_tag(tag, alloc)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "kind")
	testing.expect(t, omitempty, "should have omitempty")
	testing.expect_value(t, union_tag, "circle")
}

@(test)
test_parse_union_declaration :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 65536))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source :=
		`package test

Circle :: struct {
	kind:   string ` +
		"`json:\"kind,tag=circle\"`" +
		`,
	radius: f64 ` +
		"`json:\"radius\"`" +
		`,
}

Square :: struct {
	kind: string ` +
		"`json:\"kind,tag=square\"`" +
		`,
	side: f64 ` +
		"`json:\"side\"`" +
		`,
}

Shape :: union { Circle, Square }
`

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	ok := parser.parse_file(&p, file)
	testing.expect(t, ok, "should parse source")

	structs := make([dynamic]Struct_Info, alloc)
	unions := make([dynamic]Union_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	testing.expect_value(t, len(structs), 2)
	testing.expect_value(t, len(unions), 1)
	testing.expect_value(t, unions[0].name, "Shape")
	testing.expect_value(t, len(unions[0].variants), 2)

	resolve_unions(&unions, structs[:], alloc)

	testing.expect_value(t, len(unions), 1)
	testing.expect_value(t, unions[0].discriminator, "kind")
	testing.expect_value(t, unions[0].variants[0].struct_name, "Circle")
	testing.expect_value(t, unions[0].variants[0].tag, "circle")
	testing.expect_value(t, unions[0].variants[1].struct_name, "Square")
	testing.expect_value(t, unions[0].variants[1].tag, "square")
}

@(test)
test_union_discriminator_mismatch_drops_union :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 65536))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source :=
		`package test

A :: struct {
	k: string ` +
		"`json:\"type,tag=a\"`" +
		`,
}

B :: struct {
	k: string ` +
		"`json:\"kind,tag=b\"`" +
		`,
}

Mixed :: union { A, B }
`

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	parser.parse_file(&p, file)

	structs := make([dynamic]Struct_Info, alloc)
	unions := make([dynamic]Union_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	resolve_unions(&unions, structs[:], alloc)

	testing.expect_value(t, len(unions), 0)
}

@(test)
test_union_field_retagged_on_host_struct :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 65536))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source :=
		`package test

Circle :: struct {
	kind:   string ` +
		"`json:\"kind,tag=circle\"`" +
		`,
	radius: f64 ` +
		"`json:\"radius\"`" +
		`,
}

Shape :: union { Circle }

Event :: struct {
	name:     string ` +
		"`json:\"name\"`" +
		`,
	shape:    Shape   ` +
		"`json:\"shape\"`" +
		`,
	shapes:   []Shape ` +
		"`json:\"shapes\"`" +
		`,
	dyn_shapes: [dynamic]Shape ` +
		"`json:\"dyn_shapes\"`" +
		`,
}
`

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	parser.parse_file(&p, file)

	structs := make([dynamic]Struct_Info, alloc)
	unions := make([dynamic]Union_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	resolve_unions(&unions, structs[:], alloc)

	event_idx := -1
	for info, i in structs {
		if info.name == "Event" {
			event_idx = i
			break
		}
	}
	testing.expect(t, event_idx >= 0, "should find Event struct")

	event := structs[event_idx]
	testing.expect_value(t, len(event.fields), 4)

	find_field :: proc(fields: []Field_Info, name: string) -> (Field_Info, bool) {
		for f in fields {
			if f.odin_name == name {
				return f, true
			}
		}
		return {}, false
	}

	shape_field, _ := find_field(event.fields[:], "shape")
	testing.expect_value(t, shape_field.type_kind, Type_Kind.Union)

	shapes_field, _ := find_field(event.fields[:], "shapes")
	testing.expect_value(t, shapes_field.type_kind, Type_Kind.Array_Union)

	dyn_field, _ := find_field(event.fields[:], "dyn_shapes")
	testing.expect_value(t, dyn_field.type_kind, Type_Kind.Dynamic_Union)
}

@(test)
test_generate_union_emits_dispatch :: proc(t: ^testing.T) {
	arena: mem.Arena
	mem.arena_init(&arena, make([]byte, 131072))
	defer delete(arena.data)
	alloc := mem.arena_allocator(&arena)
	context.allocator = alloc

	source :=
		`package test

Circle :: struct {
	kind:   string ` +
		"`json:\"kind,tag=circle\"`" +
		`,
	radius: f64 ` +
		"`json:\"radius\"`" +
		`,
}

Square :: struct {
	kind: string ` +
		"`json:\"kind,tag=square\"`" +
		`,
	side: f64 ` +
		"`json:\"side\"`" +
		`,
}

Shape :: union { Circle, Square }
`

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = source
	file.fullpath = "test.odin"

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	parser.parse_file(&p, file)

	structs := make([dynamic]Struct_Info, alloc)
	unions := make([dynamic]Union_Info, alloc)
	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			process_value_decl(d, &structs, &unions, alloc)
		}
	}

	resolve_unions(&unions, structs[:], alloc)

	code := generate_code(structs[:], unions[:], "gen", "", "", alloc)

	testing.expect(t, strings.contains(code, "unmarshal_shape"), "should emit union unmarshal")
	testing.expect(t, strings.contains(code, "marshal_shape"), "should emit union marshal")
	testing.expect(
		t,
		strings.contains(code, `read_string_elem(r, elem, "kind")`),
		"should read discriminator",
	)
	testing.expect(t, strings.contains(code, `case "circle":`), "should switch on circle tag")
	testing.expect(t, strings.contains(code, `case "square":`), "should switch on square tag")
	testing.expect(
		t,
		strings.contains(code, `write_string(w, "circle")`),
		"marshal should emit literal tag for circle",
	)
	testing.expect(
		t,
		strings.contains(code, `write_string(w, "square")`),
		"marshal should emit literal tag for square",
	)
}
