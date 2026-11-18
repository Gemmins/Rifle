package rifle_c

import "base:runtime"
import rifle "rifle:rifle"


@(export)
rifle_log_default_config :: proc "c" (out_config: ^rifle.LogConfig) -> rifle.RifleError {
	if out_config == nil {
		return .InvalidArgError
	}
	out_config^ = rifle.DefaultLogConfig
	return nil
}

@(export)
rifle_log_init :: proc "c" (config: rifle.LogConfig, log_file: cstring, out_log: ^^rifle.Log) -> rifle.RifleError {
	context = runtime.default_context()
	if out_log == nil {
		return .InvalidArgError
	}
	out_log^ = nil
	log, err := rifle.log_init(config, log_file)
	if err == nil {
		out_log^ = log
	}
	return err
}

@(export)
rifle_log_deinit :: proc "c" (log: ^rifle.Log) -> rifle.RifleError {
	context = runtime.default_context()
	return rifle.log_deinit(log)
}

@(export)
rifle_log_read :: proc "c" (log: ^rifle.Log, buffer: [^]u8, buffer_size: uint, index: i64, count: i64) -> rifle.RifleError {
	context = runtime.default_context()
	return rifle.log_read(log, buffer[:int(buffer_size)], index, count)
}

@(export)
rifle_log_read_acquire :: proc "c" (log: ^rifle.Log, index: i64, count: i64, out_buf: ^[^]u8) -> rifle.RifleError {
	context = runtime.default_context()
	buf, err := rifle.log_read_acquire(log, index, count)
	if err != nil {
		out_buf^ = raw_data(buf)
	}
	return err
}

@(export)
rifle_log_read_release :: proc "c" (log: ^rifle.Log, index: i64) -> rifle.RifleError {
	context = runtime.default_context()
	return rifle.log_read_release(log, index)
}

@(export)
rifle_log_prefetch :: proc "c" (log: ^rifle.Log, index: i64, count: i64) -> rifle.RifleError {
	context = runtime.default_context()
	return rifle.log_prefetch(log, index, count)
}

@(export)
rifle_log_write :: proc "c" (log: ^rifle.Log, data: rawptr, data_size: uint, count: i64, out_index: ^i64) -> rifle.RifleError {
	out_index^ = -1
	context = runtime.default_context()
	index, err := rifle.log_write(log, ([^]u8)(data)[:int(data_size)], count)
	if err == nil {
		out_index^ = index
	}
	return err
}

@(export)
rifle_log_write_reserve :: proc "c" (log: ^rifle.Log, count: i64, out_index: ^i64, out_buf: ^[^]u8) -> rifle.RifleError {
	context = runtime.default_context()
	index, buf, err := rifle.log_write_reserve(log, count)
	if err == nil {
		out_index^ = index
		out_buf^ = raw_data(buf)
	}
	return err
}

@(export)
rifle_log_write_commit :: proc "c" (log: ^rifle.Log, index: i64) -> rifle.RifleError {
	context = runtime.default_context()
	return rifle.log_write_commit(log, index)
}

@(export)
rifle_log_drop :: proc "c" (log: ^rifle.Log, index: i64) -> rifle.RifleError {
	context = runtime.default_context()
	return rifle.log_drop(log, index)
}

@(export)
rifle_log_poll :: proc "c" (log: ^rifle.Log, out_progress: ^bool) -> rifle.RifleError {
	out_progress^ = false
	context = runtime.default_context()
	progress, err := rifle.log_poll(log)
	out_progress^ = progress
	return err
}

@(export)
rifle_log_sync :: proc "c" (log: ^rifle.Log, out_index: ^i64) -> rifle.RifleError {
	out_index^ = 0
	context = runtime.default_context()
	out_index^ = rifle.log_sync(log)
	return nil
}
