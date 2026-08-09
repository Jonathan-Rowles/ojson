#+build !js
package jsonimpl

import stdjson "core:encoding/json"
import "core:math"
import "core:strings"
import "core:testing"

@(test)
test_parse_simple_object :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"name": "test", "value": 42}`))
	testing.expect_value(t, err, Error.OK)

	name, name_err := read_string(&r, "name")
	testing.expect_value(t, name_err, Error.OK)
	testing.expect_value(t, name, "test")

	value, value_err := read_int(&r, "value")
	testing.expect_value(t, value_err, Error.OK)
	testing.expect_value(t, value, 42)
}

@(test)
test_parse_nested_object :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"user": {"name": "alice", "age": 30}}`))
	testing.expect_value(t, err, Error.OK)

	name, name_err := read_string(&r, "user.name")
	testing.expect_value(t, name_err, Error.OK)
	testing.expect_value(t, name, "alice")

	age, age_err := read_int(&r, "user.age")
	testing.expect_value(t, age_err, Error.OK)
	testing.expect_value(t, age, 30)
}

@(test)
test_parse_array :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"items": [1, 2, 3]}`))
	testing.expect_value(t, err, Error.OK)

	length, len_err := array_len(&r, "items")
	testing.expect_value(t, len_err, Error.OK)
	testing.expect_value(t, length, 3)

	first, first_err := read_int(&r, "items.0")
	testing.expect_value(t, first_err, Error.OK)
	testing.expect_value(t, first, 1)

	third, third_err := read_int(&r, "items.2")
	testing.expect_value(t, third_err, Error.OK)
	testing.expect_value(t, third, 3)
}

@(test)
test_parse_booleans :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"active": true, "deleted": false}`))
	testing.expect_value(t, err, Error.OK)

	active, active_err := read_bool(&r, "active")
	testing.expect_value(t, active_err, Error.OK)
	testing.expect_value(t, active, true)

	deleted, deleted_err := read_bool(&r, "deleted")
	testing.expect_value(t, deleted_err, Error.OK)
	testing.expect_value(t, deleted, false)
}

@(test)
test_parse_null :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"data": null}`))
	testing.expect_value(t, err, Error.OK)
	testing.expect(t, is_null(&r, "data"), "data should be null")
}

@(test)
test_parse_float :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"pi": 3.14159, "neg": -1.5e10}`))
	testing.expect_value(t, err, Error.OK)

	pi, pi_err := read_f64(&r, "pi")
	testing.expect_value(t, pi_err, Error.OK)
	testing.expect(t, pi > 3.14 && pi < 3.15, "pi should be ~3.14")

	neg, neg_err := read_f64(&r, "neg")
	testing.expect_value(t, neg_err, Error.OK)
	testing.expect(t, neg < 0, "neg should be negative")
}

@(test)
test_parse_escaped_string :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"msg": "hello\nworld", "quote": "say \"hi\""}`))
	testing.expect_value(t, err, Error.OK)

	msg, msg_err := read_string(&r, "msg")
	testing.expect_value(t, msg_err, Error.OK)
	testing.expect_value(t, msg, "hello\nworld")

	quote, quote_err := read_string(&r, "quote")
	testing.expect_value(t, quote_err, Error.OK)
	testing.expect_value(t, quote, `say "hi"`)
}

@(test)
test_exists :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"a": {"b": 1}}`))
	testing.expect_value(t, err, Error.OK)

	testing.expect(t, exists(&r, "a"), "a should exist")
	testing.expect(t, exists(&r, "a.b"), "a.b should exist")
	testing.expect(t, !exists(&r, "c"), "c should not exist")
	testing.expect(t, !exists(&r, "a.c"), "a.c should not exist")
}

@(test)
test_empty_object :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{}`))
	testing.expect_value(t, err, Error.OK)
}

@(test)
test_empty_array :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"arr": []}`))
	testing.expect_value(t, err, Error.OK)

	length, len_err := array_len(&r, "arr")
	testing.expect_value(t, len_err, Error.OK)
	testing.expect_value(t, length, 0)
}

