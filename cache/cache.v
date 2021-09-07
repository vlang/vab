// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module cache

struct Cache {
mut:
	string_cache       map[string]string
	string_array_cache map[string][]string
}

const (
	global_cache = &Cache{}
)

pub fn get_string(key string) string {
	mut c := &Cache(0)
	unsafe {
		c = cache.global_cache
	}
	if key in c.string_cache.keys() {
		// println(@MOD + '.' + @FN + '($key) get cached')
		return c.string_cache[key]
	}
	// println(@MOD + '.' + @FN + '($key) get non cached')
	return ''
}

pub fn set_string(key string, data string) {
	mut c := &Cache(0)
	unsafe {
		c = cache.global_cache
	}
	// println(@MOD + '.' + @FN + '($key) caching')
	c.string_cache[key] = data
}

pub fn get_string_array(key string) []string {
	mut c := &Cache(0)
	unsafe {
		c = cache.global_cache
	}
	if key in c.string_array_cache.keys() {
		// println(@MOD + '.' + @FN + '($key) get cached')
		return c.string_array_cache[key]
	}
	// println(@MOD + '.' + @FN + '($key) get non cached')
	return []string{}
}

pub fn set_string_array(key string, data []string) {
	mut c := &Cache(0)
	unsafe {
		c = cache.global_cache
	}
	// println(@MOD + '.' + @FN + '($key) caching')
	c.string_array_cache[key] = data
}
