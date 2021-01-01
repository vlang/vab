// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module sdk

import os

import android.util

const (
	home = os.home_dir()
)

const (
	default_api_level = os.file_name(default_platforms_dir()).all_after('android-')
	default_build_tools_version = os.file_name(default_build_tools_dir())

	min_supported_api_level = '20'
	min_supported_build_tools_version = '24.0.3'
)

// Possible default locations of the SDK
// https://stackoverflow.com/a/47630714/1904615
const (
	possible_sdk_paths_windows = [
		os.join_path(os.getenv('LOCALAPPDATA'), 'Local\\Android\\sdk')
		os.join_path(home, 'AppData\\Local\\Android\\sdk')
	]
	possible_sdk_paths_macos = [
		os.join_path(home, 'Library/Android/sdk')
	]
	possible_sdk_paths_linux = [
		os.join_path(home, "Android/Sdk"),
		'/usr/local/lib/android/sdk'
	]
)

enum Component {
	ndk
	api_level
	build_tools
}

// root will try to detect where the Android SDK is installed. Otherwise return an empty string
pub fn root() string {
	mut sdk_root := os.getenv('ANDROID_SDK_ROOT')

	if sdk_root == '' {
		sdk_root = os.getenv('ANDROID_HOME')
	}

	if sdk_root == '' {
		// Detect OS type at runtime - in case we're in some exotic environment
		dirs := match os.user_os() {
			'windows'	{ possible_sdk_paths_windows }
			'macos'		{ possible_sdk_paths_macos }
			'linux'		{ possible_sdk_paths_linux }
			else		{ []string{} }
		}

		for dir in dirs {
			if os.exists(dir) && os.is_dir(dir) { return dir }
		}
	}
	// Try and detect by getting path to 'adb'
	if sdk_root == '' {
		mut adb_path := ''

		if os.exists_in_system_path('adb') {
			adb_path = os.find_abs_path_of_executable('adb') or { return '' }
			if adb_path != '' {
				// adb normally reside in 'path/to/sdk_root/platform-tools/'
				sdk_root = os.real_path(os.join_path(os.dir(adb_path),'..'))
			}
		}
	}
	// Try and detect by getting path to 'sdkmanager'
	if sdk_root == '' {
		//mut path := sdkmanager() <- Don't do this recursion
		mut path := ''
		if os.exists_in_system_path('sdkmanager') {
			if os.exists_in_system_path('sdkmanager') {
				path = os.find_abs_path_of_executable('sdkmanager') or { '' }
			}
		}
		// Check in cache
		if !os.is_executable(path) {
			path = os.join_path(util.cache_dir(),'cmdline-tools','tools','bin','sdkmanager')
		}
		if !os.is_executable(path) {
			path = ''
		}

		if path != '' {
			// sdkmanager used to reside in 'path/to/sdk_root/cmdline-tools/tools/bin'
			// but in older setups it coould reside in 'path/to/sdk_root/tools/bin'
			// and newer setups in 'path/to/sdk_root/cmdline-tools/latest/bin' or
			// supposedly 'path/to/sdk_root/cmdline-tools/<version>/bin'
			// ... Android development is a complete mess. *sigh* ...
			// For help and updates, please see
			// https://stackoverflow.com/a/61176718
			if path.contains('cmdline-tools') {
				sdk_root = os.real_path(os.join_path(os.dir(path),'..','..','..'))
			} else {
				sdk_root = os.real_path(os.join_path(os.dir(path),'..','..'))
			}
		}
	}
	return sdk_root.trim_right(r'\/')
}

pub fn found() bool {
	return root() != ''
}

pub fn sdkmanager() string {
	mut sdkmanager := ''
	if found() {
		sdkmanager = os.join_path(tools_root(),'bin','sdkmanager')
		if !os.is_executable(sdkmanager) {
			sdkmanager = os.join_path(root(),'cmdline-tools','tools','bin','sdkmanager')
		}
	}
	if !os.is_executable(sdkmanager) {
		if os.exists_in_system_path('sdkmanager') {
			sdkmanager = os.find_abs_path_of_executable('sdkmanager') or { '' }
		}
	}
	// Check in cache
	if !os.is_executable(sdkmanager) {
		sdkmanager = os.join_path(util.cache_dir(),'cmdline-tools','tools','bin','sdkmanager')
	}
	if !os.is_executable(sdkmanager) {
		sdkmanager = ''
	}
	return sdkmanager
}

pub fn sdkmanager_version() string {
	mut version := '0.0.0'
	sdkm := sdkmanager()
	if sdkm != '' {
		cmd := [
			sdkm,
			'--version'
		]
		cmd_res := util.run(cmd)
		if cmd_res.exit_code > 0 {
			return version
		}
		version = cmd_res.output.trim(' \n\r')
	}
	return version
}

pub fn tools_root() string {
	if ! found() { return '' }
	return os.join_path(root(),'tools')
}

pub fn build_tools_root() string {
	if ! found() { return '' }
	return os.join_path(root(),'build-tools')
}

pub fn platform_tools_root() string {
	if ! found() { return '' }
	return os.join_path(root(),'platform-tools')
}

pub fn platforms_root() string {
	if ! found() { return '' }
	return os.join_path(root(),'platforms')
}

pub fn platforms_dir() []string {
	if ! found() { return []string{} }
	return util.find_sorted(platforms_root())
}

pub fn api_dirs() []string {
	if ! found() { return []string{} }
	return util.ls_sorted(platforms_root())
}

pub fn apis_available() []string {
	mut apis := []string{}
	for api in api_dirs() {
		apis << api.all_after('android-')
	}
	return apis
}

pub fn has_api(api string) bool {
	return api in apis_available()
}

pub fn has_build_tools(version string) bool {
	return version in build_tools_available()
}

pub fn build_tools_available() []string {
	if ! found() { return []string{} }
	return util.ls_sorted(build_tools_root())
}

pub fn default_build_tools_dir() string {
	if ! found() { return '' }
	dirs := util.find_sorted(build_tools_root())
	if dirs.len > 0 {
		return dirs.first()
	}
	return ''
}

pub fn default_platforms_dir() string {
	if ! found() { return '' }
	dirs := util.find_sorted(platforms_root())
	if dirs.len > 0 {
		return dirs.first()
	}
	return ''
}

pub fn setup(component Component, version string) {
	// TODO
}

