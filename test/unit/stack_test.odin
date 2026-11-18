package unit

import "base:runtime"
import "core:testing"
import rifle "rifle:rifle"

@(test)
given_empty_stack_when_popped_then_reports_no_value :: proc(t: ^testing.T) {
	// Arrange
	stack: rifle.Stack(i32)
	_ = rifle.stack_init(&stack, 2)
	defer rifle.stack_deinit(&stack)

	// Act
	value, ok := rifle.stack_pop(&stack)

	// Assert
	testing.expect(t, !ok)
	testing.expect_value(t, value, i32(0))
}

@(test)
given_values_when_pushed_and_popped_then_stack_is_lifo :: proc(t: ^testing.T) {
	// Arrange
	stack: rifle.Stack(i32)
	_ = rifle.stack_init(&stack, 3)

	// Act
	first_pushed := rifle.stack_push(&stack, 10)
	second_pushed := rifle.stack_push(&stack, 20)
	first, first_ok := rifle.stack_pop(&stack)
	second, second_ok := rifle.stack_pop(&stack)

	// Assert
	testing.expect(t, first_pushed)
	testing.expect(t, second_pushed)
	testing.expect(t, first_ok)
	testing.expect(t, second_ok)
	testing.expect_value(t, first, i32(20))
	testing.expect_value(t, second, i32(10))

	rifle.stack_deinit(&stack)
}

@(test)
given_full_stack_when_another_value_is_pushed_then_existing_values_are_unchanged :: proc(t: ^testing.T) {
	// Arrange
	stack: rifle.Stack(i32)
	_ = rifle.stack_init(&stack, 1)
	defer rifle.stack_deinit(&stack)
	_ = rifle.stack_push(&stack, 10)

	// Act
	pushed := rifle.stack_push(&stack, 20)
	value, ok := rifle.stack_pop(&stack)

	// Assert
	testing.expect(t, !pushed)
	testing.expect(t, ok)
	testing.expect_value(t, value, i32(10))
}

@(test)
given_non_empty_stack_when_peeked_then_top_is_returned_without_removal :: proc(t: ^testing.T) {
	// Arrange
	stack: rifle.Stack(i32)
	_ = rifle.stack_init(&stack, 2)
	defer rifle.stack_deinit(&stack)
	_ = rifle.stack_push(&stack, 10)
	_ = rifle.stack_push(&stack, 20)

	// Act
	peeked, peek_ok := rifle.stack_peek(&stack)
	popped, pop_ok := rifle.stack_pop(&stack)

	// Assert
	testing.expect(t, peek_ok)
	testing.expect(t, pop_ok)
	testing.expect_value(t, peeked, i32(20))
	testing.expect_value(t, popped, i32(20))
}

@(test)
given_failing_allocator_when_stack_is_initialized_then_initialization_reports_failure :: proc(t: ^testing.T) {
	// Arrange
	stack: rifle.Stack(i32)
	original_allocator := context.allocator
	context.allocator = runtime.nil_allocator()

	// Act
	ok := rifle.stack_init(&stack, 4)
	context.allocator = original_allocator

	// Assert
	testing.expect(t, !ok)
	testing.expect_value(t, len(stack.data), 0)
}

@(test)
given_zero_capacity_stack_when_values_are_pushed_or_popped_then_it_remains_empty :: proc(t: ^testing.T) {
	// Arrange
	stack: rifle.Stack(i32)
	_ = rifle.stack_init(&stack, 0)
	defer rifle.stack_deinit(&stack)

	// Act
	pushed := rifle.stack_push(&stack, 10)
	value, popped := rifle.stack_pop(&stack)
	peeked, peek_ok := rifle.stack_peek(&stack)

	// Assert
	testing.expect(t, !pushed)
	testing.expect(t, !popped)
	testing.expect(t, !peek_ok)
	testing.expect_value(t, value, i32(0))
	testing.expect_value(t, peeked, i32(0))
}
