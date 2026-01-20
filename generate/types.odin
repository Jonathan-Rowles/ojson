package generate

Type_Kind :: enum {
	String,
	Int,
	I64,
	F64,
	Bool,

	// Integer types (cast from i64)
	I8,
	I16,
	I32,
	U8,
	U16,
	U32,
	U64,
	Uint,

	// Float types (cast from f64)
	F16,
	F32,
	Enum, // Cast from int
	Distinct, // Cast to underlying then to distinct
	Struct, // Nested struct
	Array_Primitive, // []int, []string, etc.
	Array_Struct, // []User
	Dynamic_Primitive, // [dynamic]int
	Dynamic_Struct, // [dynamic]User
	Unknown,
}

Field_Info :: struct {
	odin_name:    string,
	json_name:    string,
	type_kind:    Type_Kind,
	type_name:    string,
	element_type: string,
	base_type:    string,
}

Struct_Info :: struct {
	name:   string,
	fields: [dynamic]Field_Info,
}

CLI_Options :: struct {
	path:         string,
	output:       string,
	package_name: string,
	recursive:    bool,
	verbose:      bool,
}
