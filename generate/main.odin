package generate

import "core:flags"
import "core:fmt"
import "core:os"

Options :: struct {
	path:         string `args:"pos=0,required" usage:"Path to scan (file or directory)"`,
	output:       string `args:"name=o" usage:"Output file path"`,
	package_name: string `args:"name=p" usage:"Package name for generated code"`,
	recursive:    bool `args:"name=r" usage:"Scan directories recursively"`,
	verbose:      bool `args:"name=v" usage:"Verbose output"`,
}

main :: proc() {
	opts: Options
	opts.output = "unmarshal.gen.odin"
	opts.package_name = "json"

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

	for file in files {
		structs, parse_ok := parse_file(file)
		if !parse_ok {
			if opts.verbose {
				fmt.eprintfln("Warning: Could not parse: %s", file)
			}
			continue
		}

		for info in structs {
			if opts.verbose {
				fmt.printfln("  Found struct: %s (%d fields)", info.name, len(info.fields))
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

	code := generate_code(all_structs[:], opts.package_name)

	write_ok := os.write_entire_file(opts.output, transmute([]byte)code)
	if !write_ok {
		fmt.eprintfln("Error: Could not write output file: %s", opts.output)
		os.exit(1)
	}

	fmt.printfln("Generated %s with %d unmarshal procedures", opts.output, len(all_structs))
}
