// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import vab.java
import vab.android.util

pub struct Keystore {
pub mut:
	path           string
	password       string = 'android'
	alias          string = 'androiddebugkey'
	alias_password string = 'android'
}

pub fn resolve_keystore(default_ks Keystore) !Keystore {
	file := default_ks.path
	if !os.is_file(file) {
		generate_debug_keystore(file)!
	}
	// Defaults from Android debug key
	mut password := 'android'
	mut alias := 'androiddebugkey'
	mut alias_password := password

	if default_ks.password != '' {
		password = default_ks.password
	}
	if default_ks.alias != '' {
		alias = default_ks.alias
	}
	if default_ks.alias_password != '' {
		alias_password = default_ks.alias_password
	}

	return Keystore{
		path:           file
		password:       password
		alias:          alias
		alias_password: alias_password
	}
}

// default_keystore returns the debug keystore located in `cache_directory`.
// if no debug.keystore can be found it will be generated.
pub fn default_keystore(cache_directory string) !Keystore {
	// NOTE use a cache directory to prevent 2 things:
	// 1. Avoid adb error "INSTALL_FAILED_UPDATE_INCOMPATIBLE" between machine reboots
	// 2. Do not pollute current directory / pwd with a debug.keystore
	keystore_dir := os.join_path(cache_directory, 'keystore')
	if !os.is_dir(keystore_dir) {
		os.mkdir_all(keystore_dir) or {
			return error('Could make directory for debug keystore.\n${err}')
		}
	}
	debug_keystore_path := os.join_path(keystore_dir, 'debug.keystore')
	if os.exists(debug_keystore_path) {
		return Keystore{
			path: debug_keystore_path
		}
	}
	return generate_debug_keystore(os.join_path(keystore_dir, 'debug.keystore'))!
}

// generate_debug_keystore generates a debug keystore at `file_path`.
pub fn generate_debug_keystore(file_path string) !Keystore {
	keytool := java.jdk_keytool()!
	password := 'android'
	alias := 'androiddebugkey'
	alias_password := password
	mut dname_args := "'CN=,OU=,O=,L=,S=,C=US'"
	$if windows {
		dname_args = '"' + dname_args.trim("'") + '"'
	}
	keytool_cmd := [
		keytool,
		'-genkeypair',
		'-keystore ' + file_path,
		'-storepass android',
		'-alias androiddebugkey',
		'-keypass android',
		'-keyalg RSA',
		'-validity 10000',
		'-dname',
		dname_args,
	]
	util.run_or_error(keytool_cmd)!
	return Keystore{
		path:           file_path
		password:       password
		alias:          alias
		alias_password: alias_password
	}
}