@(test)
test_array_of_objects :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"users": [{"name": "alice"}, {"name": "bob"}]}`))
	testing.expect_value(t, err, Error.OK)

	first_name, first_err := read_string(&r, "users.0.name")
	testing.expect_value(t, first_err, Error.OK)
	testing.expect_value(t, first_name, "alice")

	second_name, second_err := read_string(&r, "users.1.name")
	testing.expect_value(t, second_err, Error.OK)
	testing.expect_value(t, second_name, "bob")
}

@(test)
test_reuse :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err1 := parse(&r, transmute([]byte)string(`{"x": 1}`))
	testing.expect_value(t, err1, Error.OK)

	x1, _ := read_int(&r, "x")
	testing.expect_value(t, x1, 1)

	err2 := parse(&r, transmute([]byte)string(`{"y": 2}`))
	testing.expect_value(t, err2, Error.OK)

	y, _ := read_int(&r, "y")
	testing.expect_value(t, y, 2)

	testing.expect(t, !exists(&r, "x"), "x should not exist after new parse")
}

@(test)
test_unicode_escape :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"emoji": "\u0048\u0065\u006c\u006c\u006f"}`))
	testing.expect_value(t, err, Error.OK)

	emoji, emoji_err := read_string(&r, "emoji")
	testing.expect_value(t, emoji_err, Error.OK)
	testing.expect_value(t, emoji, "Hello")
}

@(test)
test_root_array :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`[1, 2, 3]`))
	testing.expect_value(t, err, Error.OK)

	first, first_err := read_int(&r, "0")
	testing.expect_value(t, first_err, Error.OK)
	testing.expect_value(t, first, 1)

	third, third_err := read_int(&r, "2")
	testing.expect_value(t, third_err, Error.OK)
	testing.expect_value(t, third, 3)
}

@(test)
test_whitespace :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	json := `
	{
		"name" : "test" ,
		"value" : 123
	}
	`


	err := parse(&r, transmute([]byte)json)
	testing.expect_value(t, err, Error.OK)

	name, _ := read_string(&r, "name")
	testing.expect_value(t, name, "test")

	value, _ := read_int(&r, "value")
	testing.expect_value(t, value, 123)
}

@(test)
test_deep_nesting :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	data := `{"a": {"b": {"c": {"d": {"e": "deep"}}}}}`
	err := parse(&r, transmute([]byte)data)
	testing.expect_value(t, err, Error.OK)

	val, err_val := read_string(&r, "a.b.c.d.e")
	testing.expect_value(t, err_val, Error.OK)
	testing.expect_value(t, val, "deep")
}

@(test)
test_parse_auto_reset :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err1 := parse(&r, transmute([]byte)string(`{"value": 1}`))
	testing.expect_value(t, err1, Error.OK)

	v1, _ := read_int(&r, "value")
	testing.expect_value(t, v1, 1)

	err2 := parse(&r, transmute([]byte)string(`{"value": 2}`))
	testing.expect_value(t, err2, Error.OK)

	v2, _ := read_int(&r, "value")
	testing.expect_value(t, v2, 2)
}

@(test)
test_read_before_parse :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	_, err := read_string(&r, "key")
	testing.expect_value(t, err, Error.Not_Parsed)
}

