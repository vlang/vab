// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module cache

struct Cache {
mut:
	string_cache       map[string]string
	string_array_cache map[string][]string
}

const global_cache = &Cache{}

pub fn get_string(key string) string {
	mut c := &Cache(unsafe { nil })
	unsafe {
		c = global_cache
	}
	if key in c.string_cache.keys() {
		return c.string_cache[key]
	}

	return ''
}

pub fn set_string(key string, data string) {
	mut c := &Cache(unsafe { nil })
	unsafe {
		c = global_cache
	}
	c.string_cache[key] = data
}

pub fn get_string_array(key string) []string {
	mut c := &Cache(unsafe { nil })
	unsafe {
		c = global_cache
	}
	if key in c.string_array_cache.keys() {
		return c.string_array_cache[key]
	}

	return []string{}
}

pub fn set_string_array(key string, data []string) {
	mut c := &Cache(unsafe { nil })
	unsafe {
		c = global_cache
	}
	c.string_array_cache[key] = data
}
