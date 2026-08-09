package generate

import "core:fmt"
import "core:odin/ast"
import "core:odin/parser"
import "core:odin/tokenizer"
import "core:os"
import "core:strconv"
import "core:strings"

get_package_name :: proc(
	file_path: string,
	allocator := context.allocator,
) -> (
	name: string,
	ok: bool,
) {
	data, read_err := os.read_entire_file(file_path, allocator)
	if read_err != nil {
		return "", false
	}

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = string(data)
	file.fullpath = file_path

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	if !parser.parse_file(&p, file) {
		return "", false
	}

	if file.pkg_name != "" {
		return strings.clone(file.pkg_name, allocator), true
	}

	return "", false
}

parse_file :: proc(
	file_path: string,
	allocator := context.allocator,
) -> (
	structs: [dynamic]Struct_Info,
	unions: [dynamic]Union_Info,
	pkg_name: string,
	ok: bool,
) {
	structs = make([dynamic]Struct_Info, allocator)
	unions = make([dynamic]Union_Info, allocator)

	data, read_err := os.read_entire_file(file_path, allocator)
	if read_err != nil {
		return structs, unions, "", false
	}

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = string(data)
	file.fullpath = file_path

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	if !parser.parse_file(&p, file) {
		return structs, unions, "", false
	}

	pkg_name = file.pkg_name != "" ? strings.clone(file.pkg_name, allocator) : ""

	collect_constants(file.decls[:])

	for decl in file.decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			process_value_decl(d, &structs, &unions, allocator, file.src)
		}
	}

	return structs, unions, pkg_name, true
}

process_value_decl :: proc(
	decl: ^ast.Value_Decl,
	structs: ^[dynamic]Struct_Info,
	unions: ^[dynamic]Union_Info,
	allocator := context.allocator,
	src := "",
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
			struct_info := extract_struct_info(n.name, v, allocator, src)
			if struct_info != nil && len(struct_info.fields) > 0 && !struct_info.is_tuple {
				append(structs, struct_info^)
			}
		case ^ast.Union_Type:
			union_info := extract_union_info(n.name, v, allocator)
			if union_info != nil && len(union_info.variants) > 0 {
				append(unions, union_info^)
			}
		}
	}
}

extract_union_info :: proc(
	name: string,
	union_type: ^ast.Union_Type,
	allocator := context.allocator,
) -> ^Union_Info {
	info := new(Union_Info, allocator)
	info.name = strings.clone(name, allocator)
	info.variants = make([dynamic]Union_Variant, allocator)

	if union_type.variants == nil {
		return info
	}

	for variant in union_type.variants {
		variant_name := expr_to_string(variant, allocator)
		if variant_name == "" {
			continue
		}
		append(&info.variants, Union_Variant{struct_name = variant_name})
	}

	return info
}

resolve_unions :: proc(
	unions: ^[dynamic]Union_Info,
	structs: []Struct_Info,
	allocator := context.allocator,
) {
	structs_by_name := make(map[string]^Struct_Info, allocator = allocator)
	defer delete(structs_by_name)
	for &s in structs {
		structs_by_name[s.name] = &s
	}

	resolved: [dynamic]Union_Info
	resolved = make([dynamic]Union_Info, allocator)

	for &u in unions {
		discriminator := ""
		all_resolved := true

		for &v in u.variants {
			variant_struct, found := structs_by_name[v.struct_name]
			if !found {
				all_resolved = false
				break
			}

			tag_field_idx := -1
			for f, i in variant_struct.fields {
				if f.union_tag != "" {
					tag_field_idx = i
					break
				}
			}
			if tag_field_idx < 0 {
				all_resolved = false
				break
			}

			marker := variant_struct.fields[tag_field_idx]
			if discriminator == "" {
				discriminator = marker.json_name
			} else if discriminator != marker.json_name {
				all_resolved = false
				break
			}
			v.tag = marker.union_tag
		}

		if all_resolved && discriminator != "" {
			u.discriminator = discriminator
			append(&resolved, u)
		}
	}

	union_names := make(map[string]bool, allocator = allocator)
	defer delete(union_names)
	for u in resolved {
		union_names[u.name] = true
	}

	for &s in structs {
		for &f in s.fields {
			#partial switch f.type_kind {
			case .Struct:
				if f.type_name in union_names {
					f.type_kind = .Union
				}
			case .Array_Struct:
				if f.element_type in union_names {
					f.type_kind = .Array_Union
				}
			case .Dynamic_Struct:
				if f.element_type in union_names {
					f.type_kind = .Dynamic_Union
				}
			case .Fixed_Array_Struct:
				if f.element_type in union_names {
					f.type_kind = .Fixed_Array_Union
				}
			}
		}
	}

	clear(unions)
	for u in resolved {
		append(unions, u)
	}
	delete(resolved)
}

