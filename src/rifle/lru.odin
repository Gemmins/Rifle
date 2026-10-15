package rifle

import "core:math/bits"

// 4 way lru - adapted from Hacker's Delight

lru :: u16

lru_new :: proc() -> lru {
	return 0x0137
}

lru_update :: proc(l: lru, i: u8) -> lru {
	l := l
	l |= (0xF << (4 * i))
	return l & ~(0x1111 << (3 - i))
}

lru_get_order :: proc(l: lru) -> (order: [4]u8) {
	l := l
	for i in u8(0) ..< 4 {
		rank := bits.count_ones(l & (0xF << (4 * i)))
		order[rank] = i
	}
	return order
}
