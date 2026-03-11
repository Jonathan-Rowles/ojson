package generate

import "core:flags"
import "core:fmt"
import "core:os"
import fp "core:path/filepath"

Options :: struct {
	path:         string `args:"pos=0,required" usage:"Path to scan (file or directory)"`,
	output:       string `args:"name=o" usage:"Output file path"`,
	package_name: string `args:"name=p" usage:"Package name for generated code"`,
	recursive:    bool `args:"name=r" usage:"Scan directories recursively"`,
	verbose:      bool `args:"name=v" usage:"Verbose output"`,
}

main :: proc() {
	opts: Options
	opts.output = "gen/unmarshal.gen.odin"
	opts.package_name = "gen"
	flags.parse_or_exit(&opts, os.args, .Unix)

	if opts.verbose {
		fmt.printfln("Scanning: %s", opts.path)
		fmt.printfln("Output: %s", opts.output)
		fmt.printfln("Package: %s", opts.package_name)
		fmt.printfln("Recursive: %v", opts.recursive)
	}

	files, scan_ok := find_odin_files(opts.path, opts.recursive)
	if !scan_ok {
		fmt.eprintfln("Error: Could not scan path: %s", opts.path)
		os.exit(1)
	}

	if len(files) == 0 {
		fmt.eprintln("No .odin files found")
		os.exit(0)
	}

	if opts.verbose {
		fmt.printfln("Found %d file(s):", len(files))
		for file in files {
			fmt.printfln("  %s", file)
		}
	}

	all_structs := make([dynamic]Struct_Info)
	output_dir := fp.dir(opts.output)
	abs_output_dir, _ := fp.abs(output_dir, context.allocator)

	all_parsed_structs := make(map[string]Struct_Info, allocator = context.allocator)
	defer delete(all_parsed_structs)

	for file in files {
		structs, pkg_name, parse_ok := parse_file(file)
		if !parse_ok {
			if opts.verbose {
				fmt.eprintfln("Warning: Could not parse: %s", file)
			}
			continue
		}

		abs_file, _ := fp.abs(file, context.allocator)
		source_dir := fp.dir(abs_file)

		for &info in structs {
			info.source_file = file
			info.source_package = pkg_name
			info.source_dir = source_dir
			all_parsed_structs[info.name] = info
		}
	}

	for _, info in all_parsed_structs {
		if !info.is_tuple && len(info.fields) > 0 {
			if opts.verbose {
				fmt.printfln(
					"  Found struct: %s (%d fields) in package %s",
					info.name,
					len(info.fields),
					info.source_package,
				)
			}
			append(&all_structs, info)
		}
	}

	added_deps := make(map[string]bool, allocator = context.allocator)
	defer delete(added_deps)

	for info in all_structs {
		for field in info.fields {
			dep_name := field.element_type != "" ? field.element_type : field.type_name
			if dep_name == "" {
				continue
			}
			if dep_info, found := all_parsed_structs[dep_name]; found {
				if dep_info.is_tuple && !added_deps[dep_name] {
					added_deps[dep_name] = true
					if opts.verbose {
						fmt.printfln(
							"  Adding dependency struct: %s (tuple) in package %s",
							dep_info.name,
							dep_info.source_package,
						)
					}
					append(&all_structs, dep_info)
				}
			}
		}
	}

	if len(all_structs) == 0 {
		fmt.eprintln("No structs with json tags found")
		os.exit(0)
	}

	if opts.verbose {
		fmt.printfln("Total structs found: %d", len(all_structs))
	}

	exe_path := os.args[0]
	exe_dir := fp.dir(exe_path)
	ojson_root := fp.dir(exe_dir)
	ojson_jsonimpl, _ := fp.join({ojson_root, "jsonimpl"}, context.allocator)

	abs_ojson, _ := fp.abs(ojson_jsonimpl, context.allocator)
	ojson_import, _ := fp.rel(abs_output_dir, abs_ojson)

	if opts.verbose {
		fmt.printfln("Generator exe: %s", exe_path)
		fmt.printfln("Ojson jsonimpl: %s", abs_ojson)
		fmt.printfln("Ojson import: %s", ojson_import)
	}

	code := generate_code(all_structs[:], opts.package_name, abs_output_dir, ojson_import)

	if output_dir != "" && output_dir != "." {
		os.make_directory(output_dir)
	}

	write_err := os.write_entire_file(opts.output, transmute([]byte)code)
	if write_err != nil {
		fmt.eprintfln("Error: Could not write output file: %s", opts.output)
		os.exit(1)
	}

	fmt.printfln("Generated %s with %d unmarshal procedures", opts.output, len(all_structs))
}
