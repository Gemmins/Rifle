package unit

import "core:testing"
import rifle "rifle:rifle"

@(test)
given_new_lru_when_order_is_requested_then_all_slots_are_oldest_first :: proc(t: ^testing.T) {
	// Arrange
	lru := rifle.lru_new()

	// Act
	order := rifle.lru_get_order(lru)

	// Assert
	testing.expect_value(t, order, [4]u8{3, 2, 1, 0})
}

@(test)
given_lru_when_slot_is_updated_then_slot_becomes_most_recent :: proc(t: ^testing.T) {
	// Arrange
	lru := rifle.lru_new()

	// Act
	lru = rifle.lru_update(lru, 3)
	order := rifle.lru_get_order(lru)

	// Assert
	testing.expect_value(t, order, [4]u8{2, 1, 0, 3})
}

@(test)
given_lru_when_each_slot_is_updated_then_recency_order_matches_updates :: proc(t: ^testing.T) {
	// Arrange
	lru := rifle.lru_new()

	// Act
	lru = rifle.lru_update(lru, 1)
	lru = rifle.lru_update(lru, 3)
	lru = rifle.lru_update(lru, 0)
	order := rifle.lru_get_order(lru)

	// Assert
	testing.expect_value(t, order, [4]u8{2, 1, 3, 0})
}
