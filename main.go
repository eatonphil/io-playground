package main

import (
	"bytes"
	"fmt"
	"os"
	"sync"
	"syscall"
	"time"

	"github.com/iceber/iouring-go"
)

func assert(b bool) {
	if !b {
		panic("assert")
	}
}

func readNBytes(fn string, n int) []byte {
	f, err := os.Open(fn)
	if err != nil {
		panic(err)
	}
	defer f.Close()

	buf := make([]byte, 0, n)

	var chunk = make([]byte, 4096)
	for len(buf) < n {
		read, err := f.Read(chunk)
		if err != nil {
			panic(err)
		}

		buf = append(buf, chunk[:read]...)
	}

	assert(len(buf) == n)

	return buf
}

func benchmark(name string, directIO bool, x []byte, fn func(*os.File)) {
	fmt.Printf("%s", name)
	flags := os.O_RDWR | os.O_CREATE | os.O_TRUNC
	if directIO {
		flags |= syscall.O_DIRECT
	}
	f, err := os.OpenFile("out.bin", flags, 0755)
	if err != nil {
		panic(err)
	}

	t1 := time.Now()

	fn(f)

	s := time.Now().Sub(t1).Seconds()
	fmt.Printf(",%f,%f\n", s, float64(len(x))/s)

	if err := f.Close(); err != nil {
		panic(err)
	}

	assert(bytes.Equal(readNBytes("out.bin", len(x)), x))
}

func withPwriteAndWorkerRoutines(directIO bool, x []byte, workers int) {
	name := fmt.Sprintf("%d_goroutines_pwrite", workers)
	benchmark(name, directIO, x, func(f *os.File) {
		chunkSize := 4096
		var wg sync.WaitGroup

		workSize := len(x) / workers

		for i := 0; i < len(x); i += workSize {
			wg.Add(1)
			go func(i int) {
				defer wg.Done()

				for j := i; j < i+workSize; j += chunkSize {
					size := min(chunkSize, (i+workSize)-j)
					n, err := f.WriteAt(x[j:j+size], int64(j))
					if err != nil {
						panic(err)
					}

					assert(n == chunkSize)
				}
			}(i)
		}
		wg.Wait()
	})
}

func withIOUringAndWorkerRoutines(directIO bool, x []byte, entries int, workers int) {
	name := fmt.Sprintf("%d_goroutines_io_uring_pwrite_%d_entries", workers, entries)
	benchmark(name, directIO, x, func(f *os.File) {
		chunkSize := 4096

		var wg sync.WaitGroup
		workSize := len(x) / workers

		for i := 0; i < len(x); i += workSize {
			wg.Add(1)
			go func(i int) {
				requests := make([]iouring.PrepRequest, entries)
				iour, err := iouring.New(uint(entries))
				if err != nil {
					panic(err)
				}
				defer iour.Close()

				defer wg.Done()

				for j := i; j < i+workSize; j += chunkSize * entries {
					for k := 0; k < entries; k++ {
						base := j + k*chunkSize
						if base >= i+workSize {
							break
						}
						size := min(chunkSize, (i+workSize)-base)
						requests[k] = iouring.Pwrite(int(f.Fd()), x[base:base+size], uint64(base))
					}

					res, err := iour.SubmitRequests(requests[:], nil)
					if err != nil {
						panic(err)
					}
					<-res.Done()

					for _, result := range res.ErrResults() {
						n, err := result.ReturnInt()
						if err != nil {
							panic(err)
						}

						assert(n == chunkSize)
					}
				}
			}(i)
		}
		wg.Wait()
	})
}

func main() {
	size := 4096 * 100_000
	x := readNBytes("/dev/random", size)

	var directIO = false
	for _, arg := range os.Args {
		if arg == "--directio" {
			directIO = true
		}
	}

	for i := 0; i < 10; i++ {
		// No buffering
		benchmark("blocking", directIO, x, func(f *os.File) {
			chunkSize := 4096
			for i := 0; i < len(x); i += chunkSize {
				size := min(chunkSize, len(x)-i)
				n, err := f.Write(x[i : i+size])
				if err != nil {
					panic(err)
				}

				assert(n == chunkSize)
			}
		})

		withPwriteAndWorkerRoutines(directIO, x, 1)
		withPwriteAndWorkerRoutines(directIO, x, 10)

		withIOUringAndWorkerRoutines(directIO, x, 1, 10)
		withIOUringAndWorkerRoutines(directIO, x, 128, 10)
		withIOUringAndWorkerRoutines(directIO, x, 1, 100)
		withIOUringAndWorkerRoutines(directIO, x, 128, 100)
		withIOUringAndWorkerRoutines(directIO, x, 1, 1)
		withIOUringAndWorkerRoutines(directIO, x, 128, 1)
	}
}
