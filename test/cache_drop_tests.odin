package test

import "core:testing"
import rifle "rifle:rifle"

@(test)
cache_drop_unlinks_whole_files_with_stable_paths :: proc(t: ^testing.T) {
	f: Fake_IO
	pc := new(rifle.PageCache)
	durable: i64
	extra_require(t, rifle.cache_init(pc, 256, 64, fake_io(&f), "/tmp/rifle-drop/", 256, 6, &durable) == nil)
	defer rifle.cache_deinit(pc)
	// Record 42 starts at byte 252: file zero is still partially retained.
	rifle.cache_drop(pc, 42)
	testing.expect(t, pc.drop_index == 0)
	rifle.cache_poll(pc)
	testing.expect(t, len(f.requests) == 0)
	rifle.cache_drop(pc, 43)
	testing.expect(t, pc.drop_index == 1)
	f.next_error = .FileNotReady
	rifle.cache_poll(pc)
	testing.expect(t, len(f.requests) == 0 && pc.last_file_index == 0)
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 1)
	testing.expect(t, f.requests[0].user_data.op == .DELETE)
	testing.expect(t, f.requests[0].file.id == 0)
	testing.expect(t, string(f.requests[0].file.path) == "/tmp/rifle-drop/data_0.rfl")
	// A larger drop must not overwrite the outstanding request's pathname.
	rifle.cache_drop(pc, 100)
	testing.expect(t, pc.drop_index == 2)
	rifle.cache_drop(pc, 43)
	testing.expect(t, pc.drop_index == 2) // Older requests cannot move it backwards.
	rifle.cache_poll(pc)
	testing.expect(t, len(f.requests) == 1)
	testing.expect(t, string(f.requests[0].file.path) == "/tmp/rifle-drop/data_0.rfl")
	fake_io_complete(&f, 0, -5)
	rifle.cache_poll(pc)
	testing.expect(t, pc.last_file_index == 0)
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 1)
	testing.expect(t, f.requests[0].file.id == 0)
	fake_io_complete(&f, 0, 0)
	rifle.cache_poll(pc)
	rifle.cache_poll(pc)
	extra_require(t, len(f.requests) == 1)
	testing.expect(t, f.requests[0].file.id == 1)
	testing.expect(t, string(f.requests[0].file.path) == "/tmp/rifle-drop/data_1.rfl")
	fake_io_complete(&f, 0, -2) // Already absent.
	rifle.cache_poll(pc)
	rifle.cache_poll(pc)
	testing.expect(t, pc.last_file_index == 2)
	testing.expect(t, len(f.requests) == 0) // File two contains the retained boundary.
}
