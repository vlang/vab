// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module ndk

const ndk_21_default_general_flags = ['-g', '-DANDROID', '-fdata-sections', '-ffunction-sections',
	'-funwind-tables', '-fstack-protector-strong', '-no-canonical-prefixes']
const ndk_21_default_general_ld_flags = ['-Wl,--exclude-libs,libgcc.a',
	'-Wl,--exclude-libs,libgcc_real.a', '-Wl,--exclude-libs,libatomic.a']
const ndk_supported_cpp_features = ['rtti', 'exceptions', 'no-rtti', 'no-exceptions']

@[params]
pub struct FlagConfig {
pub:
	pic                          bool = true // TODO
	debug                        bool = true // false = release
	platform_level               int  = 21
	arch                         string @[required]
	neon                         bool
	arm_mode                     string               = 'thumb' // or 'arm'
	lang                         CompilerLanguageType = .c
	ld                           string               = 'lld'
	stl                          string               = 'c++_static' // or 'c++_shared' 'none' 'system'
	cpp_features                 []string             = ['rtti', 'exceptions']
	allow_undefined_symbols      bool
	disable_format_string_checks bool
}

pub struct FlagGen {
pub:
	ndk_version string @[required]
}

pub struct FlagResult {
pub:
	flags        []string
	ld_flags     []string
	ld_flags_exe []string
}

// compiler_flags returns a FlagGen `struct`.
pub fn compiler_flag_generator(ndk_version string) FlagGen {
	return FlagGen{
		ndk_version: ndk_version
	}
}

// compiler_flags_from_config returns a FlagResult.
pub fn compiler_flags_from_config(ndk_version string, flag_config FlagConfig) !FlagResult {
	gen := compiler_flag_generator(ndk_version)
	return FlagResult{
		flags:        gen.flags(flag_config)!
		ld_flags:     gen.ld_flags(flag_config)!
		ld_flags_exe: gen.ld_flags_exe(flag_config)!
	}
}

// general_flags returns the general flags for the NDK version.
pub fn (f FlagGen) general_flags() []string {
	return ndk_21_default_general_flags.clone()
}

// flags returns the NDK version's recommended flags for the given `flag_config`.
pub fn (f FlagGen) flags(flag_config FlagConfig) ![]string {
	mut flags := []string{}
	cnf := flag_config
	if cnf.lang == .cpp {
		match cnf.stl {
			'system' {
				flags << '-stdlib=libstdc++'
			}
			'c++_static' {}
			'c++_shared' {}
			'none' {
				flags << '-nostdinc++'
			}
			else {
				return error('Invalid Android STL: ${cnf.stl}')
			}
		}
		if cnf.stl.starts_with('c++_') && cnf.arch.starts_with('armeabi') {
			flags << '-Wl,--exclude-libs,libunwind.a'
		}
		if cnf.cpp_features.len > 0 {
			for cpp_feature in cnf.cpp_features {
				if cpp_feature !in ndk_supported_cpp_features {
					return error('Invalid Android C++ feature: ${cpp_feature}')
				}
				flags << '-f${cpp_feature}'
			}
		}
	}
	if cnf.debug {
		flags << '-O0'
		// if clang:
		flags << '-fno-limit-debug-info'
	} else { // Release
		if cnf.arch.starts_with('armeabi') && cnf.arm_mode == 'thumb' {
			flags << '-Oz'
		} else {
			flags << '-O2'
		}
		flags << '-DNDEBUG'
	}
	if cnf.platform_level < 24 {
		flags << '-mstackrealign'
	}
	flags << '-D_FORTIFY_SOURCE=2'

	if cnf.arch.starts_with('armeabi') {
		flags << '-march=armv7-a'
		match cnf.arm_mode {
			'thumb' {
				flags << '-mthumb'
			}
			'arm' {}
			else {
				return error('Invalid Android ARM mode: ${cnf.arm_mode}')
			}
		}
		if cnf.arch == 'armeabi-v7a' && !cnf.neon {
			flags << '-mfpu=vfpv3-d16'
		}
	}

	if cnf.disable_format_string_checks {
		flags << '-Wno-error=format-security'
	} else {
		flags << '-Wformat -Werror=format-security'
	}
	if cnf.pic {
		flags << '-fPIC'
	}

	return flags
}

// ld_flags returns the NDK version's recommended linker flags for the given `flag_config`.
pub fn (f FlagGen) ld_flags(flag_config FlagConfig) ![]string {
	cnf := flag_config
	mut ld_flags := []string{}
	ld_flags << ndk_21_default_general_ld_flags.clone()
	if flag_config.ld == 'lld' {
		ld_flags << '-fuse-ld=lld'
		ld_flags << '-Wl,--build-id=sha1'
		if cnf.platform_level < 29 {
			ld_flags << '-Wl,--no-rosegment'
		}
	} else {
		ld_flags << '-Wl,--build-id'
	}
	ld_flags << '-Wl,--fatal-warnings'
	if cnf.lang == .cpp {
		match cnf.stl {
			'system' {
				if cnf.cpp_features.len == 0 {
					ld_flags << '-lc++abi'
					if cnf.platform_level < 21 {
						ld_flags << '-landroid_support'
					}
				}
			}
			'c++_static' {
				ld_flags << '-static-libstdc++'
			}
			'c++_shared' {}
			'none' {
				ld_flags << '-nostdlib++'
			}
			else {
				return error('Invalid Android STL: ${cnf.stl}')
			}
		}
	}
	ld_flags << '-latomic -lm'

	if !cnf.allow_undefined_symbols {
		ld_flags << '-Wl,--no-undefined'
	}
	ld_flags << '-Qunused-arguments'
	return ld_flags
}

// ld_flags_exe returns the NDK version's recommended linker flags for the given `flag_config` when generating executables.
pub fn (f FlagGen) ld_flags_exe(flag_config FlagConfig) ![]string {
	mut ld_flags := []string{}
	ld_flags << '-Wl,--gc-sections'
	return ld_flags
}
