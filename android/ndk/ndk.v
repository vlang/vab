module ndk

import os

import android.sdk

const (
	home = os.home_dir()
)

// ANDROID_SDK_ROOT and ANDROID_HOME are official ENV variables to get the SDK
// but no such conventions exists for getting the NDK.
// However ANDROID_NDK_ROOT is widely used and the `sdkmanager` has support
// for installing the NDK - and it will do so in a sub-folder (/ndk) of the SDK root.
// This is also referred to as a "Side by side" install
const (
	possible_ndk_paths_windows = [
		os.join_path(sdk.root(),'ndk')
	]
	possible_ndk_paths_macos = [
		os.join_path(sdk.root(),'ndk')
	]
	possible_ndk_paths_linux = [
		os.join_path(sdk.root(),'ndk')
	]
)

// root will try to detect where the Android NDK is installed. Otherwise return blank
pub fn root() string {
	mut ndk_root := os.getenv('ANDROID_NDK_ROOT')
	if ndk_root == '' {
		mut dirs := []string{}

		// Detect OS type at runtime - in case we're in some exotic environment
		uos := os.user_os()
		if uos == 'windows' { dirs = possible_ndk_paths_windows }
		if uos == 'macos'   { dirs = possible_ndk_paths_macos }
		if uos == 'linux'   { dirs = possible_ndk_paths_linux }

		for dir in dirs {
			if os.exists(dir) && os.is_dir(dir) { return dir }
		}
	}
	// Try if ndk-which is in path
	if ndk_root == '' {
		mut ndk_which := ''

		if os.exists_in_system_path('ndk-which') {
			ndk_which = os.find_abs_path_of_executable('ndk-which') or { return '' }
			if ndk_which != '' {
				// ndk-which normally reside in ndk root
				ndk_root = os.real_path(os.dir(ndk_which))
			}
		}
	}
	return ndk_root
}

pub fn found() bool {
	return root() != ''
}

pub fn versions_available() []string {
	return ls_sorted(root())
}

pub fn has_version(version string) bool {
	return version in versions_available()
}

pub fn versions_dir() []string {
	return find_sorted(root())
}

pub fn default_version() string {
	dirs := find_sorted(root())
	if dirs.len > 0 {
		return os.file_name(dirs.first())
	}
	return ''
}

/*
 * Utility functions
 * TODO share between sdk/ndk?
 */
fn find_sorted(path string) []string {
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

fn ls_sorted(path string) []string {
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
