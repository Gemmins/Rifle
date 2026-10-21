package test

import "core:sys/linux"
import "core:testing"
import "rifle:rifle"
@(test)
page_cache_init :: proc(t: ^testing.T) { 	//TODO: Finish
	pc: rifle.PageCache
	dir_path: cstring = "/tmp"
	dirfd, err := linux.open(dir_path, {.DIRECTORY, .PATH}, {})
	assert(err == .NONE)
	io := rifle.new_uring_io({}, dirfd)
	durable_index: i64
	_ = rifle.cache_init(&pc, 1 << 20, 1 << 13, io, base_path = string(dir_path), file_size = 1 << 30, durable_index = &durable_index)
	linux.close(dirfd)
	rifle.cache_delete(&pc)
}
