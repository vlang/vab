// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module java

import os
import regex
import vab.cache

// jre_version returns the version of your java runtime install, otherwise empty string
pub fn jre_version() string {
	mut java := 'java'
	java_home := jre_root()
	if java_home != '' {
		bin := os.join_path(java_home, 'bin', java)
		if os.is_executable(bin) {
			java = bin
		}
	}

	if java == '' {
		return ''
	}

	mut version := ''

	// Fast - but not most reliable way
	java_version := os.execute(java + ' -version')
	if java_version.exit_code == 0 {
		output := java_version.output
		mut re := regex.regex_opt(r'.*(\d+\.?\d*\.?\d*)') or { panic(err) }
		start, _ := re.match_string(output)
		if start >= 0 && re.groups.len > 0 {
			version = output[re.groups[0]..re.groups[1]]
		}
	}
	// Slow - but more reliable way, using Java itself
	if version == '' && jdk_found() {
		javac := os.join_path(jdk_root(), 'bin', 'javac')
		java_source := 'public class JavaVersion { public static void main(String[] args) { System.out.format("%s", System.getProperty("java.version")); } }'
		java_source_dir := os.temp_dir() + os.path_separator
		java_source_exe := 'JavaVersion'
		java_source_file := java_source_exe + '.java'
		pwd := os.getwd()
		os.chdir(java_source_dir) or {}
		os.write_file(java_source_file, java_source) or { return '' }
		if os.system(javac + ' ${java_source_file}') == 0 {
			r := os.execute(java + ' ${java_source_exe}')
			if r.exit_code != 0 {
				return ''
			}
			version = r.output
		}
		os.chdir(pwd) or {}
	}

	return version
}

pub fn jdk_version() string {
	mut java := 'javac'
	java_home := jdk_root()
	if java_home != '' {
		bin := os.join_path(java_home, 'bin', java)
		if os.is_executable(bin) {
			java = bin
		}
	}

	if java == '' {
		return ''
	}

	mut version := ''

	// Fast - but not most reliable way
	java_version := os.execute(java + ' -version')
	if java_version.exit_code != 0 {
		return ''
	}
	output := java_version.output

	mut re := regex.regex_opt(r'.*(\d+\.?\d*\.?\d*)') or { panic(err) }
	start, _ := re.match_string(output)
	if start >= 0 && re.groups.len > 0 {
		version = output[re.groups[0]..re.groups[1]]
	}
	// Slow - but more reliable way, using Java itself
	if version == '' && jdk_found() {
		javac := os.join_path(jdk_root(), 'bin', 'javac')
		java_source := 'public class JavaVersion { public static void main(String[] args) { System.out.format("%s", System.getProperty("java.version")); } }'
		java_source_dir := os.temp_dir() + os.path_separator
		java_source_exe := 'JavaVersion'
		java_source_file := java_source_exe + '.java'
		pwd := os.getwd()
		os.chdir(java_source_dir) or {}
		os.write_file(java_source_file, java_source) or { return '' }
		if os.system(javac + ' ${java_source_file}') == 0 {
			r := os.execute(java + ' ${java_source_exe}')
			if r.exit_code != 0 {
				return ''
			}
			version = r.output
		}
		os.chdir(pwd) or {}
	}

	if version.count('.') <= 1 {
		// Java 9 returns just "9".
		// The semver module doesn't condsider this a semantic version number
		if version.count('.') == 1 {
			version += '.0'
		}
		if version.count('.') == 0 {
			version += '.0.0'
		}
	}

	return version
}

pub fn jre_root() string {
	mut java_home := os.getenv('JAVA_HOME')
	if java_home != '' {
		return java_home.trim_right(os.path_separator)
	}
	$if !windows {
		possible_symlink := os.find_abs_path_of_executable('java') or { return '' }
		java_home = os.real_path(os.join_path(os.dir(possible_symlink), '..'))
	} $else {
		res := os.execute('where.exe java')
		if res.exit_code != 0 {
			java_home = ''
		} else {
			java_home = os.dir(res.output.trim('\n\r'))
		}
	}
	return java_home.trim_right(os.path_separator)
}

pub fn jre_found() bool {
	return jdk_root() != ''
}

pub fn jre_bin_path() string {
	bin_dir := os.find_abs_path_of_executable('java') or { os.join_path(jre_root(), 'bin', 'java') }
	return os.dir(bin_dir)
}

// jre_java_exe returns the full path to the system `java` executable if found, empty string otherwise.
pub fn jre_java_exe() string {
	return os.join_path(jre_bin_path(), 'java')
}

pub fn jdk_root() string {
	mut java_home := cache.get_string(@MOD + '.' + @FN)
	if java_home != '' {
		return java_home
	}

	java_home = os.getenv('JAVA_HOME')
	if java_home != '' {
		return java_home.trim_right(os.path_separator)
	}
	$if !windows {
		possible_symlink := os.find_abs_path_of_executable('javac') or { return '' }
		java_home = os.real_path(os.join_path(os.dir(possible_symlink), '..'))
	} $else {
		res := os.execute('where.exe javac')
		if res.exit_code != 0 {
			java_home = ''
		} else {
			java_home = os.dir(res.output.trim('\n\r'))
		}
	}
	java_home = java_home.trim_right(os.path_separator)
	cache.set_string(@MOD + '.' + @FN, java_home)
	return java_home
}

pub fn jdk_found() bool {
	root := jdk_root()
	return root != '' && os.exists(root)
}

// jdk_bin_path returns the absolute path to the JDK `bin` directory.
pub fn jdk_bin_path() string {
	bin_dir := os.find_abs_path_of_executable('javac') or {
		os.join_path(jdk_root(), 'bin', 'javac')
	}
	return os.dir(bin_dir)
}

// jdk_keytool returns the absolute path to the JDK keytool executable.
pub fn jdk_keytool() !string {
	mut keytool_exe := 'keytool'
	$if windows {
		keytool_exe += '.exe'
	}
	keytool := os.join_path(jdk_bin_path(), keytool_exe)
	if !os.exists(keytool) {
		return error(@MOD + '.' + @FN +
			': no `${keytool_exe}` could be located in "${jdk_bin_path()}"')
	}
	return keytool
}

// jdk_javac returns the absolute path to the system javac executable.
pub fn jdk_javac() !string {
	mut javac_exe := 'javac'
	$if windows {
		javac_exe += '.exe'
	}
	javac := os.join_path(jdk_bin_path(), javac_exe)
	if !os.exists(javac) {
		return error(@MOD + '.' + @FN +
			': no `${javac_exe}` could be located in "${jdk_bin_path()}"')
	}
	return javac
}
