package main

import oj ".."

Document :: enum {
	Twitter,
	Canada,
	Citm,
	Small,
}

reader: oj.Reader
reader_ready: bool

access_reader: oj.Reader
access_ready: bool
access_input: rawptr
access_elems: []oj.Element

shared_reader :: proc() -> ^oj.Reader {
	if !reader_ready {
		oj.init_reader(&reader)
		reader_ready = true
	}
	return &reader
}

teardown :: proc() {
	if reader_ready {
		oj.destroy(&reader)
		reader_ready = false
	}
	if access_ready {
		oj.destroy(&access_reader)
		access_ready = false
		access_input = nil
	}
}

abs_f64 :: proc(x: f64) -> f64 {
	return x < 0 ? -x : x
}

bench_parse :: proc(doc: Document, data: []byte) -> u64 {
	r := shared_reader()
	if oj.parse(r, data) != .OK {
		return 0
	}
	return u64(len(oj.object_keys(r, oj.root_element(r))))
}

bench_extract :: proc(doc: Document, data: []byte) -> u64 {
	r := shared_reader()
	if oj.parse(r, data) != .OK {
		return 0
	}
	switch doc {
	case .Twitter:
		id, _ := oj.read_i64(r, "statuses.0.id")
		screen_name, _ := oj.read_string(r, "statuses.0.user.screen_name")
		retweets, _ := oj.read_int(r, "statuses.0.retweet_count")
		count, _ := oj.read_int(r, "search_metadata.count")
		return u64(id) + u64(len(screen_name)) + u64(retweets) + u64(count)
	case .Canada:
		feature_type, _ := oj.read_string(r, "type")
		geometry_type, _ := oj.read_string(r, "features.0.geometry.type")
		x, _ := oj.read_f64(r, "features.0.geometry.coordinates.0.0.0")
		return u64(len(feature_type)) + u64(len(geometry_type)) + u64(abs_f64(x) * 1000)
	case .Citm:
		id, _ := oj.read_i64(r, "performances.0.id")
		event_id, _ := oj.read_i64(r, "performances.0.eventId")
		return u64(id) + u64(event_id)
	case .Small:
		return 0
	}
	return 0
}

bench_access :: proc(doc: Document, data: []byte) -> u64 {
	if access_input != rawptr(raw_data(data)) {
		if !access_ready {
			oj.init_reader(&access_reader)
			access_ready = true
		}
		if oj.parse(&access_reader, data) != .OK {
			return 0
		}
		path := doc == .Twitter ? "statuses" : "performances"
		access_elems, _ = oj.array_elements(&access_reader, path)
		access_input = rawptr(raw_data(data))
	}

	sum: u64
	#partial switch doc {
	case .Twitter:
		for elem in access_elems {
			id, _ := oj.read_i64(&access_reader, elem, "id")
			retweets, _ := oj.read_int(&access_reader, elem, "retweet_count")
			sum += u64(id) + u64(retweets)
		}
	case .Citm:
		for elem in access_elems {
			id, _ := oj.read_i64(&access_reader, elem, "id")
			event_id, _ := oj.read_i64(&access_reader, elem, "eventId")
			sum += u64(id) + u64(event_id)
		}
	}
	return sum
}

bench_oneshot :: proc(doc: Document, data: []byte) -> u64 {
	r: oj.Reader
	oj.init_reader(&r)
	defer oj.destroy(&r)
	if oj.parse(&r, data) != .OK {
		return 0
	}
	id, _ := oj.read_i64(&r, "id")
	name, _ := oj.read_string(&r, "name")
	email, _ := oj.read_string(&r, "email")
	active, _ := oj.read_bool(&r, "active")
	score, _ := oj.read_f64(&r, "score")
	age, _ := oj.read_int(&r, "age")
	return(
		u64(id) +
		u64(len(name)) +
		u64(len(email)) +
		(active ? 1 : 0) +
		u64(abs_f64(score) * 100) +
		u64(age) \
	)
}
