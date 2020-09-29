module util

import os

// Utility functions
//
pub fn find_sorted(path string) []string {
	mut dirs := []string{}
	mut files := os.ls(path) or { return dirs }
	for file in files {
		if os.is_dir(os.real_path(os.join_path(path,file))) {
			dirs << os.real_path(os.join_path(path,file))
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
		if os.is_dir(os.real_path(os.join_path(path,file))) {
			dirs << file
		}
	}
	dirs.sort()
	dirs.reverse_in_place()
	return dirs
}