@(test)
test_invalid_json :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{invalid json}`))
	testing.expect(t, err != .OK, "expected parse to fail")
}

@(test)
test_large_numbers :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	data := `{"big": 9007199254740991}`
	err := parse(&r, transmute([]byte)data)
	testing.expect_value(t, err, Error.OK)

	big, big_err := read_i64(&r, "big")
	testing.expect_value(t, big_err, Error.OK)
	testing.expect_value(t, big, i64(9007199254740991))
}

@(test)
test_negative_numbers :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	data := `{"neg": -42, "negf": -3.14}`
	err := parse(&r, transmute([]byte)data)
	testing.expect_value(t, err, Error.OK)

	neg, _ := read_int(&r, "neg")
	testing.expect_value(t, neg, -42)

	negf, _ := read_f64(&r, "negf")
	testing.expect(t, negf < -3.13 && negf > -3.15, "expected ~-3.14")
}

@(test)
test_get_string :: proc(t: ^testing.T) {
	data := `{"name": "alice", "user": {"email": "alice@test.com"}}`

	name, name_err := get_string(transmute([]byte)data, "name")
	defer delete(name)
	testing.expect_value(t, name_err, Error.OK)
	testing.expect_value(t, name, "alice")

	email, email_err := get_string(transmute([]byte)data, "user.email")
	defer delete(email)
	testing.expect_value(t, email_err, Error.OK)
	testing.expect_value(t, email, "alice@test.com")
}

@(test)
test_get_string_escaped_outlives_reader :: proc(t: ^testing.T) {
	data := `{"note": "line1\nline2 \"quoted\""}`

	note, err := get_string(transmute([]byte)data, "note")
	defer delete(note)
	testing.expect_value(t, err, Error.OK)
	testing.expect_value(t, note, "line1\nline2 \"quoted\"")
}

@(test)
test_get_int :: proc(t: ^testing.T) {
	data := `{"count": 42, "nested": {"value": -10}}`

	count, count_err := get_int(transmute([]byte)data, "count")
	testing.expect_value(t, count_err, Error.OK)
	testing.expect_value(t, count, 42)

	value, value_err := get_int(transmute([]byte)data, "nested.value")
	testing.expect_value(t, value_err, Error.OK)
	testing.expect_value(t, value, -10)
}

@(test)
test_get_f64 :: proc(t: ^testing.T) {
	data := `{"pi": 3.14159}`

	pi, pi_err := get_f64(transmute([]byte)data, "pi")
	testing.expect_value(t, pi_err, Error.OK)
	testing.expect(t, pi > 3.14 && pi < 3.15, "expected ~3.14")
}

@(test)
test_get_bool :: proc(t: ^testing.T) {
	data := `{"active": true, "deleted": false}`

	active, active_err := get_bool(transmute([]byte)data, "active")
	testing.expect_value(t, active_err, Error.OK)
	testing.expect_value(t, active, true)

	deleted, deleted_err := get_bool(transmute([]byte)data, "deleted")
	testing.expect_value(t, deleted_err, Error.OK)
	testing.expect_value(t, deleted, false)
}

@(test)
test_get_missing_key :: proc(t: ^testing.T) {
	data := `{"name": "test"}`

	_, err := get_string(transmute([]byte)data, "missing")
	testing.expect_value(t, err, Error.Key_Not_Found)
}

@(test)
test_get_type_mismatch :: proc(t: ^testing.T) {
	data := `{"name": "test"}`

	_, err := get_int(transmute([]byte)data, "name")
	testing.expect_value(t, err, Error.Type_Mismatch)
}

@(test)
test_writer_basic :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	data := struct {
		name: string,
		age:  int,
	}{"alice", 30}

	out, err := marshal_to(&w, data)
	testing.expect_value(t, err, Error.OK)
	testing.expect(t, len(out) > 0, "expected non-empty output")
}

@(test)
test_writer_escapes_control_characters :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	write_string(&w, "a\x00b\x01c\x1fd")
	testing.expect_value(t, writer_string(&w), `"a\u0000b\u0001c\u001fd"`)
}

@(test)
test_writer_escapes_mixed_control_and_utf8 :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	write_string(&w, "tab\there\x0bverté世\x1a")
	testing.expect_value(t, writer_string(&w), `"tab\there\u000bverté世\u001a"`)
}

@(test)
test_writer_short_escapes :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	write_string(&w, "\"\\\b\f\n\r\t")
	testing.expect_value(t, writer_string(&w), `"\"\\\b\f\n\r\t"`)
}

@(test)
test_writer_key_escapes_control_characters :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	write_object_start(&w)
	write_key(&w, "k\x02")
	write_string(&w, "v\x1f")
	write_object_end(&w)
	testing.expect_value(t, writer_string(&w), `{"k\u0002":"v\u001f"}`)
}

@(test)
test_writer_float_round_trip :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	write_array_start(&w)
	write_f64(&w, 3.25)
	write_f64(&w, 0.001)
	write_f64(&w, -2.5)
	write_f64(&w, 0)
	write_f64(&w, 123456789.123456789)
	write_f32(&w, 0.1)
	write_array_end(&w)
	testing.expect_value(t, writer_string(&w), `[3.25,0.001,-2.5,0,123456789.12345679,0.1]`)
}

@(test)
test_writer_float_extremes :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	write_array_start(&w)
	write_f64(&w, 1e21)
	write_f64(&w, 1e-7)
	write_f64(&w, math.nan_f64())
	write_f64(&w, math.inf_f64(1))
	write_array_end(&w)

	out := writer_string(&w)
	reparsed, err := stdjson.parse(transmute([]byte)out)
	testing.expect(t, err == nil, "extreme float output must be valid JSON")
	stdjson.destroy_value(reparsed)
	testing.expect_value(t, out, `[1e+21,1e-07,null,null]`)
}

@(test)
test_writer_reuse :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	data1 := struct {
		x: int,
	}{1}
	data2 := struct {
		y: int,
	}{2}

	out1, err1 := marshal_to(&w, data1)
	testing.expect_value(t, err1, Error.OK)
	testing.expect(t, len(out1) > 0, "expected non-empty output")

	out2, err2 := marshal_to(&w, data2)
	testing.expect_value(t, err2, Error.OK)
	testing.expect(t, len(out2) > 0, "expected non-empty output")
}

@(test)
test_root_element :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"name": "test"}`))
	testing.expect_value(t, err, Error.OK)

	root := root_element(&r)
	name, name_err := read_string_elem(&r, root, "name")
	testing.expect_value(t, name_err, Error.OK)
	testing.expect_value(t, name, "test")
}