resolve_named_types :: proc(structs: []Struct_Info, named: Named_Types) {
	for &s in structs {
		for &f in s.fields {
			element_supported := true
			if f.element_type in named.enums {
				f.element_kind = .Enum
			} else if base, is_distinct := named.distincts[f.element_type]; is_distinct {
				if is_primitive_type_name(base) {
					f.element_kind = .Distinct
					f.base_type = base
				} else {
					element_supported = false
				}
			}

			#partial switch f.type_kind {
			case .Struct:
				if f.type_name in named.enums {
					f.type_kind = .Enum
				} else if base, is_distinct := named.distincts[f.type_name]; is_distinct {
					f.type_kind = is_primitive_type_name(base) ? .Distinct : .Unknown
					f.base_type = base
				}
			case .Array_Struct:
				if !element_supported {
					f.type_kind = .Unknown
				} else if f.element_kind != .None {
					f.type_kind = .Array_Primitive
				}
			case .Dynamic_Struct:
				if !element_supported {
					f.type_kind = .Unknown
				} else if f.element_kind != .None {
					f.type_kind = .Dynamic_Primitive
				}
			case .Fixed_Array_Struct:
				if !element_supported {
					f.type_kind = .Unknown
				} else if f.element_kind != .None {
					f.type_kind = .Fixed_Array_Primitive
				}
			case .Pointer_Struct:
				if !element_supported {
					f.type_kind = .Unknown
				} else if f.element_kind != .None {
					f.type_kind = .Pointer_Primitive
				}
			case .Map_Struct:
				if !element_supported {
					f.type_kind = .Unknown
				} else if f.element_kind != .None {
					f.type_kind = .Map_Primitive
				}
			}

			#partial switch f.type_kind {
			case .Map_Primitive, .Map_Struct:
				if !is_map_key_type(f.key_type, named) {
					f.type_kind = .Unknown
				}
			}
		}
	}
}

is_map_key_type :: proc(key_type: string, named: Named_Types) -> bool {
	return key_type == "string" || is_integer_type(key_type) || key_type in named.enums
}

extract_struct_info :: proc(
	name: string,
	struct_type: ^ast.Struct_Type,
	allocator := context.allocator,
	src := "",
) -> ^Struct_Info {
	info := new(Struct_Info, allocator)
	info.name = strings.clone(name, allocator)
	info.fields = make([dynamic]Field_Info, allocator)
	info.is_tuple = false

	if struct_type.fields == nil || struct_type.fields.list == nil {
		return info
	}

	has_any_json_tag := false
	for field in struct_type.fields.list {
		process_field(field, &info.fields, &has_any_json_tag, allocator, src)
	}

	if !has_any_json_tag && len(info.fields) > 0 {
		info.is_tuple = true
	}

	return info
}

process_field :: proc(
	field: ^ast.Field,
	fields: ^[dynamic]Field_Info,
	has_any_json_tag: ^bool,
	allocator := context.allocator,
	src := "",
) {
	json_name, omitempty, raw, union_tag, has_tag := parse_json_tag(field.tag, allocator)
	if has_tag {
		has_any_json_tag^ = true
		if json_name == "-" {
			return
		}
	}

	for name_node in field.names {
		#partial switch n in name_node.derived {
		case ^ast.Ident:
			field_info: Field_Info
			field_info.odin_name = strings.clone(n.name, allocator)
			field_info.json_name = has_tag ? json_name : strings.clone(n.name, allocator)
			field_info.omitempty = omitempty
			field_info.raw = raw
			field_info.union_tag = union_tag
			field_info.type_kind, field_info.type_name, field_info.element_type, field_info.array_size =
				determine_type_kind(field.type, allocator)

			if field.type != nil {
				#partial switch map_type in field.type.derived {
				case ^ast.Map_Type:
					field_info.key_type, _ = map_key_type(map_type.key, allocator)
				}

				start := field.type.pos.offset
				end := field.type.end.offset
				if src != "" && start >= 0 && end > start && end <= len(src) {
					field_info.type_text = src[start:end]
				}
			}

			append(fields, field_info)
		}
	}
}

