package rifle

import "base:runtime"
import "core:mem"
import "core:sync"

ASSOC :: 1 // FIXME: Temp fix

// TODO: rework
BlockCache :: struct {
	entries:    []Entry,
	blocks:     []Block,
	backing:    []u8,
	block_size: i64,
	mask:       i64,
}

Entry :: struct {
	block: ^Block,
	key:   i64,
	mu:    sync.Atomic_RW_Mutex,
}

block_cache_init :: proc(c: ^BlockCache, capacity, block_size: i64) -> runtime.Allocator_Error {
	entries_bytes := capacity * size_of(Entry)
	blocks_bytes := capacity * size_of(Block)
	c.backing = make([]u8, entries_bytes + blocks_bytes + capacity * block_size) or_return
	c.block_size = block_size
	c.entries = mem.slice_data_cast([]Entry, c.backing[:entries_bytes])
	c.blocks = mem.slice_data_cast([]Block, c.backing[entries_bytes:entries_bytes + blocks_bytes])
	pool := c.backing[entries_bytes + blocks_bytes:]
	for i in 0 ..< capacity {
		c.blocks[i].data = pool[i * block_size:(i + 1) * block_size]
		c.entries[i].block = &c.blocks[i]
	}
	c.mask = (capacity / ASSOC) - 1
	for i in 0 ..< capacity {
		c.entries[i].key = -1
	}
	return nil
}

block_cache_destroy :: proc(c: ^BlockCache) {
	delete(c.backing)
}

block_cache_get :: proc(c: ^BlockCache, key: i64, refs: i64 = 1) -> (block: ^Block, hit: bool) {
	base := (key & c.mask) * ASSOC

	add_extra_refs :: proc(e: ^Entry, refs: i64) {
		if refs > 1 {
			sync.atomic_add(&e.mu.state, sync.Atomic_RW_Mutex_State_Reader * sync.Atomic_RW_Mutex_State(refs - 1))
		}
	}

	for { 	// spin here needs to be looked at
		for i in base ..< base + ASSOC {
			e := &c.entries[i]
			if sync.atomic_load(&e.key) == key {
				if sync.try_shared_lock(&e.mu) {
					if e.key == key {
						add_extra_refs(e, refs)
						return e.block, true
					}
					sync.shared_unlock(&e.mu)
				}
			}
		}

		claim :: proc(e: ^Entry, key: i64, refs: i64) -> ^Block {
			if e.key != key {
				e.key = key
				sync.atomic_store(&e.block.loaded, 0)
			}
			sync.atomic_store(&e.block.loaded, 0)
			sync.atomic_store(&e.block.record_count, 0)
			sync.atomic_add(&e.mu.state, sync.Atomic_RW_Mutex_State_Reader * sync.Atomic_RW_Mutex_State(refs))
			sync.unlock(&e.mu)
			return e.block
		}

		oldest := base
		for i in base + 1 ..< base + ASSOC {
			if c.entries[i].key < c.entries[oldest].key {
				oldest = i
			}
		}

		if sync.try_lock(&c.entries[oldest].mu) {
			return claim(&c.entries[oldest], key, refs), false
		}
		for i in base ..< base + ASSOC {
			if i == oldest do continue
			if sync.try_lock(&c.entries[i].mu) {
				return claim(&c.entries[i], key, refs), false
			}
		}
	}
	// return claim(&c.entries[oldest], key), false
}

block_cache_release :: proc(c: ^BlockCache, key: i64) {
	base := (key & c.mask) * ASSOC
	for i in base ..< base + ASSOC {
		if e := &c.entries[i]; e.key == key {
			sync.shared_unlock(&e.mu)
			return
		}
	}
}

block_cache_release_n :: proc(c: ^BlockCache, key, count: i64) { 	// bit of a hack, rework writer claims
	base := (key & c.mask) * ASSOC
	for i in base ..< base + ASSOC {
		if e := &c.entries[i]; e.key == key {
			sync.atomic_sub(&e.mu.state, sync.Atomic_RW_Mutex_State(count - 1))
			sync.shared_unlock(&e.mu)
			return
		}
	}
}