@(test)
test_element_at :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"user": {"name": "alice", "age": 30}}`))
	testing.expect_value(t, err, Error.OK)

	user_elem, elem_err := element_at(&r, "user")
	testing.expect_value(t, elem_err, Error.OK)

	name, name_err := read_string_elem(&r, user_elem, "name")
	testing.expect_value(t, name_err, Error.OK)
	testing.expect_value(t, name, "alice")

	age, age_err := read_int_elem(&r, user_elem, "age")
	testing.expect_value(t, age_err, Error.OK)
	testing.expect_value(t, age, 30)
}

@(test)
test_element_at_empty_path :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"x": 1}`))
	testing.expect_value(t, err, Error.OK)

	root_via_at, at_err := element_at(&r, "")
	testing.expect_value(t, at_err, Error.OK)

	root_direct := root_element(&r)
	testing.expect_value(t, root_via_at, root_direct)
}

@(test)
test_array_elements :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"items": [10, 20, 30]}`))
	testing.expect_value(t, err, Error.OK)

	elems, elems_err := array_elements(&r, "items")
	testing.expect_value(t, elems_err, Error.OK)
	testing.expect_value(t, len(elems), 3)

	v0, _ := read_int_elem(&r, elems[0], "")
	testing.expect_value(t, v0, 10)

	v1, _ := read_int_elem(&r, elems[1], "")
	testing.expect_value(t, v1, 20)

	v2, _ := read_int_elem(&r, elems[2], "")
	testing.expect_value(t, v2, 30)
}

@(test)
test_array_elements_from :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"data": {"values": [1, 2, 3]}}`))
	testing.expect_value(t, err, Error.OK)

	data_elem, _ := element_at(&r, "data")
	values_elem, values_err := obj_element_from(&r, data_elem, "values")
	testing.expect_value(t, values_err, Error.OK)

	elems, elems_err := array_elements_from(&r, values_elem)
	testing.expect_value(t, elems_err, Error.OK)
	testing.expect_value(t, len(elems), 3)
}

