To run:


```
go run main.go 2>&1 | tee out.csv && duckdb -c "select column0 as method, avg(cast(column1 as double)) || 's' avg_time, format_bytes(avg(column2::double)::bigint) || '/s' as throughput from 'out.csv' group by column0"
```

And observe:

```
┌───────────────────────────────────────────┬───────────────────────┬────────────┐
│                  method                   │       avg_time        │ throughput │
│                  varchar                  │        varchar        │  varchar   │
├───────────────────────────────────────────┼───────────────────────┼────────────┤
│ 10_goroutines_io_uring_pwrite_1_entry     │ 0.1633701s            │ 2.5GB/s    │
│ 10_goroutines_io_uring_pwrite_100_entries │ 0.0394018s            │ 10.4GB/s   │
│ buf                                       │ 0.257824s             │ 1.5GB/s    │
│ 10_goroutines_pwrite                      │ 0.025590199999999997s │ 16.0GB/s   │
│ nobuf                                     │ 0.2549947s            │ 1.6GB/s    │
└───────────────────────────────────────────┴───────────────────────┴────────────┘
```
