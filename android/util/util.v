// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module util

import os

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
	return os.join_path(os.cache_dir(), 'v', 'android')
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
	if res.exit_code > 0 {
		eprintln('${args[0]} failed with return code $res.exit_code')
		eprintln(res.output)
		exit(1)
	}
	return res.output
}

pub fn run(args []string) os.Result {
	res := os.exec(args.join(' ')) or { os.Result{1, ''} }
	return res
}

pub fn unzip(file string, dir string) bool {
	/*
	eprintln('Unzipping ${file} to ${dir}...')
	mut zip := szip.open(file, 0, szip.m_ronly) or { return false }
	zip.extract_entry(dir)
	zip.close()
	*/

	// TODO unzip
	unzip_cmd := [
		'unzip',
		file,
		'-d',
		dir,
	]
	run_or_exit(unzip_cmd)
	return true
}

// TODO remove when vlib os.cp_all is fixed
// cp_all will recursively copy `src` to `dst`,
// optionally overwriting files or dirs in `dst`.
pub fn cp_all(src string, dst string, overwrite bool) ? {
	source_path := real_path(src)
	dest_path := real_path(dst)
	if !exists(source_path) {
		return error("Source path doesn't exist")
	}
	// single file copy
	if !is_dir(source_path) {
		adjusted_path := if is_dir(dest_path) {
			join_path(dest_path, file_name(source_path))
		} else {
			dest_path
		}
		if exists(adjusted_path) {
			if overwrite {
				rm(adjusted_path) ?
			} else {
				return error('Destination file path already exist')
			}
		}
		cp(source_path, adjusted_path) or { panic('cp $err') }
		return
	}
	if !is_dir(dest_path) {
		return error('Destination path is not a valid directory')
	}
	files := ls(source_path) ?
	for file in files {
		sp := join_path(source_path, file)
		dp := join_path(dest_path, file)
		if is_dir(sp) {
			if !exists(dp) {
				mkdir(dp) ?
			}
		}
		cp_all(sp, dp, overwrite) or {
			rmdir(dp) or { return error(err) }
			return error(err)
		}
	}
}
