// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module ndk

import os
import android.sdk
import android.util

const (
	home = os.home_dir()
)

pub const (
	supported_archs       = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
	min_supported_version = min_version()
)

// ANDROID_SDK_ROOT and ANDROID_HOME is official ENV variables to get the SDK root
// but no such conventions exists for getting the NDK.
// However ANDROID_NDK_ROOT is widely used and the `sdkmanager` has support
// for installing the NDK - and it will do so in a sub-folder (/ndk) of the SDK root.
// This is also referred to as a "Side by side" install.
const (
	possible_ndk_paths_windows = [
		os.join_path(sdk.root(), 'ndk'),
		os.join_path(sdk.root(), 'ndk-bundle'),
	]
	possible_ndk_paths_macos   = [
		os.join_path(sdk.root(), 'ndk'),
		os.join_path(sdk.root(), 'ndk-bundle'),
	]
	possible_ndk_paths_linux   = [
		os.join_path(sdk.root(), 'ndk'),
		os.join_path(sdk.root(), 'ndk-bundle'),
	]
)

// root will try to detect where the Android NDK is installed. Otherwise return blank
pub fn root() string {
	mut ndk_root := os.getenv('ANDROID_NDK_ROOT')
	if ndk_root != '' && !os.is_dir(ndk_root) {
		$if debug_ndk ? {
			eprintln(@MOD + '.' + @FN +
				' Warning: NDK found via ANDROID_NDK_ROOT "$ndk_root" is not a directory.')
		}
		ndk_root = ''
	}
	if ndk_root == '' && sdk.root() != '' {
		mut dirs := []string{}

		// Detect OS type at runtime - in case we're in some exotic environment
		uos := os.user_os()
		if uos == 'windows' {
			dirs = ndk.possible_ndk_paths_windows.clone()
		}
		if uos == 'macos' {
			dirs = ndk.possible_ndk_paths_macos.clone()
		}
		if uos == 'linux' {
			dirs = ndk.possible_ndk_paths_linux.clone()
		}

		for dir in dirs {
			if os.exists(dir) && os.is_dir(dir) {
				$if debug_ndk ? {
					eprintln(@MOD + '.' + @FN + ' found NDK in hardcoded paths at "$dir"')
				}
				return dir
			}
		}
	}
	// Try if ndk-which is in path
	if ndk_root == '' {
		mut ndk_which := ''
		if os.exists_in_system_path('ndk-which') {
			ndk_which = os.find_abs_path_of_executable('ndk-which') or { return '' }
			if ndk_which != '' {
				if os.is_executable(ndk_which) {
					// ndk-which reside in some ndk roots
					ndk_root = os.real_path(os.dir(ndk_which))
					if !os.is_dir(ndk_root) {
						$if debug_ndk ? {
							eprintln(@MOD + '.' + @FN +
								' ndk-which was in PATH but containing dir is no more "$ndk_root"')
						}
						ndk_root = ''
					}
				}
			}
		}
	}
	if !os.is_dir(ndk_root) {
		$if debug_ndk ? {
			eprintln(@MOD + '.' + @FN + ' Warning: "$ndk_root" is not a dir')
		}
		ndk_root = ''
	}
	return ndk_root.trim_right(r'\/')
}

pub fn root_version(version string) string {
	if !is_side_by_side() {
		return root()
	}
	return os.join_path(root(), version)
}

pub fn found() bool {
	return root() != ''
}

pub fn is_side_by_side() bool {
	return os.real_path(os.join_path(sdk.root(), 'ndk')) == os.real_path(os.join_path(root()))
}

pub fn versions_available() []string {
	if !is_side_by_side() {
		return [os.file_name(root())]
	}
	return util.ls_sorted(root())
}

pub fn has_version(version string) bool {
	if !is_side_by_side() {
		return os.file_name(root()) == version
	}
	return version in versions_available()
}

/*
pub fn versions_dir() []string {
	return util.find_sorted(root())
}
*/

pub fn min_version() string {
	mut version := '0.0.0'
	uos := os.user_os()
	if uos == 'windows' {
		version = '0.0.0'
	}
	if uos == 'macos' {
		version = '21.3.6528147'
	}
	if uos == 'linux' {
		version = '21.1.6352462'
	}
	return version
}

pub fn default_version() string {
	if !is_side_by_side() {
		return os.file_name(root())
	}
	dirs := util.find_sorted(root())
	if dirs.len > 0 {
		return os.file_name(dirs.first())
	}
	return ''
}

[inline]
pub fn host_arch() string {
	host_arch := match os.user_os() {
		'windows' { 'windows-x86_64' }
		'macos' { 'darwin-x86_64' }
		'linux' { 'linux-x86_64' }
		else { 'unknown' }
	}
	return host_arch
}

// arch_to_instruction_set maps `arch` to an instruction set
// Example: assert ndk.arch_to_instruction_set('x86') == 'i686'
[inline]
pub fn arch_to_instruction_set(arch string) string {
	return match arch {
		'armeabi-v7a' { 'armv7a' }
		'arm64-v8a' { 'aarch64' }
		'x86' { 'i686' }
		'x86_64' { 'x86_64' }
		else { '' }
	}
}

// TODO do Windows as well
[inline]
pub fn compiler(ndk_version string, arch string, api_level string) ?string {
	mut eabi := ''
	if arch == 'armeabi-v7a' {
		eabi = 'eabi'
	}

	host_architecture := host_arch()
	arch_is := arch_to_instruction_set(arch)

	mut compiler := os.join_path(root_version(ndk_version), 'toolchains', 'llvm', 'prebuilt',
		host_architecture, 'bin', arch_is + '-linux-android$eabi$api_level-clang')
	// legacy ndk version setups
	/*
	if !os.is_file(compiler) {
		toolchains := util.ls_sorted(os.join_path(root_version(ndk_version),'toolchains'))
		for toolchain in toolchains {
			if toolchain.starts_with('llvm') {
				compiler = os.join_path(root_version(ndk_version),'toolchains',toolchain,'prebuilt',host_architecture,'bin',arch_is+'-linux-android${eabi}${api_level}-clang')
				break
			}
		}
	}
	*/
	if !os.is_file(compiler) {
		return error(@MOD + '.' + @FN +
			' couldn\'t locate compiler "$compiler". You could try with a newer ndk version.')
	}
	return compiler
}

[inline]
pub fn libs_path(ndk_version string, arch string, api_level string) ?string {
	mut eabi := ''
	if arch == 'armeabi-v7a' {
		eabi = 'eabi'
	}

	mut host_architecture := host_arch()
	mut arch_is := arch_to_instruction_set(arch)

	if eabi != '' {
		arch_is = 'arm'
	}

	mut libs_path := os.join_path(root_version(ndk_version), 'toolchains', 'llvm', 'prebuilt',
		host_architecture, 'sysroot', 'usr', 'lib', arch_is + '-linux-android' + eabi,
		api_level)

	/*
	if !os.is_dir(libs_path) {
		toolchains := util.ls_sorted(os.join_path(root_version(ndk_version),'toolchains'))
		for toolchain in toolchains {
			if toolchain.starts_with('llvm') {
				libs_path = os.join_path(root_version(ndk_version),'toolchains',toolchain,'prebuilt',host_architecture,'sysroot','usr','lib',arch_is+'-linux-android'+eabi,api_level)
				break
			}
		}
	}
	*/
	if !os.is_dir(libs_path) {
		return error(@MOD + '.' + @FN +
			' couldn\'t locate libraries path "$libs_path". You could try with a newer ndk version.')
	}

	return libs_path
}
