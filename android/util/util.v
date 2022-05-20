// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module util

import os
import szip
import cache

// Utility functions
pub fn find_sorted(path string) []string {
	mut dirs := []string{}
	mut files := os.ls(path) or { return dirs }
	for file in files {
		if os.is_dir(os.real_path(os.join_path(path, file))) {
			dirs << os.real_path(os.join_path(path, file))
		}
	}
	dirs.sort()
	dirs.reverse_in_place()
	return dirs
}

pub fn ls_sorted(path string) []string {
	mut dirs := []string{}
	mut files := os.ls(path) or { return dirs }
	for file in files {
		if os.is_dir(os.real_path(os.join_path(path, file))) {
			dirs << file
		}
	}
	dirs.sort()
	dirs.reverse_in_place()
	return dirs
}

pub fn cache_dir() string {
	mut cache_dir := cache.get_string(@MOD + '.' + @FN)
	if cache_dir != '' {
		return cache_dir
	}
	cache_dir = os.join_path(os.cache_dir(), 'v', 'android')
	if !os.exists(cache_dir) {
		os.mkdir_all(cache_dir) or {
			panic(@MOD + '.' + @FN + ' error making cache directory "$cache_dir". $err')
		}
	}
	cache.set_string(@MOD + '.' + @FN, cache_dir)
	return cache_dir
}

pub fn is_version(str string) bool {
	dots := str.count('.')
	if dots >= 1 && dots <= 2 {
		stripped := str.split('.').join('')
		for byt in stripped.bytes() {
			if !byt.is_digit() {
				return false
			}
		}
		return true
	}
	return false
}

pub fn verbosity_print_cmd(args []string, verbosity int) {
	cmd := args.join(' ')
	if verbosity > 1 {
		println('Running ${args[0]}')
		if verbosity > 2 {
			println(cmd)
		}
	}
}

pub fn run_or_exit(args []string) string {
	res := run(args)
	if res.exit_code != 0 {
		eprintln('${args[0]} failed with return code $res.exit_code')
		eprintln(res.output)
		exit(1)
	}
	return res.output
}

pub fn run(args []string) os.Result {
	res := os.execute(args.join(' '))
	if res.exit_code < 0 {
		return os.Result{1, ''}
	}
	return res
}

pub fn run_raw(args []string) os.Result {
	res := unsafe { os.raw_execute(args.join(' ')) }
	if res.exit_code < 0 {
		return os.Result{1, ''}
	}
	return res
}

pub fn unzip(file string, dir string) ? {
	if !os.is_dir(dir) {
		os.mkdir_all(dir)?
	}
	szip.extract_zip_to_dir(file, dir)?
}

pub fn zip_folder(dir string, out_file string) ? {
	szip.zip_folder(dir, out_file)?
}
