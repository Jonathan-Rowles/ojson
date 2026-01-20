# ojson

**SIMD-accelerated, lazy JSON field extraction for the [Odin programming language](https://odin-lang.org/).**

## Reusable Reader

```odin
import "ojson"

reader := ojson.init_reader()
defer ojson.destroy(&reader)

for msg in messages {
    ojson.parse(&reader, msg)
    price, _ := ojson.read_string(&reader, "0.price")
}
```

## One-shot

Convenience functions for single lookups. 

```odin
import "ojson"

name, _ := ojson.get_string(data, "user.name")
```

## Code Generation

Define structs with `json:` tags:

`types/user.odin`
```odin
User :: struct {
    name:  string `json:"name"`,
    email: string `json:"email"`,
    age:   int    `json:"age"`,
}
```

Generate unmarshal functions:

```bash
make generate SRC=./types 
```

Output 
`unmarshal.gen.odin`
```odin
unmarshal_user :: proc(r: ^Reader, prefix: string = "") -> (result: User, err: Error) {
	p := len(prefix) > 0 ? fmt.tprintf("%s.", prefix) : ""

	result.name, err = read_string(r, fmt.tprintf("%s%s", p, "name"))
	if err != .OK && err != .Key_Not_Found do return

	result.email, err = read_string(r, fmt.tprintf("%s%s", p, "email"))
	if err != .OK && err != .Key_Not_Found do return

	result.age, err = read_int(r, fmt.tprintf("%s%s", p, "age"))
	if err != .OK && err != .Key_Not_Found do return

	return
}
```

Use the generated code:

```odin
import "ojson"

reader := ojson.init_reader()
defer ojson.destroy(&reader)

ojson.parse(&reader, data)
user, err := ojson.unmarshal_user(&reader)
```
