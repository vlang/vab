// Copyright(C) 2023 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module paths

import os

pub const vab_namespace = 'vab'

const sanitized_exe_name = os.file_name(os.executable()).replace(' ', '_').replace('.exe',
	'').to_lower()

// ensure creates `path` if it does not already exist.
pub fn ensure(path string) ! {
	if !os.exists(path) {
		os.mkdir_all(path) or {
			return error('${@MOD}.${@FN}: error while making directory "${path}":\n${err}')
		}
	}
}

// data returns a `string` with the path to `vab`'s' data directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn data() string {
	return os.join_path(os.data_dir(), vab_namespace)
}

// config returns a `string` with the path to `vab`'s' configuration directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn config() string {
	return os.join_path(os.config_dir() or { panic('${@MOD}.${@FN}: ${err}') }, vab_namespace)
}

// tmp_work returns a `string` with the path to `vab`'s' temporary work directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn tmp_work() string {
	return os.join_path(os.temp_dir(), vab_namespace)
}

// cache returns a `string` with the path to `vab`'s' cache directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn cache() string {
	return os.join_path(os.cache_dir(), vab_namespace)
}

// exe_data returns a `string` with the path to the executable's data directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn exe_data() string {
	return os.join_path(os.data_dir(), sanitized_exe_name)
}

// exe_config returns a `string` with the path to the executable's configuration directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn exe_config() string {
	return os.join_path(os.config_dir() or { panic('${@MOD}.${@FN}: ${err}') }, sanitized_exe_name)
}

// exe_tmp_work returns a `string` with the path to the executable's temporary work directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn exe_tmp_work() string {
	return os.join_path(os.temp_dir(), sanitized_exe_name)
}

// exe_cache returns a `string` with the path to the executable's cache directory.
// NOTE: the returned path may not exist on disk. Use `ensure/1` to ensure it exists.
pub fn exe_cache() string {
	return os.join_path(os.cache_dir(), sanitized_exe_name)
}