@(test)
test_obj_element_from :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"outer": {"inner": {"value": 42}}}`))
	testing.expect_value(t, err, Error.OK)

	outer, _ := element_at(&r, "outer")
	inner, inner_err := obj_element_from(&r, outer, "inner")
	testing.expect_value(t, inner_err, Error.OK)

	value, value_err := read_int_elem(&r, inner, "value")
	testing.expect_value(t, value_err, Error.OK)
	testing.expect_value(t, value, 42)
}

@(test)
test_array_element_from :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"items": ["a", "b", "c"]}`))
	testing.expect_value(t, err, Error.OK)

	items, _ := element_at(&r, "items")
	second, second_err := array_element_from(&r, items, 1)
	testing.expect_value(t, second_err, Error.OK)

	val, val_err := read_string_elem(&r, second, "")
	testing.expect_value(t, val_err, Error.OK)
	testing.expect_value(t, val, "b")
}

@(test)
test_read_elem_all_types :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	json := `{
		"str": "hello",
		"num": 42,
		"big": 9007199254740991,
		"flt": 3.14,
		"yes": true,
		"no": false
	}`
	err := parse(&r, transmute([]byte)json)
	testing.expect_value(t, err, Error.OK)

	root := root_element(&r)

	str, _ := read_string_elem(&r, root, "str")
	testing.expect_value(t, str, "hello")

	num, _ := read_int_elem(&r, root, "num")
	testing.expect_value(t, num, 42)

	big, _ := read_i64_elem(&r, root, "big")
	testing.expect_value(t, big, i64(9007199254740991))

	flt, _ := read_f64_elem(&r, root, "flt")
	testing.expect(t, flt > 3.13 && flt < 3.15, "expected ~3.14")

	yes, _ := read_bool_elem(&r, root, "yes")
	testing.expect_value(t, yes, true)

	no, _ := read_bool_elem(&r, root, "no")
	testing.expect_value(t, no, false)
}

@(test)
test_array_of_objects_elem :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	json := `{"users": [{"name": "alice", "age": 30}, {"name": "bob", "age": 25}]}`
	err := parse(&r, transmute([]byte)json)
	testing.expect_value(t, err, Error.OK)

	users, _ := array_elements(&r, "users")
	testing.expect_value(t, len(users), 2)

	name0, _ := read_string_elem(&r, users[0], "name")
	testing.expect_value(t, name0, "alice")
	age0, _ := read_int_elem(&r, users[0], "age")
	testing.expect_value(t, age0, 30)

	name1, _ := read_string_elem(&r, users[1], "name")
	testing.expect_value(t, name1, "bob")
	age1, _ := read_int_elem(&r, users[1], "age")
	testing.expect_value(t, age1, 25)
}

@(test)
test_nested_array_elem :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	json := `{"matrix": [[1, 2], [3, 4], [5, 6]]}`
	err := parse(&r, transmute([]byte)json)
	testing.expect_value(t, err, Error.OK)

	rows, _ := array_elements(&r, "matrix")
	testing.expect_value(t, len(rows), 3)

	cols, _ := array_elements_from(&r, rows[1])
	testing.expect_value(t, len(cols), 2)

	v0, _ := read_int_elem(&r, cols[0], "")
	testing.expect_value(t, v0, 3)

	v1, _ := read_int_elem(&r, cols[1], "")
	testing.expect_value(t, v1, 4)
}

