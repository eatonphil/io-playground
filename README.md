# IO Playground

The point of this repo is to get an intuition about different IO
models. Comparing across languages isn't for benchmark wars it's more
a check for correctness. The relative difference between IO models
should be similar across language.

## Machine

I am running these tests on a dedicated bare metal instance, [OVH
Rise-1](https://eco.us.ovhcloud.com/#filterType=range_element&filterValue=rise).

* RAM: 64 GB DDR4 ECC 2,133 MHz
* Disk: 2x450 GB SSD NVMe in Soft RAID
* Processor: Intel Xeon E3-1230v6 - 4c/8t - 3.5 GHz/3.9 GHz
* `uname --kernel-release`: 6.3.8-100.fc37.x86_64

## Write 1GiB to one file (4KiB buffer)

Each implementation (other than `dd`) produces a CSV of results. Use
the following DuckDB command to analyze it.

```
$ duckdb -c "
  SELECT
    column0 AS method,
	AVG(column1::DOUBLE) || 's' avg_time,
	FORMAT_BYTES(AVG(column2::DOUBLE)::BIGINT) || '/s' AS avg_throughput
  FROM 'out.csv'
  GROUP BY column0
  ORDER BY AVG(column1::DOUBLE) ASC"
```

### `dd` (Control)

```
$ dd if=/dev/zero of=test.bin bs=4k count=1M
1048576+0 records in
1048576+0 records out
4294967296 bytes (4.3 GB, 4.0 GiB) copied, 3.09765 s, 1.4 GB/s
```

### Go

This version reads up to N entries but then blocks until all N entries
complete. This is not ideal. But I'm not sure Iceber/iouring-go
supports anything else.

First:

```
$ go run main.go | tee out.csv
```

Then run the DuckDB command from above:

```
┌────────────────────────────────────────────┬─────────────────────┬────────────────┐
│                   method                   │      avg_time       │ avg_throughput │
│                  varchar                   │       varchar       │    varchar     │
├────────────────────────────────────────────┼─────────────────────┼────────────────┤
│ 1_goroutines_pwrite                        │ 0.7111268999999999s │ 1.5GB/s        │
│ blocking                                   │ 0.7128968s          │ 1.5GB/s        │
│ 1_goroutines_io_uring_pwrite_128_entries   │ 1.0402713s          │ 1.0GB/s        │
│ 10_goroutines_pwrite                       │ 1.111215s           │ 966.2MB/s      │
│ 100_goroutines_io_uring_pwrite_128_entries │ 1.3004915000000001s │ 825.6MB/s      │
│ 100_goroutines_io_uring_pwrite_1_entries   │ 1.5118257s          │ 710.2MB/s      │
│ 10_goroutines_io_uring_pwrite_128_entries  │ 1.5322980999999998s │ 771.6MB/s      │
│ 10_goroutines_io_uring_pwrite_1_entries    │ 1.6577722000000001s │ 648.1MB/s      │
│ 1_goroutines_io_uring_pwrite_1_entries     │ 4.705483s           │ 228.2MB/s      │
└────────────────────────────────────────────┴─────────────────────┴────────────────┘
```

### Zig

Unlike the Go implementation, this version does not batch only/always
N entries at a time. It starts out batching N entries at a time but
*does not block* waiting for all N to complete. Instead it just reads
what has completed and keeps trying to add more entry batches.

First:

```
$ zig build-exe main.zig
$ ./main | tee out.csv
```

Then run the DuckDB command from above:

```
┌────────────────────────────────────────┬─────────────────────┬────────────────┐
│                 method                 │      avg_time       │ avg_throughput │
│                varchar                 │       varchar       │    varchar     │
├────────────────────────────────────────┼─────────────────────┼────────────────┤
│ 1_threads_iouring_pwrite_128_entries   │ 0.6080365773999998s │ 1.7GB/s        │
│ 1_threads_iouring_pwrite_1_entries     │ 0.6259650676999999s │ 1.7GB/s        │
│ blocking                               │ 0.6740227804s       │ 1.5GB/s        │
│ 1_threads_pwrite                       │ 0.6846085126999999s │ 1.5GB/s        │
│ 10_threads_pwrite                      │ 1.1549885629000003s │ 929.8MB/s      │
│ 10_threads_iouring_pwrite_1_entries    │ 2.4174379148s       │ 445.7MB/s      │
│ 10_threads_iouring_pwrite_128_entries  │ 2.4178504731s       │ 445.8MB/s      │
│ 100_threads_iouring_pwrite_128_entries │ 3.6317807736s       │ 296.6MB/s      │
│ 100_threads_iouring_pwrite_1_entries   │ 3.7681755905000003s │ 287.7MB/s      │
└────────────────────────────────────────┴─────────────────────┴────────────────┘
```

### Python

First:

```
$ python3 main.py | tee out.csv
```

Then run the DuckDB command from above:

```
┌──────────┬────────────┬────────────────┐
│  method  │  avg_time  │ avg_throughput │
│ varchar  │  varchar   │    varchar     │
├──────────┼────────────┼────────────────┤
│ blocking │ 0.9259369s │ 1.1GB/s        │
└──────────┴────────────┴────────────────┘
```
