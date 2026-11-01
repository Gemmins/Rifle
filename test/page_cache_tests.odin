package test

import "core:testing"
import "rifle:rifle"

@(test)
page_cache_init :: proc(t: ^testing.T) {
	pc := new(rifle.PageCache)
	f: Fake_IO
	durable_index: i64
	extra_require(t, rifle.cache_init(pc, 1 << 20, 1 << 13, fake_io(&f), base_path = "/tmp/rifle/", file_size = 1 << 30, record_size = 4, durable_index = &durable_index) == nil)
	defer rifle.cache_deinit(pc)
	testing.expect_value(t, pc.record_size, i64(4))
	testing.expect_value(t, pc.page_size, i64(1 << 13))
	testing.expect_value(t, pc.pages_per_file, i64(1 << 17))
	testing.expect_value(t, len(pc.pages), 128)
	testing.expect_value(t, len(pc.sets), 32)
	testing.expect_value(t, pc.base_path, "/tmp/rifle")
	testing.expect(t, pc.durable_index == &durable_index)
	testing.expect(t, raw_data(f.cache_buffer) == raw_data(pc.pageData))
	testing.expect_value(t, len(f.cache_buffer), 1 << 20)
	for p, i in pc.pages {
		testing.expect(t, p.index == -1 && p.state == .Empty && p.written_bytes == 0 && p.ref_count == 0)
		testing.expect_value(t, len(p.data), 1 << 13)
		testing.expect(t, raw_data(p.data) == &pc.pageData[i * (1 << 13)])
		testing.expect(t, p.path == cstring(raw_data(p.path_buffer)))
	}
	for set, i in pc.sets {
		testing.expect(t, raw_data(set.pages) == &pc.pages[i * rifle.SET_ASSOC])
		testing.expect_value(t, set.lru, rifle.lru_new())
	}
}
