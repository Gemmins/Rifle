package test

import "core:testing"
import "core:sys/linux"
import rifle "rifle:rifle"

AI_Cache_Parent :: struct($Cache: typeid) {
	cache: Cache,
}

ai_cache_parent_poll :: proc(p: ^$P/AI_Cache_Parent) -> (bool, rifle.RifleError) {
	return P.Cache.poll(p.cache.data)
}

@(test)
cache_static_interface :: proc(t: ^testing.T) {
	durable_index: i64 = -1
	p := AI_Cache_Parent(rifle.Cache) {
		cache = rifle.new_page_cache(),
	}
	c := p.cache
	io := rifle.new_uring_io({num_files = 8, file_size = 8192}, linux.AT_FDCWD)
	extra_require(t, rifle.Cache.init(c.data, 16384, 4096, io, "/tmp/rifle", 8192, &durable_index) == nil)
	defer rifle.Cache.deinit(c.data)
	c.data.record_size = 4
	data: [16]u8
	for &b, i in data {b = u8(i)}
	rifle.Cache.write(c.data, data[:], 0, 4)
	read_back: [16]u8
	rifle.Cache.read(c.data, read_back[:], 0, 4)
	testing.expect(t, read_back == data)
	ai_cache_parent_poll(&p)
	// Partial pages stay in memory; an empty sync must still complete.
	rifle.Cache.sync(c.data, 0)
	polled, err := ai_cache_parent_poll(&p)
	testing.expect(t, polled && err == nil && durable_index == 0)
}
