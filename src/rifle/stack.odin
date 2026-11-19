package rifle

import "base:runtime"

// !NOT THREADSAFE! (Doesn't need to be)
Stack :: struct($T: typeid) {
	top:  i64,
	data: []T,
}

stack_init :: proc(stack: ^Stack($T), size: i64) -> RifleError {
	err: runtime.Allocator_Error
	stack.data, err = make([]T, size, context.allocator)
	if err != nil {
		return .AllocatorError
	}
	stack.top = 0
	return nil
}

stack_deinit :: proc(stack: ^Stack($T)) -> RifleError {
	err := delete(stack.data)
	if err != nil {
		return .AllocatorError
	}
	return nil
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
