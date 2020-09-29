module ndk

import os

import android.sdk
import android.util

const (
	home = os.home_dir()
	supported_archs = ['arm64-v8a','armeabi-v7a','x86','x86_64']
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
				// ndk-which reside in some ndk roots
				ndk_root = os.real_path(os.dir(ndk_which))
			}
		}
	}
	return ndk_root
}

pub fn root_version(version string) string {
	if !is_side_by_side() {
		return root()
	}
	return os.join_path(root(),version)
}

pub fn found() bool {
	return root() != ''
}

pub fn is_side_by_side() bool {
	return os.real_path(os.join_path(sdk.root(),'ndk')) == os.real_path(os.join_path(root()))
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
	mut host_arch := ''
	uos := os.user_os()
	if uos == 'windows' { host_arch = 'windows-x86_64' }
	if uos == 'macos'   { host_arch = 'darwin-x86_64' }
	if uos == 'linux'   { host_arch = 'linux-x86_64' }
	return host_arch
}

[inline]
pub fn alt_arch(arch string) string {
	return match arch {
		'armeabi-v7a' { 'armv7a' }
		'arm64-v8a' { 'aarch64' }
		'x86' { 'x86_64' }
		'x86_64' { 'x86_64' }
		else { '' }
	}
}

[inline] // TODO do Windows as well
pub fn compiler(ndk_version string, arch string, api_level string) ?string {
	mut eabi := ''
	if arch == 'armeabi-v7a' { eabi = 'eabi' }

	host_architecture := host_arch()
	arch_alt := alt_arch(arch)

	mut compiler := os.join_path(root_version(ndk_version),'toolchains','llvm','prebuilt',host_architecture,'bin',arch_alt+'-linux-android${eabi}${api_level}-clang')
	// Try older ndk version setups
	if !os.is_file(compiler) {
		toolchains := util.ls_sorted(os.join_path(root_version(ndk_version),'toolchains'))
		for toolchain in toolchains {
			if toolchain.starts_with('llvm') {
				compiler = os.join_path(root_version(ndk_version),'toolchains',toolchain,'prebuilt',host_architecture,'bin',arch_alt+'-linux-android${eabi}${api_level}-clang')
				break
			}
		}
	}
	if !os.is_file(compiler) {
		return error(@MOD+'.'+@FN+' couldn\'t locate compiler "${compiler}"')
	}
	return compiler
}

[inline]
pub fn libs_path(ndk_version string, arch string, api_level string) ?string {
	mut eabi := ''
	if arch == 'armeabi-v7a' { eabi = 'eabi' }

	mut host_architecture := host_arch()
	mut arch_alt := alt_arch(arch)

	if eabi != '' { arch_alt = 'arm' }

	mut libs_path := os.join_path(root_version(ndk_version),'toolchains','llvm','prebuilt',host_architecture,'sysroot','usr','lib',arch_alt+'-linux-android'+eabi,api_level)

	if !os.is_dir(libs_path) {
		toolchains := util.ls_sorted(os.join_path(root_version(ndk_version),'toolchains'))
		for toolchain in toolchains {
			if toolchain.starts_with('llvm') {
				libs_path = os.join_path(root_version(ndk_version),'toolchains',toolchain,'prebuilt',host_architecture,'sysroot','usr','lib',arch_alt+'-linux-android'+eabi,api_level)
				break
			}
		}
	}
	if !os.is_dir(libs_path) {
		return error(@MOD+'.'+@FN+' couldn\'t locate libraries path "${libs_path}"')
	}

	return libs_path
}