@(test)
test_element_not_found :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"a": 1}`))
	testing.expect_value(t, err, Error.OK)

	_, elem_err := element_at(&r, "missing")
	testing.expect_value(t, elem_err, Error.Key_Not_Found)

	root := root_element(&r)
	_, obj_err := obj_element_from(&r, root, "missing")
	testing.expect_value(t, obj_err, Error.Key_Not_Found)
}

@(test)
test_element_type_mismatch :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)string(`{"str": "hello", "num": 42}`))
	testing.expect_value(t, err, Error.OK)

	str_elem, _ := element_at(&r, "str")

	_, arr_err := array_elements_from(&r, str_elem)
	testing.expect_value(t, arr_err, Error.Type_Mismatch)

	_, obj_err := obj_element_from(&r, str_elem, "x")
	testing.expect_value(t, obj_err, Error.Type_Mismatch)
}

@(test)
test_string_to_number_coercion :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(
		&r,
		transmute([]byte)string(`{"price": "0.55", "quantity": "123", "rate": "3.14159"}`),
	)
	testing.expect_value(t, err, Error.OK)

	price, price_err := read_f64(&r, "price")
	testing.expect_value(t, price_err, Error.OK)
	testing.expect_value(t, price, 0.55)

	quantity, qty_err := read_i64(&r, "quantity")
	testing.expect_value(t, qty_err, Error.OK)
	testing.expect_value(t, quantity, 123)

	qty_int, qty_int_err := read_int(&r, "quantity")
	testing.expect_value(t, qty_int_err, Error.OK)
	testing.expect_value(t, qty_int, 123)

	root := root_element(&r)
	rate, rate_err := read_f64_elem(&r, root, "rate")
	testing.expect_value(t, rate_err, Error.OK)
	testing.expect(t, rate > 3.14 && rate < 3.15, "rate should be approximately 3.14159")
}

@(test)
test_string_to_number_coercion_in_array :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(
		&r,
		transmute([]byte)string(
			`{"items": [{"price": "1.5", "size": "100"}, {"price": "2.5", "size": "200"}]}`,
		),
	)
	testing.expect_value(t, err, Error.OK)

	elems, elems_err := array_elements(&r, "items")
	testing.expect_value(t, elems_err, Error.OK)
	testing.expect_value(t, len(elems), 2)

	price1, p1_err := read_f64_elem(&r, elems[0], "price")
	testing.expect_value(t, p1_err, Error.OK)
	testing.expect_value(t, price1, 1.5)

	size1, s1_err := read_i64_elem(&r, elems[0], "size")
	testing.expect_value(t, s1_err, Error.OK)
	testing.expect_value(t, size1, 100)

	price2, p2_err := read_f64_elem(&r, elems[1], "price")
	testing.expect_value(t, p2_err, Error.OK)
	testing.expect_value(t, price2, 2.5)
}

@(test)
test_string_to_bool_coercion :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(
		&r,
		transmute([]byte)string(
			`{"enabled": "true", "disabled": "false", "one": "1", "zero": "0"}`,
		),
	)
	testing.expect_value(t, err, Error.OK)

	enabled, e1 := read_bool(&r, "enabled")
	testing.expect_value(t, e1, Error.OK)
	testing.expect_value(t, enabled, true)

	disabled, e2 := read_bool(&r, "disabled")
	testing.expect_value(t, e2, Error.OK)
	testing.expect_value(t, disabled, false)

	one, e3 := read_bool(&r, "one")
	testing.expect_value(t, e3, Error.OK)
	testing.expect_value(t, one, true)

	zero, e4 := read_bool(&r, "zero")
	testing.expect_value(t, e4, Error.OK)
	testing.expect_value(t, zero, false)

	root := root_element(&r)
	enabled_elem, e5 := read_bool_elem(&r, root, "enabled")
	testing.expect_value(t, e5, Error.OK)
	testing.expect_value(t, enabled_elem, true)
}

@(test)
test_simd_whitespace_boundaries :: proc(t: ^testing.T) {
	ws_counts := [?]int{0, 1, 15, 16, 17, 32, 33}
	for n in ws_counts {
		r: Reader
		init_reader(&r)
		defer destroy_reader(&r)

		ws := strings.repeat(" ", n)
		defer delete(ws)
		json := strings.concatenate({ws, `{"v":1}`, ws})
		defer delete(json)

		err := parse(&r, transmute([]byte)json)
		testing.expectf(t, err == .OK, "failed with %d spaces: %v", n, err)

		val, val_err := read_int(&r, "v")
		testing.expectf(t, val_err == .OK, "read failed with %d spaces", n)
		testing.expectf(t, val == 1, "wrong value with %d spaces: %v", n, val)
	}
}

@(test)
test_simd_number_boundaries :: proc(t: ^testing.T) {
	numbers := [?]string {
		"1",
		"123456789012345",
		"1234567890123456",
		"12345678901234567",
		"12345678901234567890",
	}
	for num in numbers {
		r: Reader
		init_reader(&r)
		defer destroy_reader(&r)

		json := strings.concatenate({`{"n":`, num, `}`})
		defer delete(json)

		err := parse(&r, transmute([]byte)json)
		testing.expectf(t, err == .OK, "failed parsing number len %d: %v", len(num), err)
	}
}

@(test)
test_simd_string_boundaries :: proc(t: ^testing.T) {
	str_lens := [?]int{14, 15, 16, 17, 31, 32, 33}
	for n in str_lens {
		r: Reader
		init_reader(&r)
		defer destroy_reader(&r)

		s := strings.repeat("a", n)
		defer delete(s)
		json := strings.concatenate({`{"k":"`, s, `"}`})
		defer delete(json)

		err := parse(&r, transmute([]byte)json)
		testing.expectf(t, err == .OK, "failed with string len %d: %v", n, err)

		val, val_err := read_string(&r, "k")
		testing.expectf(t, val_err == .OK, "read failed with string len %d", n)
		testing.expectf(t, len(val) == n, "wrong string len: got %d expected %d", len(val), n)
	}
}

@(test)
test_simd_string_escape_boundaries :: proc(t: ^testing.T) {
	escape_positions := [?]int{13, 14, 15, 16, 17}
	for pos in escape_positions {
		r: Reader
		init_reader(&r)
		defer destroy_reader(&r)

		prefix := strings.repeat("a", pos)
		defer delete(prefix)
		json := strings.concatenate({`{"k":"`, prefix, `\"end"}`})
		defer delete(json)

		err := parse(&r, transmute([]byte)json)
		testing.expectf(t, err == .OK, "failed with escape at pos %d: %v", pos, err)
	}
}

@(test)
test_dense_array_buffer_growth :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	strings.write_byte(&b, '[')
	for i in 0 ..< 50_000 {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_int(&b, i & 9)
	}
	strings.write_byte(&b, ']')

	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)strings.to_string(b))
	testing.expect_value(t, err, Error.OK)

	n, len_err := array_len(&r, "")
	testing.expect_value(t, len_err, Error.OK)
	testing.expect_value(t, n, 50_000)

	last, last_err := read_int(&r, "49999")
	testing.expect_value(t, last_err, Error.OK)
	testing.expect_value(t, last, 49_999 & 9)
}

@(test)
test_dense_object_buffer_growth :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	strings.write_byte(&b, '{')
	for i in 0 ..< 20_000 {
		if i > 0 {
			strings.write_byte(&b, ',')
		}
		strings.write_string(&b, `"k`)
		strings.write_int(&b, i)
		strings.write_string(&b, `":`)
		strings.write_int(&b, i)
	}
	strings.write_byte(&b, '}')

	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)strings.to_string(b))
	testing.expect_value(t, err, Error.OK)

	v, v_err := read_int(&r, "k19999")
	testing.expect_value(t, v_err, Error.OK)
	testing.expect_value(t, v, 19_999)
}

