package rifle

// !NOT THREADSAFE! (Doesn't need to be)
Stack :: struct($T: typeid) {
	top:  i64,
	data: []T,
}

stack_init :: proc(stack: ^Stack($T), size: i64) -> bool {
	stack.data, _ = make([]T, size, context.allocator)
	// if err != nil {
	// 	return false
	// }
	// TODO: check i guesss
	stack.top = 0
	return true
}

stack_deinit :: proc(stack: ^Stack($T)) {
	delete(stack.data)
}

stack_pop :: proc(stack: ^Stack($T)) -> (T, bool) {
	if stack.top < 1 {
		return {}, false
	}
	stack.top -= 1
	return stack.data[stack.top], true
}

stack_push :: proc(stack: ^Stack($T), element: T) -> bool {
	if stack.top >= cast(i64)len(stack.data) {
		return false
	}
	stack.data[stack.top] = element
	stack.top += 1
	return true
}

stack_peek :: proc(stack: ^Stack($T)) -> (T, bool) {
	if stack.top < 1 {
		return {}, false
	}
	return stack.data[stack.top - 1], true
}

stack_peek_all :: proc(stack: ^Stack($T)) -> []T {
	if stack.top == 0 {
		return nil
	}
	return stack.data[0:stack.top - 1]
}
