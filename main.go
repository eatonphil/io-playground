package main

import (
	"bytes"
	"fmt"
	"os"
	"sync"
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

func withIOUringAndWorkerRoutines(x []byte, entries int, workers int) {
	f, err := os.OpenFile("out.bin", os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0755)
	if err != nil {
		panic(err)
	}

	t1 := time.Now()
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

	s := time.Now().Sub(t1).Seconds()
	fmt.Printf("%d_goroutines_io_uring_pwrite_%d_entries,%f,%f\n", workers, entries, s, float64(len(x))/s)

	if err := f.Close(); err != nil {
		panic(err)
	}

	assert(bytes.Equal(readNBytes("out.bin", len(x)), x))
}

func main() {
	x := readNBytes("/dev/random", 4096*100_000)
	assert(len(x) == 4096*100_000)

	//fmt.Println("type,time")

	for i := 0; i < 10; i++ {
		// No buffering
		func() {
			f, err := os.OpenFile("out.bin", os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0755)
			if err != nil {
				panic(err)
			}

			t1 := time.Now()
			chunkSize := 4096
			for i := 0; i < len(x); i += chunkSize {
				n, err := f.Write(x[i : i+chunkSize])
				if err != nil {
					panic(err)
				}

				assert(n == chunkSize)
			}
			s := time.Now().Sub(t1).Seconds()
			fmt.Printf("blocking,%f,%f\n", s, float64(len(x))/s)

			if err := f.Close(); err != nil {
				panic(err)
			}

			assert(bytes.Equal(readNBytes("out.bin", len(x)), x))
		}()

		func() {
			f, err := os.OpenFile("out.bin", os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0755)
			if err != nil {
				panic(err)
			}

			t1 := time.Now()
			chunkSize := 4096
			for i := 0; i < len(x); i += chunkSize {
				n, err := f.WriteAt(x[i:i+chunkSize], int64(i))
				if err != nil {
					panic(err)
				}

				assert(n == chunkSize)
			}
			s := time.Now().Sub(t1).Seconds()
			fmt.Printf("1_goroutine_pwrite,%f,%f\n", s, float64(len(x))/s)

			if err := f.Close(); err != nil {
				panic(err)
			}

			assert(bytes.Equal(readNBytes("out.bin", len(x)), x))
		}()

		// With buffering
		// func () {
		// 	f_, err := os.OpenFile("out.bin", os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0755)
		// 	if err != nil {
		// 		panic(err)
		// 	}
		// 	f := bufio.NewWriter(f_)

		// 	t1 := time.Now()
		// 	chunkSize := 4096
		// 	for i := 0; i < len(x); i += chunkSize {
		// 		n, err := f.Write(x[i:i+chunkSize])
		// 		if err != nil {
		// 			panic(err)
		// 		}

		// 		assert(n == chunkSize)
		// 	}
		// 	f.Flush()
		// 	s := time.Now().Sub(t1).Seconds()
		// 	fmt.Printf("buf,%f,%f\n", s, float64(len(x))/s)

		// 	if err := f_.Close(); err != nil {
		// 		panic(err)
		// 	}

		// 	assert(bytes.Equal(readNBytes("out.bin", len(x)), x))
		// }()

		// With worker threads
		func() {
			f, err := os.OpenFile("out.bin", os.O_RDWR|os.O_CREATE|os.O_TRUNC, 0755)
			if err != nil {
				panic(err)
			}

			t1 := time.Now()
			chunkSize := 4096
			var wg sync.WaitGroup

			for i := 0; i < len(x); i += chunkSize * 10_000 {
				wg.Add(1)
				go func(i int) {
					defer wg.Done()

					for j := i; j < i+chunkSize*10_000; j += chunkSize {
						n, err := f.WriteAt(x[j:j+chunkSize], int64(j))
						if err != nil {
							panic(err)
						}

						assert(n == chunkSize)
					}
				}(i)
			}
			wg.Wait()
			s := time.Now().Sub(t1).Seconds()
			fmt.Printf("10_goroutines_pwrite,%f,%f\n", s, float64(len(x))/s)

			if err := f.Close(); err != nil {
				panic(err)
			}

			assert(bytes.Equal(readNBytes("out.bin", len(x)), x))
		}()

		withIOUringAndWorkerRoutines(x, 1, 10)
		withIOUringAndWorkerRoutines(x, 128, 10)
		withIOUringAndWorkerRoutines(x, 1, 100)
		withIOUringAndWorkerRoutines(x, 128, 100)
		withIOUringAndWorkerRoutines(x, 1, 1)
		withIOUringAndWorkerRoutines(x, 128, 1)
	}
}
