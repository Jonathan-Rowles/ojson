# ojson

[![CI](https://github.com/Jonathan-Rowles/ojson/actions/workflows/ci.yml/badge.svg)](https://github.com/Jonathan-Rowles/ojson/actions/workflows/ci.yml)

**A fast, SIMD-accelerated JSON parser for the [Odin programming language](https://odin-lang.org/), built for lazy field extraction.**

- Lazy parsing: structure is indexed up front, type conversion and unescaping happen when you read a field
- SIMD-accelerated string and number scanning
- Reusable reader that amortizes allocation across many messages
- Non-allocating iteration over arrays and object key/value pairs
- Code generation for struct unmarshalling and marshalling

## When to use ojson over `core:encoding/json`

Use **ojson** when you read a few known fields per message, process a stream of
messages through one reusable `Reader`, or need steady-state parsing that does
not allocate. Strings come back as views into the input, so there is nothing to
free.

Use **`core:encoding/json`** when you query one document repeatedly, need the
parsed data to outlive the input buffer, or want `unmarshal` with no build
step. ojson's strings and `Element` handles are invalidated by the next
`parse`.

See [`benchmark/`](benchmark/) for the numbers.

## Installation

```bash
# Add as a submodule or copy to your project
git clone https://github.com/jonathan-rowles/ojson
```

## Usage

### Reusable reader

```odin
import oj "ojson"

r: oj.Reader
oj.init_reader(&r)
defer oj.destroy(&r)

for msg in messages {
    if oj.parse(&r, msg) != .OK do continue

    name, _ := oj.read_string(&r, "users.0.name")
    fmt.println(name)

    items, _ := oj.array_iter(&r, "items")
    for item in oj.next(&items) {
        price, _ := oj.read_f64(&r, item, "price")
        fmt.println(price)
    }
}
```

Reads and navigation procs accept a path from the root, a named field of an
`Element`, or an `Element` itself:

```odin
by_path,  _ := oj.read_f64(&r, "book.bids.0.price")
by_field, _ := oj.read_f64(&r, level, "amount")
by_value, _ := oj.read_f64(&r, cell)
```

### Iteration

`array_iter` and `object_iter` walk containers without allocating;
`array_elements` and `object_keys` return slices when you need one to keep.
Keys come back raw, so decode escapes with `unescape_string` (free when there
are none).

```odin
it := oj.object_iter(&r, elem)
for raw_key, value in oj.next(&it) {
    key := oj.unescape_string(&r, raw_key)
    fmt.println(key, oj.element_value_type(&r, value))
}
```

`Element` handles and returned strings point into the reader and are
invalidated by the next `parse`; debug builds assert on stale use. A failed
`parse` leaves the reader empty: every read returns `.Not_Parsed` until the
next successful `parse`.

### One-shot

```odin
name, _ := oj.get_string(data, "user.name")
defer delete(name)
```

`get_string` clones the value so it outlives the temporary reader; the caller
owns it.

### Building JSON

`write` resolves on the value type, and on arity for key/value pairs. Floats
use shortest round-trip formatting; NaN and infinity are written as `null`.
`write_u64` covers unsigned values above `i64` range, and `write_key_i64` /
`write_key_u64` write integer object keys.

```odin
w: oj.Writer
oj.init(&w)
defer oj.destroy(&w)

oj.write_object_start(&w)
oj.write(&w, "name", "Alice")
oj.write(&w, "age", 30)
oj.write(&w, "score", 3.25)
oj.write_key(&w, "tags")
oj.write_array_start(&w)
oj.write(&w, "a")
oj.write(&w, "b")
oj.write_array_end(&w)
oj.write_object_end(&w)

fmt.println(oj.writer_string(&w)) // {"name":"Alice","age":30,"score":3.25,"tags":["a","b"]}
```

### Code generation

```odin
// types.odin
Item :: struct {
    name:  string `json:"name"`,
    price: f64    `json:"price"`,
}

Order :: struct {
    id:    i64       `json:"id"`,
    items: []Item    `json:"items"`,
    note:  string    `json:"note,omitempty"`,
}
```

```bash
make generate SRC=../myproject/types
```

Generates both `unmarshal_*` and `marshal_*` procs for each struct:

```odin
import oj "ojson"
import oj_gen "ojson/gen"

r: oj.Reader
oj.init_reader(&r)
defer oj.destroy(&r)

// Unmarshal
oj.parse(&r, data)
order, err := oj_gen.unmarshal_order(&r)

// Marshal
w: oj.Writer
oj.init(&w)
defer oj.destroy(&w)
oj_gen.marshal_order(&w, order)
result := oj.writer_string(&w)
```

### Field types

```odin
Status :: enum { Idle = 0, Active = 7 }
Entity_ID :: distinct int

Profile :: struct {
    name:     string            `json:"name"`,
    address:  ^Address          `json:"address"`,
    labels:   map[string]string `json:"labels"`,
    by_state: map[Status]int    `json:"by_state"`,
    links:    []Entity_ID       `json:"links,omitempty"`,
}
```

- Strings, numbers, bools, nested structs, tagged unions, slices, dynamic and
  fixed arrays.
- `omitempty` drops a field from marshal output at its zero value.
- `^T` is optional: a missing key, `null` or mistyped value leaves it `nil`,
  anything else is allocated with `new` and owned by the caller. Marshal
  writes `null`, or drops the field under `omitempty`.
- `map[K]V` is a JSON object with string, integer or enum keys. Integer keys
  are range-checked, and an entry with a non-numeric or out-of-range key or a
  mistyped value is skipped. Marshal uses Odin's map iteration order.
- An enum is its integer value; a distinct type reads and writes as its base
  type. Both work as fields, in containers, behind pointers and as map values,
  resolved across every scanned file.
- A field the generator cannot express is skipped with a warning at generation
  time and a `TODO` comment in the output, which still compiles: containers of
  containers, pointers inside containers, distinct types from non-primitives,
  and map keys beyond string/integer/enum.
