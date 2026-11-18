package rifle

paddedValue :: struct($T: typeid, $alignment: int) #align (alignment) {
	value: T,
	_:     [alignment - size_of(T)]u8,
}
