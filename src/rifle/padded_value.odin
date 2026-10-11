package rifle

paddedValue :: struct($T: typeid) #align (64) {
	value: T,
	_:     [64 - size_of(T)]u8,
}
