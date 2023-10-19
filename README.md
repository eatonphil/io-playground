# IO Playground

## Write ~400MB to one file

### Go

To run:

```
$ go run main.go 2>&1 | tee out.csv
$ duckdb -c "select column0 as method, avg(column1::double) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as avg_throughput from 'out.csv' group by column0 order by avg(column1::double) asc"
```

And observe:

```
┌────────────────────────────────────────────┬──────────────────────┬────────────────┐
│                   method                   │       avg_time       │ avg_throughput │
│                  varchar                   │       varchar        │    varchar     │
├────────────────────────────────────────────┼──────────────────────┼────────────────┤
│ 1_goroutines_pwrite                        │ 0.2854128s           │ 1.4GB/s        │
│ blocking                                   │ 0.28881369999999995s │ 1.4GB/s        │
│ 10_goroutines_pwrite                       │ 0.32212419999999997s │ 1.2GB/s        │
│ 10_goroutines_io_uring_pwrite_128_entries  │ 0.3520878s           │ 1.1GB/s        │
│ 100_goroutines_io_uring_pwrite_128_entries │ 0.36614690000000005s │ 1.1GB/s        │
│ 1_goroutines_io_uring_pwrite_128_entries   │ 0.41654559999999996s │ 984.3MB/s      │
│ 100_goroutines_io_uring_pwrite_1_entries   │ 0.4171275s           │ 982.3MB/s      │
│ 10_goroutines_io_uring_pwrite_1_entries    │ 0.538555s            │ 775.8MB/s      │
│ 1_goroutines_io_uring_pwrite_1_entries     │ 1.9181275s           │ 215.1MB/s      │
└────────────────────────────────────────────┴──────────────────────┴────────────────┘
```

### Zig

Identical methods, basically similar results.

To run:

```
$ zig build-exe main.zig
$ ./main
$ duckdb -c "select column0 as method, avg(column1::double) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as avg_throughput from 'out.csv' group by column0 order by avg(column1::double) asc"
```

And observe:

```
┌────────────────────────────────────────┬──────────────────────┬────────────────┐
│                 method                 │       avg_time       │ avg_throughput │
│                varchar                 │       varchar        │    varchar     │
├────────────────────────────────────────┼──────────────────────┼────────────────┤
│ 1_threads_pwrite                       │ 0.2640253184s        │ 1.5GB/s        │
│ blocking                               │ 0.2717205943s        │ 1.5GB/s        │
│ 1_threads_iouring_pwrite_128_entries   │ 0.3057609942s        │ 1.3GB/s        │
│ 10_threads_pwrite                      │ 0.318430708s         │ 1.2GB/s        │
│ 10_threads_iouring_pwrite_128_entries  │ 0.332900983s         │ 1.2GB/s        │
│ 100_threads_iouring_pwrite_128_entries │ 0.348642789s         │ 1.1GB/s        │
│ 10_threads_iouring_pwrite_1_entries    │ 0.42450315789999993s │ 965.0MB/s      │
│ 100_threads_iouring_pwrite_1_entries   │ 0.43977728650000003s │ 931.9MB/s      │
│ 1_threads_iouring_pwrite_1_entries     │ 0.7284202819999999s  │ 566.6MB/s      │
└────────────────────────────────────────┴──────────────────────┴────────────────┘
```

### Python

To run:

```
$ python3 main.py
$ duckdb -c "select column0 as method, avg(column1::double) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as avg_throughput from 'out.csv' group by column0 order by avg(column1::double) asc"
```

```
┌──────────┬──────────────────────┬────────────────┐
│  method  │       avg_time       │ avg_throughput │
│ varchar  │       varchar        │    varchar     │
├──────────┼──────────────────────┼────────────────┤
│ blocking │ 0.36418720000000004s │ 1.1GB/s        │
└──────────┴──────────────────────┴────────────────┘
```
