package generate

import "core:mem"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:strings"
import "core:testing"

@(test)
test_parse_json_tag_simple :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `json:"name"`

	name, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "name")
}

@(test)
test_parse_json_tag_with_backticks :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = "`json:\"field_name\"`"

	name, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "field_name")
}

@(test)
test_parse_json_tag_with_omitempty :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `json:"value,omitempty"`

	name, ok := parse_json_tag(tag)
	testing.expect(t, ok, "expected tag to be parsed")
	testing.expect_value(t, name, "value")
}

@(test)
test_parse_json_tag_no_json :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = `xml:"data"`

	_, ok := parse_json_tag(tag)
	testing.expect(t, !ok, "expected no json tag")
}

@(test)
test_parse_json_tag_empty :: proc(t: ^testing.T) {
	tag: tokenizer.Token
	tag.text = ""

	_, ok := parse_json_tag(tag)
	testing.expect(t, !ok, "expected no json tag")
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
	testing.expect_value(t, result, "a_p_i")
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

	code := generate_code({info}, "json", "", "", alloc)

	testing.expect(t, strings.contains(code, "unmarshal_user"), "should contain unmarshal_user")
	testing.expect(t, strings.contains(code, "read_string"), "should contain read_string")
	testing.expect(t, strings.contains(code, "read_int"), "should contain read_int")
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

	code := generate_code({info}, "json", "", "", alloc)

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

	code := generate_code({info}, "json", "", "", alloc)

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

	code := generate_code({info}, "json", "", "", alloc)

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

	code := generate_code({info}, "json", "", "", alloc)

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

	code := generate_code({info}, "json", "", "", alloc)

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
			process_value_decl(d, &structs, alloc)
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
			process_value_decl(d, &structs, alloc)
		}
	}

	if len(structs) > 0 {
		testing.expect_value(t, len(structs[0].fields), 0)
	}
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
			process_value_decl(d, &structs, alloc)
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
			process_value_decl(d, &structs, alloc)
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
			process_value_decl(d, &structs, alloc)
		}
	}

	testing.expect_value(t, len(structs), 1)
	testing.expect_value(t, len(structs[0].fields), 1)
	testing.expect_value(t, structs[0].fields[0].type_kind, Type_Kind.Dynamic_Primitive)
	testing.expect_value(t, structs[0].fields[0].element_type, "int")
}
