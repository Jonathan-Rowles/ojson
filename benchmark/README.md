# ojson benchmark

Measures ojson across four access patterns and three document shapes. Run from
the repo root:

```sh
make bench
```

`make bench` passes `-o:speed -microarch:native`.

## Cases

| case | what it measures |
|---|---|
| `parse` | parse the whole document, reusing one `Reader` |
| `extract` | parse, then read a few known fields by path |
| `access` | parse once, then read fields from every array element |
| `oneshot` | full setup, parse, read all fields and teardown, every call |

`parse`, `extract` and `oneshot` are the patterns ojson is built for. `access` is the opposite: it holds one parsed document and reads from it repeatedly, which is what a DOM parser is built for. It is here to keep that cost visible.

## Test data

`twitter.json`, `canada.json` and `citm_catalog.json` are the canonical [nativejson-benchmark](https://github.com/miloyip/nativejson-benchmark) files, also used by simdjson and RapidJSON. They cover string-heavy, number-heavy and large-nested shapes respectively.

## Results

Measured on an i9-11900K (Arch Linux, Odin dev-2026-04, `-o:speed
-microarch:x86-64-v3`). Each figure is the median of 5 trials.

| case | document | size | per-op | throughput |
|---|---|---:|---:|---:|
| `parse` | twitter.json | 616.7 KB | 266.96 µs | 2.4 GB/s |
| `parse` | canada.json | 2.1 MB | 1.32 ms | 1.7 GB/s |
| `parse` | citm_catalog.json | 1.6 MB | 704.62 µs | 2.5 GB/s |
| `extract` | twitter.json | 616.7 KB | 276.21 µs | 2.3 GB/s |
| `extract` | canada.json | 2.1 MB | 1.40 ms | 1.6 GB/s |
| `extract` | citm_catalog.json | 1.6 MB | 712.67 µs | 2.4 GB/s |
| `access` | twitter.json | 616.7 KB | 3.19 µs | - |
| `access` | citm_catalog.json | 1.6 MB | 5.65 µs | - |
| `oneshot` | small struct | 103 B | 228 ns | - |

Throughput is omitted for `access`, where no parsing happens inside the timed loop, and for `oneshot`, where the 103-byte payload makes it meaningless. The harness prints a trailing checksum so the optimiser cannot discard the work.
