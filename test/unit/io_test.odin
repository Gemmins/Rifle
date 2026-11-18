package unit

import "core:testing"
import rifle "rifle:rifle"

@(test)
given_io_user_data_fields_when_packed_then_each_field_round_trips_without_overlap :: proc(t: ^testing.T) {
	// Arrange
	original := rifle.IOUserData{
		page_index = (1 << 24) - 1,
		reserved = (1 << 12) - 1,
		op = .HEADER,
		payload = (1 << 24) - 1,
	}

	// Act
	packed := cast(u64)original
	unpacked := cast(rifle.IOUserData)packed

	// Assert
	testing.expect_value(t, size_of(rifle.IOUserData), 8)
	testing.expect_value(t, unpacked, original)
}

@(test)
given_io_completion_when_created_then_result_and_request_token_are_independent :: proc(t: ^testing.T) {
	// Arrange
	token := rifle.IOUserData{page_index = 42, op = .WRITE, payload = 99}

	// Act
	completion := rifle.IOCompletion{user_data = token, res = -5}

	// Assert
	testing.expect_value(t, completion.user_data, token)
	testing.expect_value(t, completion.res, i32(-5))
}
