// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import runtime
import sync.pool
import vab.vxt
import vab.android.ndk
import vab.android.util
import crypto.md5

pub const (
	supported_target_archs  = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
	default_archs           = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
	supported_gles_versions = [2, 3]
	default_gles_version    = 2
)

pub struct CompileOptions {
pub:
	verbosity int // level of verbosity
	cache     bool
	cache_key string
	parallel  bool = true // Run, what can be run, in parallel
	// env
	work_dir string // temporary work directory
	input    string
	//
	is_prod          bool
	gles_version     int = android.default_gles_version
	no_printf_hijack bool   // Do not let V redefine printf for log output aka. V_ANDROID_LOG_PRINT
	archs            []string // compile for these CPU architectures
	v_flags          []string // flags to pass to the v compiler
	c_flags          []string // flags to pass to the C compiler(s)
	ndk_version      string   // version of the Android NDK to compile against
	lib_name         string   // filename of the resulting .so ('${lib_name}.so')
	api_level        string   // Android API level to use when compiling
	min_sdk_version  int = default_min_sdk_version
}

struct ShellJob {
	cmd      []string
	env_vars map[string]string
}

struct ShellJobResult {
	job    ShellJob
	result os.Result
}

fn async_run(pp &pool.PoolProcessor, idx int, wid int) &ShellJobResult {
	item := pp.get_item<ShellJob>(idx)
	return sync_run(item)
}

fn sync_run(item ShellJob) &ShellJobResult {
	for key, value in item.env_vars {
		os.setenv(key, value, true)
	}
	res := util.run(item.cmd)
	return &ShellJobResult{
		job: item
		result: res
	}
}

