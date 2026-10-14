package test

import "core:testing"
import "rifle:rifle"

@(test)
page_cache_init :: proc(t: ^testing.T) {
	pc: rifle.PageCache
	rifle.page_cache_init(&pc, 1 << 20)
}
