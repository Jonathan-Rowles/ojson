package generate

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:strings"

parse_file :: proc(
	file_path: string,
	allocator := context.allocator,
) -> (
	structs: [dynamic]Struct_Info,
	ok: bool,
) {
	structs = make([dynamic]Struct_Info, allocator)

	data, read_ok := os.read_entire_file(file_path, allocator)
	if !read_ok {
		return structs, false
	}

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = string(data)
	file.fullpath = file_path

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	if !parser.parse_file(&p, file) {
		return structs, false
	}

	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			process_value_decl(d, &structs, allocator)
		}
	}

	return structs, true
}

process_value_decl :: proc(
	decl: ^ast.Value_Decl,
	structs: ^[dynamic]Struct_Info,
	allocator := context.allocator,
) {
	if len(decl.names) == 0 || len(decl.values) == 0 {
		return
	}

	name_node := decl.names[0]
	#partial switch n in name_node.derived {
	case ^ast.Ident:
		value_node := decl.values[0]
		#partial switch v in value_node.derived {
		case ^ast.Struct_Type:
			struct_info := extract_struct_info(n.name, v, allocator)
			if struct_info != nil && len(struct_info.fields) > 0 {
				append(structs, struct_info^)
			}
		}
	}
}

extract_struct_info :: proc(
	name: string,
	struct_type: ^ast.Struct_Type,
	allocator := context.allocator,
) -> ^Struct_Info {
	info := new(Struct_Info, allocator)
	info.name = strings.clone(name, allocator)
	info.fields = make([dynamic]Field_Info, allocator)

	if struct_type.fields == nil || struct_type.fields.list == nil {
		return info
	}

	for field in struct_type.fields.list {
		process_field(field, &info.fields, allocator)
	}

	return info
}

process_field :: proc(
	field: ^ast.Field,
	fields: ^[dynamic]Field_Info,
	allocator := context.allocator,
) {
	json_name, has_tag := parse_json_tag(field.tag)
	if !has_tag {
		return
	}

	for name_node in field.names {
		#partial switch n in name_node.derived {
		case ^ast.Ident:
			field_info: Field_Info
			field_info.odin_name = strings.clone(n.name, allocator)
			field_info.json_name = json_name
			field_info.type_kind, field_info.type_name, field_info.element_type =
				determine_type_kind(field.type, allocator)

			append(fields, field_info)
		}
	}
}

parse_json_tag :: proc(tag: tokenizer.Token) -> (json_name: string, ok: bool) {
	text := tag.text
	if text == "" {
		return "", false
	}

	if len(text) >= 2 && text[0] == '`' && text[len(text) - 1] == '`' {
		text = text[1:len(text) - 1]
	}

	json_prefix := `json:"`
	idx := strings.index(text, json_prefix)
	if idx < 0 {
		return "", false
	}

	remaining := text[idx + len(json_prefix):]

	end_idx := strings.index_byte(remaining, '"')
	if end_idx < 0 {
		return "", false
	}

	value := remaining[:end_idx]

	comma_idx := strings.index_byte(value, ',')
	if comma_idx >= 0 {
		value = value[:comma_idx]
	}

	return value, len(value) > 0
}

determine_type_kind :: proc(
	type_expr: ^ast.Expr,
	allocator := context.allocator,
) -> (
	kind: Type_Kind,
	type_name: string,
	element_type: string,
) {
	if type_expr == nil {
		return .Unknown, "", ""
	}

	#partial switch t in type_expr.derived {
	case ^ast.Ident:
		return type_from_ident(t.name, allocator)

	case ^ast.Array_Type:
		elem_kind, elem_name, _ := determine_type_kind(t.elem, allocator)
		element_type = elem_name

		if elem_kind == .Struct {
			return .Array_Struct, "slice", elem_name
		} else {
			return .Array_Primitive, "slice", elem_name
		}

	case ^ast.Dynamic_Array_Type:
		elem_kind, elem_name, _ := determine_type_kind(t.elem, allocator)
		element_type = elem_name

		if elem_kind == .Struct {
			return .Dynamic_Struct, "dynamic", elem_name
		} else {
			return .Dynamic_Primitive, "dynamic", elem_name
		}

	case ^ast.Pointer_Type:
		return determine_type_kind(t.elem, allocator)

	case ^ast.Selector_Expr:
		type_name = expr_to_string(type_expr, allocator)
		return .Struct, type_name, ""
	}

	return .Unknown, "", ""
}

type_from_ident :: proc(
	name: string,
	allocator := context.allocator,
) -> (
	kind: Type_Kind,
	type_name: string,
	element_type: string,
) {
	type_name = strings.clone(name, allocator)

	switch name {
	case "string":
		return .String, type_name, ""
	case "int":
		return .Int, type_name, ""
	case "i64":
		return .I64, type_name, ""
	case "i32":
		return .I32, type_name, ""
	case "i16":
		return .I16, type_name, ""
	case "i8":
		return .I8, type_name, ""
	case "u64":
		return .U64, type_name, ""
	case "u32":
		return .U32, type_name, ""
	case "u16":
		return .U16, type_name, ""
	case "u8":
		return .U8, type_name, ""
	case "uint":
		return .Uint, type_name, ""
	case "f64":
		return .F64, type_name, ""
	case "f32":
		return .F32, type_name, ""
	case "f16":
		return .F16, type_name, ""
	case "bool":
		return .Bool, type_name, ""
	case:
		// Could be enum or distinct, but we'll treat as struct for now
		return .Struct, type_name, ""
	}
}

expr_to_string :: proc(expr: ^ast.Expr, allocator := context.allocator) -> string {
	if expr == nil {
		return ""
	}

	#partial switch e in expr.derived {
	case ^ast.Ident:
		return strings.clone(e.name, allocator)
	case ^ast.Selector_Expr:
		x := expr_to_string(e.expr, allocator)
		field := e.field != nil ? e.field.name : ""
		return fmt.aprintf("%s.%s", x, field, allocator = allocator)
	}

	return ""
}