pub fn compile(opt CompileOptions) bool {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		panic('$err_sig: failed making directory "$opt.work_dir". $err')
	}
	build_dir := os.join_path(opt.work_dir, 'build')
	mut jobs := []ShellJob{}

	if opt.verbosity > 0 {
		println('Compiling V to C' + if opt.parallel { ' in parallel' } else { '' })
		if opt.v_flags.len > 0 {
			println('V flags: `$opt.v_flags`')
		}
	}
	vexe := vxt.vexe()
	v_output_file := os.join_path(opt.work_dir, 'v_android.c')

	// Dump modules and C flags to files
	v_cflags_file := os.join_path(opt.work_dir, 'v.cflags')
	os.rm(v_cflags_file) or {}
	v_dump_modules_file := os.join_path(opt.work_dir, 'v.modules')
	os.rm(v_dump_modules_file) or {}

	mut v_cmd := [vexe]
	if !opt.cache {
		v_cmd << '-nocache'
	}

	v_cmd << opt.v_flags
	v_cmd << [
		'-gc none',
		'-cc clang',
		'-dump-modules "$v_dump_modules_file"',
		'-dump-c-flags "$v_cflags_file"',
		'-os android',
		'-apk',
	]
	v_cmd << opt.input

	// NOTE this command fails with a C compile error but the output we need is still
	// present... Yes - not exactly pretty.
	// VCROSS_COMPILER_NAME is needed (on at least Windows)
	jobs << ShellJob{
		env_vars: {
			'VCROSS_COMPILER_NAME': ndk.compiler(.c, opt.ndk_version, 'arm64-v8a', opt.api_level) or {
				''
			}
		}
		cmd: v_cmd.clone()
	}

	// Compile to Android compatible C file
	v_cmd = [vexe]
	if !opt.cache {
		v_cmd << '-nocache'
	}
	v_cmd << opt.v_flags
	v_cmd << [
		'-gc none',
		'-os android',
		'-apk',
		'-o "$v_output_file"',
	]
	v_cmd << opt.input
	jobs << ShellJob{
		cmd: v_cmd.clone()
	}

	if opt.parallel {
		mut pp := pool.new_pool_processor(maxjobs: runtime.nr_cpus() - 1, callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results<ShellJobResult>() {
			util.verbosity_print_cmd(job_res.job.cmd, opt.verbosity)
			if '-cc clang' !in job_res.job.cmd {
				util.exit_on_bad_result(job_res.result, '${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
				if opt.verbosity > 2 {
					println(job_res.result.output)
				}
			}
		}
	} else {
		for job in jobs {
			util.verbosity_print_cmd(job.cmd, opt.verbosity)
			job_res := sync_run(job)
			if '-cc clang' !in job_res.job.cmd {
				util.exit_on_bad_result(job_res.result, '${job.cmd[0]} failed with return code $job_res.result.exit_code')
				if opt.verbosity > 2 {
					println(job_res.result.output)
				}
			}
		}
	}
	jobs.clear()

	// Parse imported modules from dump
	mut imported_modules := os.read_file(v_dump_modules_file) or {
		panic('$err_sig: failed reading module dump file "$v_dump_modules_file". $err')
	}.split('\n').filter(it != '')
	imported_modules.sort()
	if opt.verbosity > 2 {
		println('Imported modules:\n' + imported_modules.join('\n'))
	}
	if imported_modules.len == 0 {
		panic('$err_sig: empty module dump file "$v_dump_modules_file".')
	}

	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	if opt.cache && os.exists(build_dir) && os.exists(v_output_file) {
		mut bytes := os.read_bytes(v_output_file) or {
			panic('$err_sig: failed reading "$v_output_file". $err')
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
		os.rm(hash_file) or {}
		mut hash_fh := os.open_file(hash_file, 'w+', 0o700) or {
			panic('$err_sig: failed opening "$hash_file". $err')
		}
		hash_fh.write(hash.bytes()) or { panic('$err_sig: failed writing to "$hash_file". $err') }
		hash_fh.close()
	}
	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or {}
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

	// For all compilers
	mut cflags := opt.c_flags
	mut includes := []string{}
	mut defines := []string{}
	mut ldflags := []string{}
	mut sources := []string{}

	// Read in the dumped cflags
	vcflags := os.read_file(v_cflags_file) or {
		panic('$err_sig: failed reading C flags to "$v_cflags_file". $err')
	}
	for line in vcflags.split('\n') {
		if line.contains('.tmp.c') || line.ends_with('.o"') {
			continue
		}
		if line.starts_with('-D') {
			defines << line
		}
		if line.starts_with('-I') {
			if line.contains('/usr/') {
				continue
			}
			includes << line
		}
		if line.starts_with('-l') {
			if line.contains('-lgc') {
				continue
			}
			ldflags << line
		}
	}

	// ... still a bit of a mess
	if opt.is_prod {
		cflags << ['-Os']
	} else {
		cflags << ['-O0']
	}
	cflags << ['-fPIC', '-fvisibility=hidden', '-ffunction-sections', '-fdata-sections',
		'-ferror-limit=1']

	cflags << ['-Wall', '-Wextra', '-Wno-unused-variable', '-Wno-unused-parameter',
		'-Wno-unused-result', '-Wno-unused-function', '-Wno-missing-braces', '-Wno-unused-label',
		'-Werror=implicit-function-declaration']

	// TODO Here to make the compiler(s) shut up :/
	cflags << ['-Wno-braced-scalar-init', '-Wno-incompatible-pointer-types',
		'-Wno-implicitly-unsigned-literal', '-Wno-pointer-sign', '-Wno-enum-conversion',
		'-Wno-int-conversion', '-Wno-int-to-pointer-cast', '-Wno-sign-compare', '-Wno-return-type',
		'-Wno-extra-tokens', '-Wno-unused-value']

	// NOTE This define allows V to redefine C's printf() - to let logging via println() etc. go
	// through Android device's system log (that adb logcat reads).
	if !opt.no_printf_hijack {
		if opt.verbosity > 1 {
			println('Define V_ANDROID_LOG_PRINT - (f)printf will be redefined...')
		}
		defines << '-DV_ANDROID_LOG_PRINT'
	}

	defines << '-DAPPNAME="$opt.lib_name"'
	defines << ['-DANDROID', '-D__ANDROID__', '-DANDROIDVERSION=$opt.api_level']

	// TODO if full_screen
	defines << '-DANDROID_FULLSCREEN'

	// Include NDK headers
	// NOTE "$ndk_root/sysroot/usr/include" was deprecated since NDK r19
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		panic('$err_sig: getting NDK sysroot path. $err')
	}
	includes << ['-I"' + os.join_path(ndk_sysroot, 'usr', 'include') + '"',
		'-I"' + os.join_path(ndk_sysroot, 'usr', 'include', 'android') + '"']

	is_debug_build := '-cg' in opt.v_flags || '-g' in opt.v_flags

	// Boehm-Demers-Weiser Garbage Collector (bdwgc / libgc)
	mut uses_gc := true // V default
	for v_flag in opt.v_flags {
		if v_flag.starts_with('-gc') {
			if v_flag.ends_with('none') {
				uses_gc = false
			}
			if opt.verbosity > 1 {
				println('Garbage collecting is $uses_gc via "$v_flag"')
			}
			break
		}
	}

	if uses_gc {
		includes << [
			'-I"' + os.join_path(v_home, 'thirdparty', 'libgc', 'include') + '"',
		]
		sources << ['"' + os.join_path(v_home, 'thirdparty', 'libgc', 'gc.c') + '"']
		if is_debug_build {
			defines << '-DGC_ASSERTIONS'
			defines << '-DGC_ANDROID_LOG'
		}
		defines << '-D_REENTRANT'
		defines << '-DUSE_MMAP' // Will otherwise crash with a message with a path to the lib in GC_unix_mmap_get_mem+528
	}

	// Sokol
	if is_debug_build {
		if opt.verbosity > 1 {
			println('Define SOKOL_DEBUG')
		}
		defines << '-DSOKOL_DEBUG'
	}

	if opt.verbosity > 1 {
		println('Using GLES $opt.gles_version')
	}
	if opt.gles_version == 3 {
		defines << ['-DSOKOL_GLES3']
	} else {
		defines << ['-DSOKOL_GLES2']
	}

	ldflags << ['-uANativeActivity_onCreate', '-usokol_main']

	// stb_image via `stbi` module
	if 'stbi' in imported_modules {
		if opt.verbosity > 1 {
			println('Including stb_image via stbi module')
		}
		// includes << ['-I"$v_home/thirdparty/stb_image"']
		sources << [
			'"' + os.join_path(v_home, 'thirdparty', 'stb_image', 'stbi.c') + '"',
		]
	}

	// cJson via `json` module
	if 'json' in imported_modules {
		if opt.verbosity > 1 {
			println('Including cJSON via json module')
		}
		includes << ['-I"' + os.join_path(v_home, 'thirdparty', 'cJSON') + '"']
		sources << [
			'"' + os.join_path(v_home, 'thirdparty', 'cJSON', 'cJSON.c') + '"',
		]
	}

	// misc
	ldflags << ['-llog', '-landroid', '-lEGL', '-lGLESv2', '-lm']

	ldflags << ['-shared'] // <- Android loads native code via a library in NativeActivity

	mut cflags_arm64 := ['-m64']
	mut cflags_arm32 := ['-mfloat-abi=softfp', '-m32']
	mut cflags_x86 := ['-march=i686', '-mssse3', '-mfpmath=sse', '-m32']
	mut cflags_x86_64 := ['-march=x86-64', '-msse4.2', '-mpopcnt', '-m64']

	mut arch_cc := map[string]string{}
	mut arch_libs := map[string]string{}
	for arch in archs {
		compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			panic('$err_sig: failed getting NDK compiler. $err')
		}
		arch_cc[arch] = compiler

		arch_lib := ndk.libs_path(opt.ndk_version, arch, opt.api_level) or {
			panic('$err_sig: failed getting NDK libs path. $err')
		}
		arch_libs[arch] = arch_lib
	}

	mut arch_cflags := map[string][]string{}
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	if opt.verbosity > 0 {
		println('Compiling C to $archs' + if opt.parallel { ' in parallel' } else { '' })
	}

	// Cross compile .so lib files
	for arch in archs {
		arch_lib_dir := os.join_path(build_dir, 'lib', arch)
		os.mkdir_all(arch_lib_dir) or {
			panic('$err_sig: failed making directory "$arch_lib_dir". $err')
		}

		build_cmd := [arch_cc[arch], cflags.join(' '), includes.join(' '),
			defines.join(' '), sources.join(' '), arch_cflags[arch].join(' '),
			'-o "$arch_lib_dir/lib${opt.lib_name}.so"', v_output_file, '-L"' + arch_libs[arch] + '"',
			ldflags.join(' ')]

		jobs << ShellJob{
			cmd: build_cmd
		}
	}

	if opt.parallel {
		mut pp := pool.new_pool_processor(maxjobs: runtime.nr_cpus() - 1, callback: async_run)
		pp.work_on_items(jobs)
		for job_res in pp.get_results<ShellJobResult>() {
			util.verbosity_print_cmd(job_res.job.cmd, opt.verbosity)
			util.exit_on_bad_result(job_res.result, '${job_res.job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				println(job_res.result.output)
			}
		}
	} else {
		for job in jobs {
			util.verbosity_print_cmd(job.cmd, opt.verbosity)
			job_res := sync_run(job)
			util.exit_on_bad_result(job_res.result, '${job.cmd[0]} failed with return code $job_res.result.exit_code')
			if opt.verbosity > 2 {
				println(job_res.result.output)
			}
		}
	}

	if 'armeabi-v7a' in archs {
		// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
		armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
		os.mkdir_all(armeabi_lib_dir) or {
			panic('$err_sig: failed making directory "$armeabi_lib_dir". $err')
		}

		armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'lib${opt.lib_name}.so')
		armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.lib_name}.so')
		os.cp(armeabi_lib_src, armeabi_lib_dst) or {
			panic('$err_sig: failed copying "$armeabi_lib_src" to "$armeabi_lib_dst". $err')
		}
	}
	return true
}
