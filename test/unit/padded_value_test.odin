package unit

import "core:testing"
import rifle "rifle:rifle"

@(test)
given_padded_values_when_stored_in_array_then_each_value_starts_on_requested_alignment :: proc(t: ^testing.T) {
	// Arrange
	values: [2]rifle.paddedValue(i64, 128)

	// Act
	first_address := uintptr(&values[0])
	second_address := uintptr(&values[1])

	// Assert
	testing.expect_value(t, align_of(rifle.paddedValue(i64, 128)), 128)
	testing.expect_value(t, size_of(rifle.paddedValue(i64, 128)), 128)
	testing.expect_value(t, first_address % 128, uintptr(0))
	testing.expect_value(t, second_address - first_address, uintptr(128))
}
