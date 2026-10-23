#+build linux

package test

import "core:sys/linux/uring"
import "core:testing"
import "core:time"
import rifle "rifle:rifle"

@(test)
uring_overflow_without_new_submissions :: proc(t: ^testing.T) {
	s := setup_test_io(t)
	io := cast(^rifle.UringIO)s.io.data
	count := len(io.ring.cq.cqes) + 32
	start := time.now()
	// NOPs produce identifiable completions without file operations. READ tags
	// route them through the public completion path; no data is actually read.
	for i in 0 ..< count {
		ud := rifle.UringUserData{op = .READ, page_index = u32(i)}
		_, ok := uring.nop(&io.ring, cast(u64)ud)
		extra_require(t, ok)
		_, err := uring.submit(&io.ring, 0)
		extra_require(t, err == .NONE)
		for uring.sq_ready(&io.ring) != 0 {
			extra_require(t, time.since(start) < 5 * time.Second)
		}
	}
	for !uring.cq_ring_needs_flush(&io.ring) {
		extra_require(t, time.since(start) < 5 * time.Second)
	}
	extra_require(t, uring.sq_ready(&io.ring) == 0)
	seen := make([]bool, count)
	defer delete(seen)
	received := 0
	for received < count {
		n, err := s.io.poll(s.io.data, s.completions[:])
		extra_require(t, err == nil)
		for ce in s.completions[:n] {
			extra_require(t, ce.user_data.op == .READ && ce.res == 0)
			index := int(ce.user_data.page_index)
			extra_require(t, index < count && !seen[index])
			seen[index] = true
			received += 1
		}
		extra_require(t, time.since(start) < 5 * time.Second)
	}
	testing.expect(t, !uring.cq_ring_needs_flush(&io.ring))
}
