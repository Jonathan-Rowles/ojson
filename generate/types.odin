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
	Fixed_Array_Primitive, // [10]int, [5]string, etc.
	Fixed_Array_Struct, // [10]User
	Unknown,
}

Field_Info :: struct {
	odin_name:    string,
	json_name:    string,
	type_kind:    Type_Kind,
	type_name:    string,
	element_type: string,
	base_type:    string,
	array_size:   int, // For fixed-size arrays like [10]T
	omitempty:    bool,
}

Struct_Info :: struct {
	name:           string,
	fields:         [dynamic]Field_Info,
	source_file:    string, // File where struct was found
	source_package: string, // Package name where struct was found
	source_dir:     string, // Directory where struct was found
	is_tuple:       bool, // True if struct has no json tags (unmarshal as positional array)
}

CLI_Options :: struct {
	path:         string,
	output:       string,
	package_name: string,
	recursive:    bool,
	verbose:      bool,
}
