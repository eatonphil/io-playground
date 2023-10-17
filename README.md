# IO Playground

## Write ~400MB to one file

### Go

To run:

```
$ go run main.go 2>&1 | tee out.csv
$ duckdb -c "select column0 as method, avg(column1::double) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as throughput from 'out.csv' group by column0 order by avg(column1::double) asc"
```

And observe:

```
┌────────────────────────────────────────────┬──────────────────────┬────────────┐
│                   method                   │       avg_time       │ throughput │
│                  varchar                   │       varchar        │  varchar   │
├────────────────────────────────────────────┼──────────────────────┼────────────┤
│ blocking                                   │ 0.2823283s           │ 1.4GB/s    │
│ 1_goroutine_pwrite                         │ 0.2881248s           │ 1.4GB/s    │
│ 10_goroutines_pwrite                       │ 0.32153139999999997s │ 1.2GB/s    │
│ 10_goroutines_io_uring_pwrite_128_entries  │ 0.3440831999999999s  │ 1.1GB/s    │
│ 100_goroutines_io_uring_pwrite_128_entries │ 0.36411150000000003s │ 1.1GB/s    │
│ 1_goroutines_io_uring_pwrite_128_entries   │ 0.41081460000000003s │ 999.3MB/s  │
│ 100_goroutines_io_uring_pwrite_1_entries   │ 0.4156378s           │ 986.4MB/s  │
│ 10_goroutines_io_uring_pwrite_1_entries    │ 0.5378928999999999s  │ 773.8MB/s  │
│ 1_goroutines_io_uring_pwrite_1_entries     │ 1.7859083999999998s  │ 229.4MB/s  │
└────────────────────────────────────────────┴──────────────────────┴────────────┘
```

### Zig

Identical methods, basically similar results.

To run:

```
$ zig build-exe main.zig
$ ./main
$ duckdb -c "select column0 as method, avg(column1::double) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as throughput from 'out.csv' group by column0 order by avg(column1::double) asc"
```

And observe:

```
┌────────────────────────────────────────┬──────────────────────┬────────────┐
│                 method                 │       avg_time       │ throughput │
│                varchar                 │       varchar        │  varchar   │
├────────────────────────────────────────┼──────────────────────┼────────────┤
│ blocking                               │ 0.2620964682s        │ 1.5GB/s    │
│ 1_threads_pwrite                       │ 0.2664669307s        │ 1.5GB/s    │
│ 10_threads_pwrite                      │ 0.3152884659s        │ 1.2GB/s    │
│ 1_threads_iouring_pwrite_128_entries   │ 0.332853636s         │ 1.2GB/s    │
│ 10_threads_iouring_pwrite_128_entries  │ 0.34393276060000005s │ 1.1GB/s    │
│ 100_threads_iouring_pwrite_128_entries │ 0.3554842698s        │ 1.1GB/s    │
│ 10_threads_iouring_pwrite_1_entries    │ 0.4295826038s        │ 953.7MB/s  │
│ 100_threads_iouring_pwrite_1_entries   │ 0.45531048200000007s │ 899.8MB/s  │
│ 1_threads_iouring_pwrite_1_entries     │ 0.7128790843s        │ 576.5MB/s  │
└────────────────────────────────────────┴──────────────────────┴────────────┘
```

### Python

To run:

```
$ python3 main.py
$ duckdb -c "select column0 as method, avg(column1::double) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as throughput from 'out.csv' group by column0 order by avg(column1::double) asc"
```

```
┌──────────┬────────────┬────────────┐
│  method  │  avg_time  │ throughput │
│ varchar  │  varchar   │  varchar   │
├──────────┼────────────┼────────────┤
│ blocking │ 0.3681182s │ 1.1GB/s    │
└──────────┴────────────┴────────────┘
```
