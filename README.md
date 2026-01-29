# ojson

**SIMD-accelerated, lazy JSON field extraction for the [Odin programming language](https://odin-lang.org/).**

ojson lets you extract fields from JSON without fully deserializing the document. Includes a code generator for type-safe unmarshalling.

## Features

- Fast field extraction without full parse
- Reusable reader for parsing many messages
- Code generation for struct unmarshalling
- Zero dependencies

## Installation
```bash
# Add as a submodule or copy to your project
git clone https://github.com/jonathan-rowles/ojson
```

## Usage

## Reusable Reader

For parsing many messages:

```odin
import oj "ojson"

reader := oj.init_reader()
defer oj.destroy(&reader)

for msg in messages {
    oj.parse(&reader, msg)

    name, _ := oj.read_string(&reader, "users.0.name")

    items, _ := oj.array_elements(&reader, "items")
    for item in items {
        price, _ := oj.read_f64_elem(&reader, item, "price")
    }
}
```

## One-shot

For single lookups:

```odin
name, _ := oj.get_string(data, "user.name")
```

## Code Generation

```odin
// types.odin
Item :: struct {
    name:  string `json:"name"`,
    price: f64    `json:"price"`,
}

Order :: struct {
    id:    i64       `json:"id"`,
    items: []Item    `json:"items"`,
    tags:  [5]string `json:"tags"`,
}
```

```bash
make generate SRC=../myproject/types
```

```odin
import oj "ojson"
import oj_gen "ojson/gen"

oj.parse(&reader, data)
order, err := oj_gen.unmarshal_order(&reader)
```
