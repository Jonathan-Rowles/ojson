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
	abs_output_dir, _ := fp.abs(output_dir)

	for file in files {
		structs, pkg_name, parse_ok := parse_file(file)
		if !parse_ok {
			if opts.verbose {
				fmt.eprintfln("Warning: Could not parse: %s", file)
			}
			continue
		}

		abs_file, _ := fp.abs(file)
		source_dir := fp.dir(abs_file)

		for &info in structs {
			info.source_file = file
			info.source_package = pkg_name
			info.source_dir = source_dir

			if opts.verbose {
				fmt.printfln(
					"  Found struct: %s (%d fields) in package %s",
					info.name,
					len(info.fields),
					pkg_name,
				)
			}
			append(&all_structs, info)
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
	ojson_jsonimpl := fp.join({ojson_root, "jsonimpl"})

	abs_ojson, _ := fp.abs(ojson_jsonimpl)
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

	write_ok := os.write_entire_file(opts.output, transmute([]byte)code)
	if !write_ok {
		fmt.eprintfln("Error: Could not write output file: %s", opts.output)
		os.exit(1)
	}

	fmt.printfln("Generated %s with %d unmarshal procedures", opts.output, len(all_structs))
}