parse_json_tag :: proc(
	tag: tokenizer.Token,
	allocator := context.allocator,
) -> (
	json_name: string,
	omitempty: bool,
	raw: bool,
	union_tag: string,
	ok: bool,
) {
	text := tag.text
	if text == "" {
		return "", false, false, "", false
	}

	if len(text) >= 2 && text[0] == '`' && text[len(text) - 1] == '`' {
		text = text[1:len(text) - 1]
	}

	json_prefix := `json:"`
	idx := strings.index(text, json_prefix)
	if idx < 0 {
		return "", false, false, "", false
	}

	remaining := text[idx + len(json_prefix):]

	end_idx := strings.index_byte(remaining, '"')
	if end_idx < 0 {
		return "", false, false, "", false
	}

	value := remaining[:end_idx]

	comma_idx := strings.index_byte(value, ',')
	if comma_idx >= 0 {
		options := value[comma_idx + 1:]
		value = value[:comma_idx]
		omitempty = has_option(options, "omitempty")
		raw = has_option(options, "raw")
		union_tag = extract_tag_option(options, allocator)
	}

	return value, omitempty, raw, union_tag, len(value) > 0
}

has_option :: proc(options: string, name: string) -> bool {
	remaining := options
	for len(remaining) > 0 {
		comma := strings.index_byte(remaining, ',')
		segment: string
		if comma < 0 {
			segment = remaining
			remaining = ""
		} else {
			segment = remaining[:comma]
			remaining = remaining[comma + 1:]
		}
		if strings.trim_space(segment) == name {
			return true
		}
	}
	return false
}

extract_tag_option :: proc(options: string, allocator := context.allocator) -> string {
	prefix := "tag="
	remaining := options
	for len(remaining) > 0 {
		comma := strings.index_byte(remaining, ',')
		segment: string
		if comma < 0 {
			segment = remaining
			remaining = ""
		} else {
			segment = remaining[:comma]
			remaining = remaining[comma + 1:]
		}
		segment = strings.trim_space(segment)
		if strings.has_prefix(segment, prefix) {
			return strings.clone(segment[len(prefix):], allocator)
		}
	}
	return ""
}

determine_type_kind :: proc(
	type_expr: ^ast.Expr,
	allocator := context.allocator,
) -> (
	kind: Type_Kind,
	type_name: string,
	element_type: string,
	array_size: int,
) {
	if type_expr == nil {
		return .Unknown, "", "", 0
	}

	#partial switch t in type_expr.derived {
	case ^ast.Ident:
		k, n, e := type_from_ident(t.name, allocator)
		return k, n, e, 0

	case ^ast.Array_Type:
		elem_kind, elem_name, _, _ := determine_type_kind(t.elem, allocator)
		element_type = elem_name

		if elem_kind != .Struct && !is_primitive_kind(elem_kind) {
			return .Unknown, "", "", 0
		}

		if t.len != nil {
			size := parse_array_length(t.len)
			if elem_kind == .Struct {
				return .Fixed_Array_Struct, "fixed", elem_name, size
			} else {
				return .Fixed_Array_Primitive, "fixed", elem_name, size
			}
		}

		if elem_kind == .Struct {
			return .Array_Struct, "slice", elem_name, 0
		} else {
			return .Array_Primitive, "slice", elem_name, 0
		}

	case ^ast.Dynamic_Array_Type:
		elem_kind, elem_name, _, _ := determine_type_kind(t.elem, allocator)
		element_type = elem_name

		if elem_kind != .Struct && !is_primitive_kind(elem_kind) {
			return .Unknown, "", "", 0
		}

		if elem_kind == .Struct {
			return .Dynamic_Struct, "dynamic", elem_name, 0
		} else {
			return .Dynamic_Primitive, "dynamic", elem_name, 0
		}

	case ^ast.Pointer_Type:
		elem_kind, elem_name, _, _ := determine_type_kind(t.elem, allocator)

		if elem_kind == .Struct {
			return .Pointer_Struct, "pointer", elem_name, 0
		}
		if is_primitive_kind(elem_kind) {
			return .Pointer_Primitive, "pointer", elem_name, 0
		}
		return .Unknown, "", "", 0

	case ^ast.Map_Type:
		_, key_ok := map_key_type(t.key, allocator)
		if !key_ok {
			return .Unknown, "", "", 0
		}

		value_kind, value_name, _, _ := determine_type_kind(t.value, allocator)

		if value_kind == .Struct {
			return .Map_Struct, "map", value_name, 0
		}
		if is_primitive_kind(value_kind) {
			return .Map_Primitive, "map", value_name, 0
		}
		return .Unknown, "", "", 0

	case ^ast.Selector_Expr:
		type_name = expr_to_string(type_expr, allocator)
		return .Struct, type_name, "", 0
	}

	return .Unknown, "", "", 0
}

