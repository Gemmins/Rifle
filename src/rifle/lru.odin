package rifle

import "core:math/bits"

// Little 4 way lru - found this in Hacker's Delight :)

lru :: u16

lru_new :: proc() -> lru {
	return 0b000000100110111
}

lru_update :: proc(l: lru, i: u8) -> lru {
	l := l
	l |= (0xf << (4 * i))
	return l & ~(0x1111 << (3 - i))
}

lru_get_order :: proc(l: lru) -> (order: [4]u8) {
	l := l
	for i in u8(0) ..< 4 {
		rank := bits.count_ones(l & (0xf << (4 * i)))
		order[rank] = i
	}
	return order
}
