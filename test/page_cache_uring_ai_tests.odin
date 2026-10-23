#+build linux

package test

import "core:fmt"
import "core:os"
import "core:slice"
import "core:sync"
import "core:sys/linux"
import "core:sys/linux/uring"
import "core:testing"
import "core:time"
import rifle "rifle:rifle"

ai_real_cache :: proc(t: ^testing.T, dir: string, durable: ^i64, record_size, pages_per_file: i64, cache_pages: i64 = 4) -> rifle.Cache {
	testing.set_fail_timeout(t, 15 * time.Second)
	io := rifle.new_uring_io({uring.DEFAULT_PARAMS, 16, u64(pages_per_file * PAGE_SIZE)}, linux.AT_FDCWD)
	c := rifle.new_page_cache()
	extra_require(t, c.init(c.data, cache_pages * PAGE_SIZE, PAGE_SIZE, io, dir, pages_per_file * PAGE_SIZE, durable) == nil)
	pc := cast(^rifle.PageCache)c.data
	pc.record_size = record_size
	return c
}

ai_real_cache_flush :: proc(t: ^testing.T, c: rifle.Cache, target: i64) {
	pc := cast(^rifle.PageCache)c.data
	start := time.now()
	// Only request durability once all resident writes have completed.
	for {
		_, err := c.poll(c.data)
		extra_require(t, err == nil)
		pending := false
		for p in pc.pages {
			pending = pending || p.state == .Dirty || p.state == .Flushing
		}
		if !pending {break}
		extra_require(t, time.since(start) < 5 * time.Second)
	}
	c.sync(c.data, target)
	for sync.atomic_load(pc.durable_index) != target {
		_, err := c.poll(c.data)
		extra_require(t, err == nil)
		extra_require(t, time.since(start) < 5 * time.Second)
	}
	testing.expect(t, !pc.sync_in_progress)
}

@(test)
cache_uring_sync_and_cold_read :: proc(t: ^testing.T) {
	dir, err := os.make_directory_temp("/tmp", "rifle-cache-roundtrip-*", context.allocator)
	extra_require(t, err == nil)
	defer delete(dir)
	defer os.remove_all(dir)
	durable: i64 = -1
	// 24-byte records straddle both 4096-byte pages and 8192-byte files.
	data: [3 * PAGE_SIZE]u8
	for &b, i in data {b = u8((i * 17 + i / PAGE_SIZE * 31) % 251)}
	{
		c := ai_real_cache(t, dir, &durable, 24, 2, cache_pages = 8)
		defer c.deinit(c.data)
		c.write(c.data, data[:171 * 24], 0, 171)
		c.write(c.data, data[171 * 24:], 171, 341)
		ai_real_cache_flush(t, c, 512)
		testing.expect_value(t, durable, i64(512))
	}
	// Check file placement independently of the cache's read mapping.
	for file_id in 0 ..< 2 {
		path := fmt.aprintf("%s/data_%d.rfl", dir, file_id)
		defer delete(path)
		disk, read_err := os.read_entire_file(path, context.allocator)
		extra_require(t, read_err == nil)
		defer delete(disk)
		begin := file_id * 2 * PAGE_SIZE
		end := min(begin + 2 * PAGE_SIZE, len(data))
		extra_require(t, len(disk) >= end - begin)
		testing.expect(t, slice.equal(disk[:end - begin], data[begin:end]))
	}
	// A new cache and ring must open the files and load their pages from disk.
	c := ai_real_cache(t, dir, &durable, 24, 2, cache_pages = 8)
	defer c.deinit(c.data)
	output: [3 * PAGE_SIZE]u8
	c.read(c.data, output[:], 0, 512)
	testing.expect(t, output == data)
	subrange: [176 * 24]u8
	c.read(c.data, subrange[:], 169, 176)
	testing.expect(t, slice.equal(subrange[:], data[169 * 24:345 * 24]))
}

@(test)
cache_uring_evict_and_reload :: proc(t: ^testing.T) {
	dir, err := os.make_directory_temp("/tmp", "rifle-cache-eviction-*", context.allocator)
	extra_require(t, err == nil)
	defer delete(dir)
	defer os.remove_all(dir)
	durable: i64 = -1
	c := ai_real_cache(t, dir, &durable, 64, 4)
	defer c.deinit(c.data)
	data: [8 * PAGE_SIZE]u8
	for &b, i in data {b = u8((i * 7 + i / PAGE_SIZE * 19) % 251)}
	// Eight pages through a four-page cache force flushing and eviction.
	for page in 0 ..< 8 {
		c.write(c.data, data[page * PAGE_SIZE:(page + 1) * PAGE_SIZE], i64(page * 64), 64)
	}
	ai_real_cache_flush(t, c, 512)
	pc := cast(^rifle.PageCache)c.data
	for p in pc.pages {testing.expect(t, p.index != 0)}
	output: [PAGE_SIZE]u8
	for page in 0 ..< 8 {
		c.read(c.data, output[:], i64(page * 64), 64)
		testing.expect(t, slice.equal(output[:], data[page * PAGE_SIZE:(page + 1) * PAGE_SIZE]))
	}
	for p in pc.pages {
		testing.expect(t, p.state == .Clean && p.ref_count == 0)
	}
	testing.expect_value(t, durable, i64(512))
}
