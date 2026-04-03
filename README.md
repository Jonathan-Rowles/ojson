# ojson

**SIMD-accelerated, lazy JSON field extraction for the [Odin programming language](https://odin-lang.org/).**

ojson parses JSON lazily: it walks the full document to index structure and positions, but defers type conversion and string unescaping until you read a field. SIMD-accelerated string and number scanning. Includes a code generator for type-safe unmarshalling and marshalling.

## Features

- Lazy parsing with deferred type conversion
- SIMD-accelerated string and number scanning
- Reusable reader that amortizes allocation across many messages
- Code generation for struct unmarshalling and marshalling
- `omitempty` support for skipping zero-valued fields during marshal

## Installation
```bash
# Add as a submodule or copy to your project
git clone https://github.com/jonathan-rowles/ojson
```

## Usage

### Reusable Reader

For parsing many messages:

```odin
import oj "ojson"

r: oj.Reader
oj.init_reader(&r)
defer oj.destroy(&r)

for msg in messages {
    oj.parse(&r, msg)

    name, _ := oj.read_string(&r, "users.0.name")

    items, _ := oj.array_elements(&r, "items")
    for item in items {
        price, _ := oj.read_f64_elem(&r, item, "price")
    }
}
```

### One-shot

For single lookups:

```odin
name, _ := oj.get_string(data, "user.name")
```

### Code Generation

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
- **Unions**
