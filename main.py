import datetime

def read_n_bytes(fn, want):
    bytes = bytearray(want)
    with open(fn, "rb") as f:
        written = 0
        while written < want:
            chunk = f.read(4096)
            n = min(len(chunk), want - written)
            bytes[written:written + n] = chunk[:n]
            written += n

    assert len(bytes) == want
    return bytes

def main():
    x = read_n_bytes("/dev/random", 2**30)

    for _ in range(10):
        with open("out.bin", "wb") as f:
            t1 = datetime.datetime.now()

            i = 0
            while i < len(x):
                f.write(x[i:i+4096])
                i += 4096

            t2 = datetime.datetime.now()
            diff = (t2-t1).total_seconds()
            print(f"blocking,{diff},{len(x) / diff}")

main()
