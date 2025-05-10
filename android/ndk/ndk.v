// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module ndk

import os
import x.json2
import vab.cache
import vab.android.sdk
import vab.android.util

const home = os.home_dir()

pub const supported_archs = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
pub const min_supported_version = min_version_supported_by_vab()

pub enum CompilerLanguageType {
	c
	cpp
}

pub enum Tool {
	ar
}

// ANDROID_SDK_ROOT and ANDROID_HOME is official ENV variables to get the SDK root
// but no such conventions exists for getting the NDK.
// However ANDROID_NDK_ROOT is widely used and the `sdkmanager` has support
// for installing the NDK - and it will do so in a sub-folder (/ndk) of the SDK root.
// This is also referred to as a "Side by side" install.
const possible_ndk_paths_windows = [
	os.join_path(sdk.root(), 'ndk'),
	os.join_path(sdk.root(), 'ndk-bundle'),
]
const possible_ndk_paths_macos = [
	os.join_path(sdk.root(), 'ndk'),
	os.join_path(sdk.root(), 'ndk-bundle'),
]
const possible_ndk_paths_linux = [
	os.join_path(sdk.root(), 'ndk'),
	os.join_path(sdk.root(), 'ndk-bundle'),
]

// root will try to detect where the Android NDK is installed. Otherwise return blank
pub fn root() string {
	mut ndk_root := cache.get_string(@MOD + '.' + @FN)
	if ndk_root != '' {
		return ndk_root
	}

	ndk_root = os.getenv('ANDROID_NDK_ROOT')
	if ndk_root != '' && !os.is_dir(ndk_root) {
		$if debug_ndk ? {
			eprintln(@MOD + '.' + @FN +
				' Warning: NDK found via ANDROID_NDK_ROOT "${ndk_root}" is not a directory.')
		}
		ndk_root = ''
	}
	if ndk_root == '' && sdk.root() != '' {
		mut dirs := []string{}

		// Detect OS type at runtime - in case we're in some exotic environment
		uos := os.user_os()
		if uos == 'windows' {
			dirs = possible_ndk_paths_windows.clone()
		}
		if uos == 'macos' {
			dirs = possible_ndk_paths_macos.clone()
		}
		if uos == 'linux' {
			dirs = possible_ndk_paths_linux.clone()
		}

		for dir in dirs {
			if os.exists(dir) && os.is_dir(dir) {
				$if debug_ndk ? {
					eprintln(@MOD + '.' + @FN + ' found NDK in hardcoded paths at "${dir}"')
				}
				ndk_root = dir
				cache.set_string(@MOD + '.' + @FN, ndk_root)
				return ndk_root
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
								' ndk-which was in PATH but containing dir is no more "${ndk_root}"')
						}
						ndk_root = ''
					}
				}
			}
		}
	}
	if !os.is_dir(ndk_root) {
		$if debug_ndk ? {
			eprintln(@MOD + '.' + @FN + ' Warning: "${ndk_root}" is not a dir')
		}
		ndk_root = ''
	}
	ndk_root = ndk_root.trim_right(r'\/')
	cache.set_string(@MOD + '.' + @FN, ndk_root)
	return ndk_root
}

// default_version returns the default NDK version if found, blank otherwise
pub fn default_version() string {
	if !is_side_by_side() {
		v := version_from_source_properties() or { '' }
		if v != '' {
			return v
		}
		return os.file_name(root())
	}
	dirs := util.find_sorted(root())
	if dirs.len > 0 {
		return os.file_name(dirs.first())
	}
	return ''
}

// root_version returns the root for the NDK with `version`.
pub fn root_version(version string) string {
	if !is_side_by_side() {
		if version != 'ndk-bundle' {
			v := version_from_source_properties() or { '' }
			if v != '' {
				if version == v {
					return root()
				}
			}
			return '' // TODO make everything return optionals
		}
		return root()
	}
	return os.join_path(root(), version)
}

// found returns `true` if a NDK is found.
pub fn found() bool {
	return root() != ''
}

// is_side_by_side returns `true` if the NDK is installed
// in "side-by-side" form in the SDK.
pub fn is_side_by_side() bool {
	return os.real_path(os.join_path(sdk.root(), 'ndk')) == os.real_path(os.join_path(root()))
}

pub fn versions_available() []string {
	if !is_side_by_side() {
		v := version_from_source_properties() or { '' }
		if v != '' {
			return [v]
		}
		return [os.file_name(root())]
	}
	return util.ls_sorted(root())
}

pub fn has_version(version string) bool {
	if !is_side_by_side() {
		if version != 'ndk-bundle' {
			v := version_from_source_properties() or { '' }
			if v != '' {
				return v == version
			}
		}
		return os.file_name(root()) == version
	}
	return version in versions_available()
}

fn min_version_supported_by_vab() string {
	uos := os.user_os()
	return match uos {
		'windows' {
			'21.4.7075529'
		}
		'macos' {
			'21.3.6528147'
		}
		'linux' {
			'21.1.6352462'
		}
		else {
			'0.0.0'
		}
	}
}

