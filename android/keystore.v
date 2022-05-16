// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import java
import android.util

pub struct Keystore {
pub mut:
	path           string
	password       string
	alias          string
	alias_password string
}

pub fn resolve_keystore(default_ks Keystore, verbosity int) Keystore {
	file := default_ks.path
	if !os.is_file(file) {
		if verbosity > 0 {
			println('Generating "$file"')
		}
		keytool := os.join_path(java.jdk_bin_path(), 'keytool')
		mut dname_args := "'CN=,OU=,O=,L=,S=,C=US'"
		$if windows {
			dname_args = '"' + dname_args.trim("'") + '"'
		}
		keytool_cmd := [
			keytool,
			'-genkeypair',
			'-keystore ' + file,
			'-storepass android',
			'-alias androiddebugkey',
			'-keypass android',
			'-keyalg RSA',
			'-validity 10000',
			'-dname',
			dname_args,
		]
		util.verbosity_print_cmd(keytool_cmd, verbosity)
		util.run_or_exit(keytool_cmd)
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
		path: file
		password: password
		alias: alias
		alias_password: alias_password
	}
}
