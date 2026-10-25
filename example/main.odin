package main

import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:thread"
import "core:time"
import rifle "rifle:rifle"

RECORD_SIZE :: 128
RECORDS_PER_BLOCK :: 1 << 12
BLOCKS_PER_FILE :: 1 << 10
CACHE_SIZE_IN_BLOCKS :: 1 << 6
MAX_OPEN_FILES :: 64
RECORDS_PER_THREAD :: 1 << 24
N_THREADS :: 1
LOG_PATH :: "./example/idk"

Thread_Data :: struct {
	m: ^rifle.Log_old,
}

write_thread :: proc(t: ^thread.Thread) {
	data := cast(^Thread_Data)t.data
	a, _ := runtime.make_aligned([]u8, RECORD_SIZE, RECORD_SIZE)
	append_errs := 0
	for i in 0 ..< RECORDS_PER_THREAD {
		d := i
		copy(a[0:], mem.ptr_to_bytes(&d))
		_, err := rifle.log_append(data.m, a)
		if err != rifle.RifleError.None {
			append_errs += 1
		}
	}
	if append_errs > 0 {
		fmt.println("[writer] append errors:", append_errs)
	}
}

bench_single :: proc(l: ^rifle.Log_old) {
	a, _ := runtime.make_aligned([]u8, RECORD_SIZE, RECORD_SIZE)
	count1 := 0
	start := time.now()._nsec
	for i in 0 ..< RECORDS_PER_THREAD {
		d := i
		copy(a[0:], mem.ptr_to_bytes(&d))
		rifle.log_append(l, a)
		count1 += i
	}
	end := time.now()._nsec
	fmt.println("write:", end - start)

	start = time.now()._nsec
	count: i64 = 0
	for i in 0 ..< RECORDS_PER_THREAD {
		rifle.log_read_index(l, a, cast(i64)i)
		j := cast(^i64)raw_data(a)
		count += j^
	}
	end = time.now()._nsec
	fmt.println("read: ", end - start)
	fmt.println(count)
	fmt.println(count1)
}

bench_multi :: proc(l: ^rifle.Log_old, n: int) {
	thread_data := make([]Thread_Data, n)
	threads := make([]^thread.Thread, n)
	defer delete(thread_data)
	defer delete(threads)

	for i in 0 ..< n {
		thread_data[i] = {
			m = l,
		}
	}

	start := time.now()._nsec
	for i in 0 ..< n {
		t := thread.create(write_thread)
		t.data = &thread_data[i]
		threads[i] = t
		thread.start(t)
	}
	for t in threads {
		thread.join(t)
		thread.destroy(t)
	}
	end := time.now()._nsec
	fmt.println("write:", end - start)

	fmt.println("head after writes:", rifle.log_head_index(l))

	a, _ := runtime.make_aligned([]u8, RECORD_SIZE, RECORD_SIZE)
	total_records := n * RECORDS_PER_THREAD
	start = time.now()._nsec
	count: i64 = 0
	read_errs := 0
	zero_reads := 0
	for i in 0 ..< total_records {
		(cast(^i64)raw_data(a))^ = -1
		err := rifle.log_read_index(l, a, cast(i64)i)
		if err != rifle.RifleError.None {
			read_errs += 1
			continue
		}
		j := cast(^i64)raw_data(a)
		if j^ == 0 do zero_reads += 1
		count += j^
	}
	end = time.now()._nsec
	fmt.println("read: ", end - start)
	fmt.println("read errs:", read_errs)
	fmt.println("zero reads:", zero_reads)

	per_thread_sum := i64(RECORDS_PER_THREAD) * i64(RECORDS_PER_THREAD - 1) / 2
	expected := i64(n) * per_thread_sum
	fmt.println("sum:     ", count)
	fmt.println("expected:", expected)
}

main :: proc() {
	l, err := rifle.log_create(LOG_PATH, RECORD_SIZE, RECORDS_PER_BLOCK, BLOCKS_PER_FILE, CACHE_SIZE_IN_BLOCKS, MAX_OPEN_FILES)

	if err != nil {
		fmt.printfln("Error creating log: %v", err)
	}

	time.sleep(time.Second)

	// bench_single(l)
	bench_multi(l, N_THREADS)

	rifle.log_destroy(l)
}
