module android

import os
import vxt

import android.ndk
import android.util
import crypto.md5

const (
	default_archs = ['arm64-v8a','armeabi-v7a','x86','x86_64']
)

pub struct CompileOptions {
	verbosity		int

	work_dir		string
	input			string

	archs			[]string
	v_flags			[]string
	c_flags			[]string

	ndk_version		string
	lib_name		string
	api_level		string
}

pub fn compile(opt CompileOptions) bool {
	os.mkdir_all(opt.work_dir)
	build_dir := os.join_path(opt.work_dir, 'build')

	if opt.verbosity > 0 {
		println('Compiling V to C')
	}
	vexe := vxt.vexe()
	v_output_file := os.join_path(opt.work_dir, 'v_android.c')
	mut v_cmd := [ vexe ]
	v_cmd << opt.v_flags
	v_cmd << [
		'-os android',
		'-apk',
		'-o "${v_output_file}"',
		opt.input
	]
	util.verbosity_print_cmd(v_cmd, opt.verbosity)
	v_comp_res := util.run_or_exit(v_cmd)
	if opt.verbosity > 1 {
		println(v_comp_res)
	}

	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	if os.exists(build_dir) && os.exists(v_output_file) {
		mut bytes := os.read_bytes(v_output_file) or { panic(err) }
		bytes << opt.str().bytes()
		hash = md5.sum(bytes).hex()

		if os.exists(hash_file) {
			prev_hash := os.read_file(hash_file) or { '' }
			if hash == prev_hash {
				if opt.verbosity > 2 {
					println('Skipping compile. Hashes match ${hash}')
				}
				return true
			}
		}

	}

	if hash != '' && os.exists(v_output_file) {
		if opt.verbosity > 2 {
			println('Writing new hash ${hash}')
		}
		os.rm(hash_file)
		mut hash_fh := os.open_file(hash_file, 'w+', 0o700) or { panic(err) }
		hash_fh.write(hash.bytes())
		hash_fh.close()
	}

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir)
	}
	os.mkdir(build_dir)

	v_home := vxt.home()

	mut archs := []string{}
	if opt.archs.len > 0 {
		for a in opt.archs {
			if a in default_archs {
				archs << a.trim_space()
			} else {
				eprintln('Architechture "${a}" not one of ${default_archs}')
			}
		}
	}
	// Compile sources for all Android archs if no valid archs found
	if archs.len <= 0 {
		archs = default_archs
	}

	if opt.verbosity > 0 {
		println('Compiling C to ${archs}')
	}

	// For all compilers
	mut cflags := opt.c_flags
	mut includes := []string{}
	mut defines := []string{}
	mut ldflags := []string{}
	mut sources := []string{}

	// ... still a bit of a mess
	if '-prod' in opt.v_flags {
		cflags << ['-Os']
	} else {
		cflags << ['-O0']
	}
	cflags << ['-fPIC','-fvisibility=hidden','-ffunction-sections','-fdata-sections','-ferror-limit=1']

	cflags << ['-Wall','-Wextra','-Wno-unused-variable','-Wno-unused-parameter','-Wno-unused-result','-Wno-unused-function','-Wno-missing-braces','-Wno-unused-label','-Werror=implicit-function-declaration']

	// TODO Here to make the compilers shut up :/
	cflags << ['-Wno-braced-scalar-init','-Wno-incompatible-pointer-types','-Wno-implicitly-unsigned-literal','-Wno-pointer-sign','-Wno-enum-conversion','-Wno-int-conversion','-Wno-int-to-pointer-cast','-Wno-sign-compare','-Wno-return-type']

	defines << ['-DAPPNAME="${opt.lib_name}"']
	defines << ['-DANDROID','-D__ANDROID__','-DANDROIDVERSION=${opt.api_level}']

	// TODO if full_screen
	defines << ['-DANDROID_FULLSCREEN']

	// NDK headers
	includes << ['-I"${ndk.root()}/sysroot/usr/include"','-I"${ndk.root()}/sysroot/usr/include/android"']

	// Sokol
	// TODO support both GLES2 & GLES3 - GLES2 should be default - trust me
	// TODO Toggle debug - probably follow v -prod flag somehow
	defines << ['-DSOKOL_DEBUG','-DSOKOL_GLES2']
	ldflags << ['-uANativeActivity_onCreate','-usokol_main']
	includes << ['-I"${v_home}/thirdparty/sokol"','-I"${v_home}/thirdparty/sokol/util"']

	// stb_image
	includes << ['-I"${v_home}/thirdparty/stb_image"']
	sources << ['"${v_home}/thirdparty/stb_image/stbi.c"']

	// fontstash
	includes << ['-I"${v_home}/thirdparty/fontstash"']

	// misc
	ldflags << ['-llog','-landroid','-lEGL','-lGLESv2','-lm']

	ldflags << ['-shared'] // <- Android loads native code via a library in NativeActivity

	mut cflags_arm64 := ['-m64']
	mut cflags_arm32 := ['-mfloat-abi=softfp','-m32']
	mut cflags_x86 := ['-march=i686','-mtune=intel','-mssse3','-mfpmath=sse','-m32']
	mut cflags_x86_64 := ['-march=x86-64','-msse4.2','-mpopcnt','-m64','-mtune=intel']

	mut arch_cc := map[string]string
	mut arch_libs := map[string]string
	for arch in archs {
		compiler := ndk.compiler(opt.ndk_version, arch, opt.api_level) or { panic(err) }
		arch_cc[arch] = compiler

		arch_lib := ndk.libs_path(opt.ndk_version, arch, opt.api_level) or { panic(err) }
		arch_libs[arch] = arch_lib
	}

	mut arch_cflags := map[string][]string
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	// Cross compile .so lib files
	for arch in archs {

		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir)

		build_cmd := [ arch_cc[arch],
			cflags.join(' '),
			includes.join(' '),
			defines.join(' '),
			sources.join(' '),
			arch_cflags[arch].join(' '),
			'-o "${arch_lib_dir}/lib${opt.lib_name}.so"',
			v_output_file,
			'-L"'+arch_libs[arch]+'"',
			ldflags.join(' ')
		]
		util.verbosity_print_cmd(build_cmd, opt.verbosity)
		comp_res := util.run_or_exit(build_cmd)

		if opt.verbosity > 1 {
			println(comp_res)
		}
	}

	if 'armeabi-v7a' in archs {
		// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
		armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
		os.mkdir_all(armeabi_lib_dir)

		armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a','lib${opt.lib_name}.so')
		armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.lib_name}.so')
		os.cp( armeabi_lib_src, armeabi_lib_dst) or { panic(err) }
	}
	return true
}
