package generate

import "core:os"
import "core:path/filepath"
import "core:strings"

find_odin_files :: proc(
	path: string,
	recursive: bool,
	allocator := context.allocator,
) -> (
	files: [dynamic]string,
	ok: bool,
) {
	files = make([dynamic]string, allocator)

	info, err := os.stat(path, allocator)
	if err != nil {
		return files, false
	}

	if info.type != .Directory {
		if strings.has_suffix(path, ".odin") && !strings.has_suffix(path, "_test.odin") {
			append(&files, strings.clone(path, allocator))
		}
		return files, true
	}

	if recursive {
		scan_directory_recursive(path, &files, allocator)
	} else {
		scan_directory(path, &files, allocator)
	}

	return files, true
}

scan_directory :: proc(dir: string, files: ^[dynamic]string, allocator := context.allocator) {
	handle, err := os.open(dir)
	if err != nil {
		return
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1, allocator)
	if read_err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, allocator)

	for entry in entries {
		if entry.type == .Directory {
			continue
		}
		if strings.has_suffix(entry.name, ".odin") &&
		   !strings.has_suffix(entry.name, "_test.odin") {
			full_path, _ := filepath.join({dir, entry.name}, allocator)
			append(files, full_path)
		}
	}
}

scan_directory_recursive :: proc(
	dir: string,
	files: ^[dynamic]string,
	allocator := context.allocator,
) {
	handle, err := os.open(dir)
	if err != nil {
		return
	}
	defer os.close(handle)

	entries, read_err := os.read_dir(handle, -1, allocator)
	if read_err != nil {
		return
	}
	defer os.file_info_slice_delete(entries, allocator)

	for entry in entries {
		full_path, _ := filepath.join({dir, entry.name}, allocator)

		if entry.type == .Directory {
			if strings.has_prefix(entry.name, ".") || entry.name == "bin" {
				delete(full_path, allocator)
				continue
			}
			scan_directory_recursive(full_path, files, allocator)
			delete(full_path, allocator)
		} else {
			if strings.has_suffix(entry.name, ".odin") &&
			   !strings.has_suffix(entry.name, "_test.odin") {
				append(files, full_path)
			} else {
				delete(full_path, allocator)
			}
		}
	}
}