// host_arch returns the host architecture string for the platform which `vab` was compiled on.
@[inline]
pub fn host_arch() string {
	$if linux {
		return 'linux-x86_64'
	}
	$if macos {
		return 'darwin-x86_64'
	}
	$if windows {
		return 'windows-x86_64'
	}
	$if termux {
		return 'linux-aarch64'
	}
	return 'unknown'
}

// arch_to_instruction_set maps `arch` to an instruction set
// Example: assert ndk.arch_to_instruction_set('x86') == 'i686'
@[inline]
pub fn arch_to_instruction_set(arch string) string {
	return match arch {
		'armeabi-v7a' { 'armv7a' }
		'arm64-v8a' { 'aarch64' }
		'x86' { 'i686' }
		'x86_64' { 'x86_64' }
		else { '' }
	}
}

// bin_path returns the absolute path to the host architecture's `bin` directory.
// As an example: `/path/to/ndk/toolchains/llvm/prebuilt/linux-x86_64/bin`.
@[inline]
pub fn bin_path(ndk_version string) string {
	return os.join_path(root_version(ndk_version), 'toolchains', 'llvm', 'prebuilt', host_arch(),
		'bin')
}

// compiler_min_api returns a compiler with the lowest API level available for `arch` in `ndk_version`.
pub fn compiler_min_api(lang_type CompilerLanguageType, ndk_version string, arch string) !string {
	available_compilers := available_ndk_compilers_by_api(lang_type, ndk_version, arch)
	mut keys := available_compilers.keys().map(it.int())
	keys.sort()
	if keys.len == 0 {
		return error(@MOD + '.' + @FN +
			' could not locate ${lang_type} compiler for architecture "${arch}". Available compilers: ${available_compilers}.')
	}
	if compiler := available_compilers[keys.first().str()] {
		return compiler
	}
	// Something must be wrong with the NDK
	return error(@MOD + '.' + @FN +
		' couldn\'t locate ${lang_type} compiler for architecture "${arch}". Available compilers: ${available_compilers}. The NDK might be corrupt.')
}

// compiler_max_api returns a compiler with the highest API level available for `arch` in `ndk_version`.
pub fn compiler_max_api(lang_type CompilerLanguageType, ndk_version string, arch string) !string {
	available_compilers := available_ndk_compilers_by_api(lang_type, ndk_version, arch)
	mut keys := available_compilers.keys().map(it.int())
	keys.sort()
	if keys.len == 0 {
		return error(@MOD + '.' + @FN +
			' could not locate ${lang_type} compiler for architecture "${arch}". Available compilers: ${available_compilers}.')
	}
	if compiler := available_compilers[keys.last().str()] {
		return compiler
	}
	// Something must be wrong with the NDK
	return error(@MOD + '.' + @FN +
		' couldn\'t locate ${lang_type} compiler for architecture "${arch}". Available compilers: ${available_compilers}. The NDK might be corrupt.')
}

pub fn compiler(lang_type CompilerLanguageType, ndk_version string, arch string, api_level string) !string {
	available_compilers := available_ndk_compilers_by_api(lang_type, ndk_version, arch)
	if compiler := available_compilers[api_level] {
		return compiler
	}

	// Some setups (E.g. some CI servers) the max API level reported by the default SDK will be higher than
	// what the default NDK supports - report a descriptive error.
	mut other_api_level_supported_hint := '.'
	if available_compilers.len > 0 {
		other_api_level_supported_hint = ' use compiler_(min/max)_api() or use another API level (--api <level>).\nNDK "${ndk_version}" supports API levels: ${available_compilers.keys()}'
	}
	return error(@MOD + '.' + @FN +
		' couldn\'t locate C compiler for architecture "${arch}" at API level "${api_level}". You could try with a NDK version > "${ndk_version}"${other_api_level_supported_hint}')
}

fn available_ndk_compilers_by_api(lang_type CompilerLanguageType, ndk_version string, arch string) map[string]string {
	mut compilers := map[string]string{}
	compiler_bin_path := bin_path(ndk_version)
	if os.is_dir(compiler_bin_path) {
		from := i16(min_api_available(ndk_version).int())
		to := i16(max_api_available(ndk_version).int()) + 1
		if to > from {
			for level in from .. to {
				mut compiler := os.join_path(compiler_bin_path, compiler_triplet(arch) +
					'${level}-clang')
				if lang_type == .cpp {
					compiler += '++'
				}
				$if windows {
					compiler += '.cmd'
				}
				if os.is_file(compiler) {
					compilers['${level}'] = compiler
				}
			}
		}
	}
	return compilers
}

