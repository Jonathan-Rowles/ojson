package main

import "core:fmt"
import "core:os"
import "core:slice"
import sysinfo "core:sys/info"
import "core:time"

SMALL_JSON :: `{"id":12345678901234,"name":"Jon Rowles","email":"jon@example.com","active":true,"score":98.6,"age":37}`

TRIALS :: 5

Job :: struct {
	case_name:  string,
	document:   string,
	doc:        Document,
	run:        proc(doc: Document, data: []byte) -> u64,
	data:       []byte,
	iters:      int,
	throughput: bool,
}

time_job :: proc(job: Job) -> (ns_per_op: f64, checksum: u64) {
	warmup := max(1, job.iters / 10)
	for _ in 0 ..< warmup {
		checksum = job.run(job.doc, job.data)
	}

	samples: [TRIALS]f64
	for t in 0 ..< TRIALS {
		start := time.tick_now()
		for _ in 0 ..< job.iters {
			checksum = job.run(job.doc, job.data)
		}
		elapsed := time.duration_nanoseconds(time.tick_since(start))
		samples[t] = f64(elapsed) / f64(job.iters)
	}
	slice.sort(samples[:])
	return samples[TRIALS / 2], checksum
}

load :: proc(path: string) -> []byte {
	data, err := os.read_entire_file_from_path(path, context.allocator)
	if err != nil {
		fmt.eprintfln("failed to read %s: %v", path, err)
		os.exit(1)
	}
	return data
}

print_header :: proc() {
	fmt.println("ojson benchmark")
	fmt.println()

	physical, logical, cores_ok := sysinfo.cpu_core_count()
	if name := sysinfo.cpu_name(); name != "" {
		if cores_ok {
			fmt.printfln("  cpu     %s (%d physical, %d logical)", name, physical, logical)
		} else {
			fmt.printfln("  cpu     %s", name)
		}
	}
	if version, ok := sysinfo.os_version(context.allocator); ok {
		fmt.printfln("  os      %s", version.full)
	}
	fmt.printfln("  odin    %s", ODIN_VERSION)
	fmt.printfln("  build   -o:speed, %v %v", ODIN_OS, ODIN_ARCH)
	fmt.printfln("  timing  median of %d trials", TRIALS)
	fmt.println()
}

format_size :: proc(bytes: int) -> string {
	switch {
	case bytes < 1024:
		return fmt.aprintf("%d B", bytes)
	case bytes < 1024 * 1024:
		return fmt.aprintf("%.1f KB", f64(bytes) / 1024)
	case:
		return fmt.aprintf("%.1f MB", f64(bytes) / (1024 * 1024))
	}
}

format_time :: proc(ns: f64) -> string {
	switch {
	case ns < 1_000:
		return fmt.aprintf("%.0f ns", ns)
	case ns < 1_000_000:
		return fmt.aprintf("%.2f us", ns / 1_000)
	case:
		return fmt.aprintf("%.2f ms", ns / 1_000_000)
	}
}

format_throughput :: proc(job: Job, ns: f64) -> string {
	if !job.throughput || ns <= 0 {
		return "-"
	}
	return fmt.aprintf("%.0f", f64(len(job.data)) * 1000.0 / ns)
}

main :: proc() {
	twitter := load("testdata/twitter.json")
	canada := load("testdata/canada.json")
	citm := load("testdata/citm_catalog.json")
	small := transmute([]byte)string(SMALL_JSON)

	jobs := []Job {
		{"parse", "twitter.json", .Twitter, bench_parse, twitter, 100, true},
		{"parse", "canada.json", .Canada, bench_parse, canada, 30, true},
		{"parse", "citm_catalog.json", .Citm, bench_parse, citm, 50, true},
		{"extract", "twitter.json", .Twitter, bench_extract, twitter, 100, true},
		{"extract", "canada.json", .Canada, bench_extract, canada, 30, true},
		{"extract", "citm_catalog.json", .Citm, bench_extract, citm, 50, true},
		{"access", "twitter.json", .Twitter, bench_access, twitter, 100, false},
		{"access", "citm_catalog.json", .Citm, bench_access, citm, 40, false},
		{"oneshot", "small struct", .Small, bench_oneshot, small, 50_000, true},
	}

	print_header()
	fmt.printfln(
		"  %-9s %-18s %10s %8s %12s %10s",
		"case",
		"document",
		"size",
		"iters",
		"per-op",
		"MB/s",
	)
	fmt.println("  -------------------------------------------------------------------------")

	total: u64
	for job in jobs {
		ns, checksum := time_job(job)
		total += checksum
		teardown()

		fmt.printfln(
			"  %-9s %-18s %10s %8s %12s %10s",
			job.case_name,
			job.document,
			format_size(len(job.data)),
			fmt.aprintf("%d", job.iters),
			format_time(ns),
			format_throughput(job, ns),
		)
	}

	fmt.println()
	fmt.printfln("  checksum %d", total)
	fmt.println()
	fmt.println("  parse    parse the whole document, reusing one Reader")
	fmt.println("  extract  parse, then read a few known fields by path")
	fmt.println("  access   parse once, then read fields from every array element")
	fmt.println("  oneshot  full setup, parse, read all fields and teardown, every call")
}
