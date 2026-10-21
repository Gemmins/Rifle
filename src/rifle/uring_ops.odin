#+build linux

package rifle

import "core:sys/linux"
import "core:sys/linux/uring"

// Trying to get these ops upstreamed into odin core:sys/linux/uring

IO_Uring_Unlinkat_Flags :: bit_set[IO_Uring_Unlinkat_Flags_Bits;u32]

IO_Uring_Fallocate_Flags :: bit_set[IO_Uring_Fallocate_Flags_Bits;u32]

IO_Uring_Unlinkat_Flags_Bits :: enum {
	AT_REMOVEDIR = 9,
}

IO_Uring_Fallocate_Flags_Bits :: enum {
	FALLOC_FL_KEEP_SIZE,
	FALLOC_FL_PUNCH_HOLE,
	FALLOC_FL_NO_HIDE_STALE,
	FALLOC_FL_COLLAPSE_RANGE,
	FALLOC_FL_ZERO_RANGE,
	FALLOC_FL_INSERT_RANGE,
	FALLOC_FL_UNSHARE_RANGE,
	FALLOC_FL_WRITE_ZEROES,
}


read_fixed :: proc(ring: ^uring.Ring, user_data: u64, fd: linux.Fd, buf: []u8, offset: u64, buf_index: u16) -> (sqe: ^linux.IO_Uring_SQE, ok: bool) {
	sqe = uring.get_sqe(ring) or_return
	sqe.opcode = .READ_FIXED
	sqe.fd = fd
	sqe.addr = cast(u64)uintptr(raw_data(buf))
	sqe.len = u32(len(buf))
	sqe.off = offset
	sqe.buf_index = buf_index
	sqe.user_data = user_data

	ok = true
	return
}

fallocate :: proc(
	ring: ^uring.Ring,
	user_data: u64,
	fd: linux.Fd,
	mode: IO_Uring_Fallocate_Flags,
	offset: u64,
	len: u64,
) -> (
	sqe: ^linux.IO_Uring_SQE,
	ok: bool,
) {
	sqe = uring.get_sqe(ring) or_return
	sqe.opcode = .FALLOCATE
	sqe.fd = fd
	sqe.off = offset
	sqe.addr = len
	sqe.len = transmute(u32)mode
	sqe.user_data = user_data

	ok = true
	return
}

write_fixed :: proc(ring: ^uring.Ring, user_data: u64, fd: linux.Fd, buf: []u8, offset: u64, buf_index: u16) -> (sqe: ^linux.IO_Uring_SQE, ok: bool) {
	sqe = uring.get_sqe(ring) or_return
	sqe.opcode = .WRITE_FIXED
	sqe.fd = fd
	sqe.addr = cast(u64)uintptr(raw_data(buf))
	sqe.len = u32(len(buf))
	sqe.off = offset
	sqe.user_data = user_data
	sqe.buf_index = buf_index

	ok = true
	return
}

unlinkat :: proc(ring: ^uring.Ring, user_data: u64, dirfd: linux.Fd, path: cstring, flags: IO_Uring_Unlinkat_Flags) -> (sqe: ^linux.IO_Uring_SQE, ok: bool) {
	sqe = uring.get_sqe(ring) or_return
	sqe.opcode = .UNLINKAT
	sqe.fd = dirfd
	sqe.addr = transmute(u64)path
	sqe.unlink_flags = transmute(u32)flags
	sqe.user_data = user_data

	ok = true
	return
}