@(test)
test_scratch_overflow_chunks :: proc(t: ^testing.T) {
	b: strings.Builder
	strings.builder_init(&b)
	defer strings.builder_destroy(&b)
	strings.write_string(&b, `{"big":"`)
	for _ in 0 ..< 3000 {
		strings.write_string(&b, `a\n`)
	}
	strings.write_string(&b, `"}`)

	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	err := parse(&r, transmute([]byte)strings.to_string(b))
	testing.expect_value(t, err, Error.OK)

	for _ in 0 ..< 10 {
		v, v_err := read_string(&r, "big")
		testing.expect_value(t, v_err, Error.OK)
		testing.expect_value(t, len(v), 6000)
	}

	err = parse(&r, transmute([]byte)strings.to_string(b))
	testing.expect_value(t, err, Error.OK)
	v, v_err := read_string(&r, "big")
	testing.expect_value(t, v_err, Error.OK)
	testing.expect_value(t, len(v), 6000)
}

@(test)
test_read_after_failed_parse :: proc(t: ^testing.T) {
	r: Reader
	init_reader(&r)
	defer destroy_reader(&r)

	ok_err := parse(&r, transmute([]byte)string(`{"value": 1}`))
	testing.expect_value(t, ok_err, Error.OK)

	bad_err := parse(&r, transmute([]byte)string(`{"value": `))
	testing.expect(t, bad_err != .OK, "expected parse to fail")

	_, read_err := read_int(&r, "value")
	testing.expect_value(t, read_err, Error.Not_Parsed)

	_, elem_err := element_at(&r, "")
	testing.expect_value(t, elem_err, Error.Not_Parsed)

	recover_err := parse(&r, transmute([]byte)string(`{"value": 3}`))
	testing.expect_value(t, recover_err, Error.OK)
	v, v_err := read_int(&r, "value")
	testing.expect_value(t, v_err, Error.OK)
	testing.expect_value(t, v, 3)
}