pub fn tool(tool_type Tool, ndk_version string, arch string) !string {
	match tool_type {
		.ar {
			mut eabi := ''
			mut arch_is := arch_to_instruction_set(arch)
			if arch == 'armeabi-v7a' {
				arch_is = 'arm'
				eabi = 'eabi'
			}
			path := bin_path(ndk_version)
			if os.is_dir(path) {
				// NOTE: these *linux-android*-ar tools was deprecated in NDK r22 and removed in r23
				mut ar := os.join_path(path, arch_is + '-linux-android${eabi}-ar')
				$if windows {
					ar += '.cmd' // TODO validate if this is correct
				}
				if os.is_file(ar) {
					return ar
				}
				// Try `llvm-ar` which was introduced as default in NDK r22 (https://github.com/android/ndk/wiki/Changelog-r22)
				ar = os.join_path(path, 'llvm-ar')
				$if windows {
					ar += '.exe'
				}
				if os.is_file(ar) {
					return ar
				}
			}
		}
	}
	return error(@MOD + '.' + @FN +
		' couldn\'t locate "${tool_type}" tool for architecture "${arch}". You could try with a NDK version > "${ndk_version}"')
}

pub fn compiler_triplet(arch string) string {
	mut eabi := ''
	arch_is := arch_to_instruction_set(arch)
	if arch == 'armeabi-v7a' {
		eabi = 'eabi'
	}
	return arch_is + '-linux-android${eabi}'
}

pub fn libs_path(ndk_version string, arch string, api_level string) !string {
	mut host_architecture := host_arch()
	mut arch_is := arch_to_instruction_set(arch)

	mut eabi := ''
	if arch == 'armeabi-v7a' {
		eabi = 'eabi'
		arch_is = 'arm'
	}

	mut libs_path := os.join_path(root_version(ndk_version), 'toolchains', 'llvm', 'prebuilt',
		host_architecture, 'sysroot', 'usr', 'lib', arch_is + '-linux-android' + eabi,
		api_level)

	if !os.is_dir(libs_path) {
		return error(@MOD + '.' + @FN +
			' couldn\'t locate libraries path "${libs_path}". You could try with a newer NDK version.')
	}

	return libs_path
}

pub fn sysroot_path(ndk_version string) !string {
	// NOTE "$ndk_root/sysroot/usr/include" was deprecated since NDK r19
	mut sysroot_path := os.join_path(root_version(ndk_version), 'toolchains', 'llvm',
		'prebuilt', host_arch(), 'sysroot')

	if !os.is_dir(sysroot_path) {
		return error(@MOD + '.' + @FN +
			' couldn\'t locate sysroot at "${sysroot_path}". You could try with a newer NDK version (>= r19).')
	}

	return sysroot_path
}

pub fn min_api_available(version string) string {
	if !found() {
		return ''
	}
	platforms := read_platforms_json(version) or { return '' }
	platform := platforms['min'] or { return '' }
	return platform.str()
}

pub fn max_api_available(version string) string {
	if !found() {
		return ''
	}
	platforms := read_platforms_json(version) or { return '' }
	platform := platforms['max'] or { return '' }
	return platform.str()
}

pub fn available_apis_by_arch(ndk_version string) map[string][]string {
	mut arch_apis := map[string][]i16{}

	compiler_bin_path := bin_path(ndk_version)
	if os.is_dir(compiler_bin_path) {
		from := i16(min_api_available(ndk_version).int())
		to := i16(max_api_available(ndk_version).int()) + 1
		if to > from {
			for arch in supported_archs {
				for level in from .. to {
					mut compiler := os.join_path(compiler_bin_path, compiler_triplet(arch) +
						'${level}-clang')
					if os.is_file(compiler) {
						arch_apis['${arch}'] << level
					}
				}
				arch_apis['${arch}'].sort(a > b)
			}
		}
	}
	mut arch_apis_result := map[string][]string{}
	for arch, apis in arch_apis {
		arch_apis_result['${arch}'] = apis.map(it.str())
	}
	return arch_apis_result
}

pub fn meta_dir(version string) string {
	if !found() {
		return ''
	}
	return os.join_path(root_version(version), 'meta')
}

fn read_platforms_json(version string) ?map[string]json2.Any {
	mut platforms_json_file := cache.get_string(@MOD + '.' + @FN + '${version}')
	if platforms_json_file != '' {
		platforms_json := json2.raw_decode(platforms_json_file) or { return none }
		platforms := platforms_json.as_map()
		return platforms
	}
	platforms_json_path := os.join_path(meta_dir(version), 'platforms.json')
	platforms_json_file = os.read_file(platforms_json_path) or { return none }
	platforms_json := json2.raw_decode(platforms_json_file) or { return none }
	platforms := platforms_json.as_map()
	cache.set_string(@MOD + '.' + @FN + '${version}', platforms_json_file)
	return platforms
}

fn version_from_source_properties() ?string {
	cached_version := cache.get_string(@MOD + '.' + @FN)
	if cached_version != '' {
		return cached_version
	}
	lines := read_source_properties()?
	for line in lines {
		if line.contains('Pkg.Revision') {
			v := line.all_after_last('=').trim_space()
			if v == '' {
				return none
			} else {
				cache.set_string(@MOD + '.' + @FN, v)
				return v
			}
		}
	}
	return none
}

fn read_source_properties() ?[]string {
	if found() {
		sp_file := os.join_path(root(), 'source.properties')
		if os.is_file(sp_file) {
			return os.read_lines(sp_file) or { return none }
		}
	}
	return none
}