map_key_type :: proc(
	key_expr: ^ast.Expr,
	allocator := context.allocator,
) -> (
	key_type: string,
	ok: bool,
) {
	kind, name, _, _ := determine_type_kind(key_expr, allocator)

	#partial switch kind {
	case .String, .Int, .I64, .I8, .I16, .I32, .U8, .U16, .U32, .U64, .Uint, .Struct:
		return name, true
	}
	return "", false
}

is_primitive_type_name :: proc(name: string) -> bool {
	return name == "string" || name == "bool" || is_integer_type(name) || is_float_type(name)
}

is_primitive_kind :: proc(kind: Type_Kind) -> bool {
	#partial switch kind {
	case .String, .Int, .I64, .F64, .Bool, .I8, .I16, .I32, .U8, .U16, .U32, .U64, .Uint, .F16, .F32:
		return true
	}
	return false
}

g_constants: map[string]int

collect_file_declarations :: proc(
	file_path: string,
	named: ^Named_Types,
	allocator := context.allocator,
) -> bool {
	data, read_err := os.read_entire_file(file_path, allocator)
	if read_err != nil {
		return false
	}

	NO_POS :: tokenizer.Pos{}
	file := ast.new(ast.File, NO_POS, NO_POS)
	file.src = string(data)
	file.fullpath = file_path

	p := parser.default_parser()
	p.err = proc(_: tokenizer.Pos, _: string, _: ..any) {}
	p.warn = proc(_: tokenizer.Pos, _: string, _: ..any) {}

	if !parser.parse_file(&p, file) {
		return false
	}

	collect_constants(file.decls[:])
	collect_named_types(file.decls[:], named)
	return true
}

collect_named_types :: proc(decls: []^ast.Stmt, named: ^Named_Types) {
	for decl in decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			if d.is_mutable {
				continue
			}
			for name_node, i in d.names {
				if i >= len(d.values) {
					break
				}
				#partial switch n in name_node.derived {
				case ^ast.Ident:
					#partial switch v in d.values[i].derived {
					case ^ast.Enum_Type:
						named.enums[n.name] = true
					case ^ast.Distinct_Type:
						named.distincts[n.name] = distinct_base_name(v.type)
					}
				}
			}
		}
	}
}

distinct_base_name :: proc(type_expr: ^ast.Expr) -> string {
	if type_expr == nil {
		return ""
	}
	#partial switch t in type_expr.derived {
	case ^ast.Ident:
		return t.name
	}
	return ""
}

collect_constants :: proc(decls: []^ast.Stmt) {
	for decl in decls {
		#partial switch d in decl.derived {
		case ^ast.Value_Decl:
			if len(d.names) == 0 || len(d.values) == 0 {
				continue
			}
			if !d.is_mutable {
				#partial switch n in d.names[0].derived {
				case ^ast.Ident:
					val, ok := eval_const_expr(d.values[0])
					if ok {
						g_constants[n.name] = val
					}
				}
			}
		}
	}
}

eval_const_expr :: proc(expr: ^ast.Expr) -> (int, bool) {
	if expr == nil {
		return 0, false
	}
	#partial switch e in expr.derived {
	case ^ast.Basic_Lit:
		val, ok := strconv.parse_int(e.tok.text)
		return val, ok
	case ^ast.Ident:
		if val, found := g_constants[e.name]; found {
			return val, true
		}
	}
	return 0, false
}

parse_array_length :: proc(expr: ^ast.Expr) -> int {
	val, ok := eval_const_expr(expr)
	if ok {
		return val
	}
	return 0
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