@(test)
test_parse_int_key_ranges :: proc(t: ^testing.T) {
	Case :: struct {
		key:      string,
		expected: i64,
		ok:       bool,
	}

	u8_cases := []Case{{"0", 0, true}, {"255", 255, true}, {"256", 0, false}, {"-1", 0, false}}
	for c in u8_cases {
		v, ok := parse_int_key(u8, c.key)
		testing.expect_value(t, ok, c.ok)
		testing.expect_value(t, i64(v), c.ok ? c.expected : 0)
	}

	i8_cases := []Case{{"-128", -128, true}, {"127", 127, true}, {"128", 0, false}, {"-129", 0, false}}
	for c in i8_cases {
		v, ok := parse_int_key(i8, c.key)
		testing.expect_value(t, ok, c.ok)
		testing.expect_value(t, i64(v), c.ok ? c.expected : 0)
	}

	max_u64, max_u64_ok := parse_int_key(u64, "18446744073709551615")
	testing.expect_value(t, max_u64_ok, true)
	testing.expect_value(t, max_u64, max(u64))

	_, wrap_ok := parse_int_key(u64, "18446744073709551616")
	testing.expect_value(t, wrap_ok, false)

	min_i64, min_i64_ok := parse_int_key(i64, "-9223372036854775808")
	testing.expect_value(t, min_i64_ok, true)
	testing.expect_value(t, min_i64, min(i64))

	_, under_ok := parse_int_key(i64, "-9223372036854775809")
	testing.expect_value(t, under_ok, false)

	_, hex_ok := parse_int_key(int, "0x10")
	testing.expect_value(t, hex_ok, false)

	_, plus_ok := parse_int_key(int, "+7")
	testing.expect_value(t, plus_ok, false)

	_, empty_ok := parse_int_key(int, "")
	testing.expect_value(t, empty_ok, false)

	_, dash_ok := parse_int_key(int, "-")
	testing.expect_value(t, dash_ok, false)

	zeros, zeros_ok := parse_int_key(int, "007")
	testing.expect_value(t, zeros_ok, true)
	testing.expect_value(t, zeros, 7)
}

@(test)
test_writer_u64_and_int_keys :: proc(t: ^testing.T) {
	w: Writer
	init_writer(&w)
	defer destroy_writer(&w)

	write_object_start(&w)
	write_key_u64(&w, max(u64))
	write_u64(&w, max(u64))
	write_key_i64(&w, min(i64))
	write_int(&w, min(int))
	write_key_i64(&w, 0)
	write_u64(&w, 0)
	write_object_end(&w)

	expected := `{"18446744073709551615":18446744073709551615,"-9223372036854775808":-9223372036854775808,"0":0}`
	testing.expect_value(t, writer_string(&w), expected)
}
