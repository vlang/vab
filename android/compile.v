// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import vxt
import android.ndk
import android.util
import crypto.md5

pub const (
	default_archs = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
)

pub struct CompileOptions {
	verbosity int // level of verbosity
	cache     bool
	cache_key string
	// env
	work_dir string // temporary work directory
	input    string
	//
	archs       []string // compile for these CPU architectures
	v_flags     []string // flags to pass to the v compiler
	c_flags     []string // flags to pass to the C compiler(s)
	ndk_version string   // version of the Android NDK to compile against
	lib_name    string   // filename of the resulting .so ('${lib_name}.so')
	api_level   string   // Android API level to use when compiling
}

pub fn compile(opt CompileOptions) bool {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		panic('$err_sig: failed making directory "$opt.work_dir". ' + err)
	}
	build_dir := os.join_path(opt.work_dir, 'build')

	if opt.verbosity > 0 {
		println('Compiling V to C')
	}
	vexe := vxt.vexe()
	v_output_file := os.join_path(opt.work_dir, 'v_android.c')

	// Dump C flags
	vcflags_file := os.join_path(opt.work_dir, 'v.cflags')
	os.rm(vcflags_file) or { }
	mut v_cmd := [vexe]
	if !opt.cache {
		v_cmd << '-nocache'
	}
	v_cmd << opt.v_flags
	v_cmd << [
		'-dump-c-flags',
		'"$vcflags_file"',
		'-os android',
		'-apk',
	]
	v_cmd << opt.input
	util.verbosity_print_cmd(v_cmd, opt.verbosity)
	util.run(v_cmd)
	//

	v_cmd = [vexe]
	if !opt.cache {
		v_cmd << '-nocache'
	}
	v_cmd << opt.v_flags
	v_cmd << [
		'-os android',
		'-apk',
		'-o "$v_output_file"',
	]
	v_cmd << opt.input
	util.verbosity_print_cmd(v_cmd, opt.verbosity)
	v_comp_res := util.run_or_exit(v_cmd)
	if opt.verbosity > 1 {
		println(v_comp_res)
	}
	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	if opt.cache && os.exists(build_dir) && os.exists(v_output_file) {
		mut bytes := os.read_bytes(v_output_file) or {
			panic('$err_sig: failed reading "$v_output_file". ' + err)
		}
		bytes << '$opt.str()-$opt.cache_key'.bytes()
		hash = md5.sum(bytes).hex()

		if os.exists(hash_file) {
			prev_hash := os.read_file(hash_file) or { '' }
			if hash == prev_hash {
				if opt.verbosity > 1 {
					println('Skipping compile. Hashes match $hash')
				}
				return true
			}
		}
	}

	if hash != '' && os.exists(v_output_file) {
		if opt.verbosity > 2 {
			println('Writing new hash $hash')
		}
		os.rm(hash_file) or { }
		mut hash_fh := os.open_file(hash_file, 'w+', 0o700) or {
			panic('$err_sig: failed opening "$hash_file". ' + err)
		}
		hash_fh.write(hash.bytes()) or { panic('$err_sig: failed writing to "$hash_file". ' + err) }
		hash_fh.close()
	}
	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or { }
	}
	os.mkdir(build_dir) or { panic(err) }

	v_home := vxt.home()

	mut archs := []string{}
	if opt.archs.len > 0 {
		for a in opt.archs {
			if a in android.default_archs {
				archs << a.trim_space()
			} else {
				eprintln('Architechture "$a" not one of $android.default_archs')
			}
		}
	}
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = android.default_archs.clone()
	}

	if opt.verbosity > 0 {
		println('Compiling C to $archs')
	}
	// For all compilers
	mut cflags := opt.c_flags
	mut includes := []string{}
	mut defines := []string{}
	mut ldflags := []string{}
	mut sources := []string{}

	// Read in the dumped cflags
	vcflags := os.read_file(vcflags_file) or {
		panic('$err_sig: failed writing C flags to "$vcflags_file". ' + err)
	}
	for line in vcflags.split('\n') {
		if line.contains('.tmp.c') || line.ends_with('.o"') {
			continue
		}
		if line.starts_with('-I') {
			includes << line
		}
		if line.starts_with('-l') {
			ldflags << line
		}
	}

	// ... still a bit of a mess
	if '-prod' in opt.v_flags {
		cflags << ['-Os']
	} else {
		cflags << ['-O0']
	}
	cflags << ['-fPIC', '-fvisibility=hidden', '-ffunction-sections', '-fdata-sections', '-ferror-limit=1']

	cflags << ['-Wall', '-Wextra', '-Wno-unused-variable', '-Wno-unused-parameter', '-Wno-unused-result',
		'-Wno-unused-function', '-Wno-missing-braces', '-Wno-unused-label', '-Werror=implicit-function-declaration']

	// TODO Here to make the compilers shut up :/
	cflags << ['-Wno-braced-scalar-init', '-Wno-incompatible-pointer-types', '-Wno-implicitly-unsigned-literal',
		'-Wno-pointer-sign', '-Wno-enum-conversion', '-Wno-int-conversion', '-Wno-int-to-pointer-cast',
		'-Wno-sign-compare', '-Wno-return-type', '-Wno-extra-tokens']

	defines << ['-DAPPNAME="$opt.lib_name"']
	defines << ['-DANDROID', '-D__ANDROID__', '-DANDROIDVERSION=$opt.api_level']

	// TODO if full_screen
	defines << ['-DANDROID_FULLSCREEN']

	ndk_root := ndk.root_version(opt.ndk_version)
	// NDK headers
	includes << ['-I"$ndk_root/sysroot/usr/include"', '-I"$ndk_root/sysroot/usr/include/android"']

	// Sokol
	if '-cg' in opt.v_flags || '-g' in opt.v_flags {
		defines << ['-DSOKOL_DEBUG']
	}
	// TODO support both GLES2 & GLES3 - GLES2 should be default
	defines << ['-DSOKOL_GLES2']
	//defines << ['-DSOKOL_GLES3']
	ldflags << ['-uANativeActivity_onCreate', '-usokol_main']

	// stb_image
	// includes << ['-I"$v_home/thirdparty/stb_image"']
	sources << ['"$v_home/thirdparty/stb_image/stbi.c"']

	// misc
	ldflags << ['-llog', '-landroid', '-lEGL', '-lGLESv2', '-lm']

	ldflags << ['-shared'] // <- Android loads native code via a library in NativeActivity

	mut cflags_arm64 := ['-m64']
	mut cflags_arm32 := ['-mfloat-abi=softfp', '-m32']
	mut cflags_x86 := ['-march=i686', '-mtune=intel', '-mssse3', '-mfpmath=sse', '-m32']
	mut cflags_x86_64 := ['-march=x86-64', '-msse4.2', '-mpopcnt', '-m64', '-mtune=intel']

	mut arch_cc := map[string]string{}
	mut arch_libs := map[string]string{}
	for arch in archs {
		compiler := ndk.compiler(opt.ndk_version, arch, opt.api_level) or {
			panic('$err_sig: failed getting NDK compiler. ' + err)
		}
		arch_cc[arch] = compiler

		arch_lib := ndk.libs_path(opt.ndk_version, arch, opt.api_level) or {
			panic('$err_sig: failed getting NDK libs path. ' + err)
		}
		arch_libs[arch] = arch_lib
	}

	mut arch_cflags := map[string][]string{}
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	// Cross compile .so lib files
	for arch in archs {
		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir) or {
			panic('$err_sig: failed making directory "$arch_lib_dir". ' + err)
		}

		build_cmd := [arch_cc[arch], cflags.join(' '), includes.join(' '),
			defines.join(' '), sources.join(' '), arch_cflags[arch].join(' '), '-o "$arch_lib_dir/lib${opt.lib_name}.so"',
			v_output_file, '-L"' + arch_libs[arch] + '"', ldflags.join(' ')]
		util.verbosity_print_cmd(build_cmd, opt.verbosity)
		comp_res := util.run_or_exit(build_cmd)

		if opt.verbosity > 1 {
			println(comp_res)
		}
	}

	if 'armeabi-v7a' in archs {
		// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
		armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
		os.mkdir_all(armeabi_lib_dir) or {
			panic('$err_sig: failed making directory "$armeabi_lib_dir". ' + err)
		}

		armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'lib${opt.lib_name}.so')
		armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.lib_name}.so')
		os.cp(armeabi_lib_src, armeabi_lib_dst) or {
			panic('$err_sig: failed copying "$armeabi_lib_src" to "$armeabi_lib_dst". ' + err)
		}
	}
	return true
}
