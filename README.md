# ojson

[![CI](https://github.com/Jonathan-Rowles/ojson/actions/workflows/ci.yml/badge.svg)](https://github.com/Jonathan-Rowles/ojson/actions/workflows/ci.yml)

**SIMD-accelerated, lazy JSON field extraction for the [Odin programming language](https://odin-lang.org/).**

ojson parses JSON lazily: it walks the full document to index structure and positions, but defers type conversion and string unescaping until you read a field. SIMD-accelerated string and number scanning. Includes a code generator for type-safe unmarshalling and marshalling.

## Features

- Lazy parsing with deferred type conversion
- SIMD-accelerated string and number scanning
- Reusable reader that amortizes allocation across many messages
- Non-allocating iteration over arrays and object key/value pairs
- Code generation for struct unmarshalling and marshalling
- `omitempty` support for skipping zero-valued fields during marshal

## When to use ojson over `core:encoding/json`

ojson never builds a document tree, so it is fast when you parse a message,
take the fields you need and move on. The standard library builds an owned
`json.Value` tree: a map allocation per object, but O(1) lookups afterwards.

Use **ojson** when you read a few known fields per message, process a stream of
messages through one reusable `Reader`, or need steady-state parsing that does
not allocate. Strings come back as views into the input, so there is nothing to
free.

Use **`core:encoding/json`** when you hold one parsed document and query it
repeatedly, need `map[K]V` or unknown object keys, want `unmarshal` with no
build step, or need the parsed data to outlive the input buffer. ojson's
strings and `Element` handles are invalidated by the next `parse`.

See [`benchmark/`](benchmark/) for the numbers.

## Installation

```bash
# Add as a submodule or copy to your project
git clone https://github.com/jonathan-rowles/ojson
```

## Building

Build with `-o:speed`. Odin defaults to `-o:minimal`, and to `-o:none` when
`-debug` is set. Measured on the benchmark, `-o:speed` is worth roughly 5x over
`-o:none` and 3.5x over `-o:minimal`.

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

    items, _ := oj.array_iter_at(&r, "items")
    for item in oj.next(&items) {
        price, _ := oj.read_f64(&r, item, "price")
        fmt.println(price)
    }
}
```

`read_string`, `read_int`, `read_i64`, `read_f64` and `read_bool` each take
three argument shapes:

```odin
by_path,  _ := oj.read_f64(&r, "book.bids.0.price") // value at a path
by_field, _ := oj.read_f64(&r, level, "amount")     // named field of an element
by_value, _ := oj.read_f64(&r, cell)                // the element's own value
```

Reads are marked `@(require_results)`, so the error return has to be handled or
explicitly discarded with `_`.

### Iteration

`array_iter` and `object_iter` walk containers without allocating.
`array_elements` and `object_keys` still exist for when you need a slice to
keep.

```odin
it := oj.object_iter(&r, elem)
for key, value in oj.next(&it) {
    fmt.println(key, oj.element_value_type(&r, value))
}
```

`Element` handles and returned strings point into the reader and are
invalidated by the next `parse`. Debug builds assert if you use a stale one.

### One-shot

```odin
name, _ := oj.get_string(data, "user.name")
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
w := oj.init_writer()
defer oj.destroy(&w)
oj_gen.marshal_order(&w, order)
result := oj.writer_string(&w)
```

Fields tagged with `omitempty` are skipped during marshal when they have their zero value (`""` for strings, `0` for numbers, `false` for bools, empty for slices).

## Not Yet Supported

The following types are not currently supported by the code generator:

- **Pointers (`^T`)**: detected by the parser but generated code won't compile
- **Maps (`map[K]V`)**
