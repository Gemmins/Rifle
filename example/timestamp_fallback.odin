#+build !amd64
package main

import "core:time"

timestamp_source_init :: proc "contextless" () -> Timestamp_Source {
	return {kind = .Monotonic_Nanoseconds, ticks_per_second = 1_000_000_000}
}

timestamp_now :: #force_inline proc "contextless" (source: ^Timestamp_Source) -> (timestamp: u64, aux: u32) {
	return u64(time.tick_now()._nsec), 0
}
