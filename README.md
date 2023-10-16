To run:


```
go run main.go 2>&1 | tee out.csv && duckdb -c "select column0 as method, avg(cast(column1 as double)) avg_time, format_bytes(avg(column2::double)::bigint) as kb_per_sec from 'out.csv' group by column0"
```

And observe:

```
┌───────────────────────────────────────────┬──────────────────────┬────────────┐
│                  method                   │       avg_time       │ kb_per_sec │
│                  varchar                  │        double        │  varchar   │
├───────────────────────────────────────────┼──────────────────────┼────────────┤
│ 10_goroutines_io_uring_pwrite_1_entry     │            0.1633701 │ 2.5GB      │
│ 10_goroutines_io_uring_pwrite_100_entries │            0.0394018 │ 10.4GB     │
│ buf                                       │             0.257824 │ 1.5GB      │
│ 10_goroutines_pwrite                      │ 0.025590199999999997 │ 16.0GB     │
│ nobuf                                     │            0.2549947 │ 1.6GB      │
└───────────────────────────────────────────┴──────────────────────┴────────────┘
```
