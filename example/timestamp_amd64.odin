#+build amd64
package main

import "base:intrinsics"
import simd_x86 "core:simd/x86"
import "core:time"

rdtscp_is_supported :: proc "contextless" () -> bool {
	max_extended_leaf, _, _, _ := intrinsics.x86_cpuid(0x8000_0000, 0)
	if max_extended_leaf < 0x8000_0001 {
		return false
	}
	_, _, _, edx := intrinsics.x86_cpuid(0x8000_0001, 0)
	return edx & (1 << 27) != 0
}

timestamp_source_init :: proc "contextless" () -> Timestamp_Source {
	if rdtscp_is_supported() && time.has_invariant_tsc() {
		frequency, ok := time.tsc_frequency(100 * time.Millisecond)
		if ok && frequency > 0 {
			return {kind = .RDTSCP, ticks_per_second = frequency}
		}
	}
	return {kind = .Monotonic_Nanoseconds, ticks_per_second = 1_000_000_000}
}

@(enable_target_feature="sse2")
timestamp_now :: proc "contextless" (source: ^Timestamp_Source) -> (timestamp: u64, aux: u32) {
	if source.kind == .RDTSCP {
		timestamp = simd_x86.__rdtscp(&aux)
		// RDTSCP orders earlier loads; LFENCE prevents the measured operation
		// from beginning before the timestamp read has completed.
		simd_x86._mm_lfence()
		return
	}
	return u64(time.tick_now()._nsec), 0
}
