// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import vab.vxt
import vab.util as job_util
import vab.android.ndk
import vab.android.util
import crypto.md5

pub const supported_target_archs = ndk.supported_archs
pub const default_archs = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
pub const supported_gles_versions = [3]
pub const default_gles_version = 3

pub struct CompileOptions {
pub:
	verbosity   int // level of verbosity
	cache       bool
	cache_key   string
	parallel    bool = true // Run, what can be run, in parallel
	no_so_build bool // Do not build the .so file, can be used if you're only interested in the object files
	// env
	work_dir string // temporary work directory
	input    string
	//
	is_prod         bool
	gles_version    int = default_gles_version
	archs           []string // compile for these CPU architectures
	v_flags         []string // flags to pass to the v compiler
	c_flags         []string // flags to pass to the C compiler(s)
	ndk_version     string   // version of the Android NDK to compile against
	lib_name        string   // filename of the resulting .so ('${lib_name}.so')
	api_level       string   // Android API level to use when compiling
	min_sdk_version int = default_min_sdk_version
}

// verbose prints `msg` to STDOUT if `CompileOptions.verbosity` level is >= `verbosity_level`.
pub fn (co &CompileOptions) verbose(verbosity_level int, msg string) {
	if co.verbosity >= verbosity_level {
		println(msg)
	}
}

// uses_gc returns true if a `-gc` flag is found among the passed v flags.
pub fn (opt CompileOptions) uses_gc() bool {
	mut uses_gc := true // V default
	for v_flag in opt.v_flags {
		if v_flag.starts_with('-gc') {
			if v_flag.ends_with('none') {
				uses_gc = false
			}
			break
		}
	}
	return uses_gc
}

// has_v_d_flag returns true if `d_flag` (-d <ident>) can be found among the passed v flags.
pub fn (opt CompileOptions) has_v_d_flag(d_flag string) bool {
	for v_flag in opt.v_flags {
		if v_flag.contains('-d ${d_flag}') {
			return true
		}
	}
	return false
}

// is_debug_build returns true if either `-cg` or `-g` flags is found among the passed v flags.
pub fn (opt CompileOptions) is_debug_build() bool {
	return '-cg' in opt.v_flags || '-g' in opt.v_flags
}

// archs returns an array of target architectures.
pub fn (opt CompileOptions) archs() ![]string {
	mut archs := []string{}
	if opt.archs.len > 0 {
		for arch in opt.archs.map(it.trim_space()) {
			if arch in default_archs {
				archs << arch
			} else {
				return error(@MOD + '.' + @FN +
					': Architechture "${arch}" not one of ${default_archs}')
			}
		}
	}
	return archs
}

// build_directory returns the compile build directory.
pub fn (opt CompileOptions) build_directory() !string {
	dir := os.join_path(opt.work_dir, 'build')
	return dir
}

pub enum CompileType {
	v_to_c
	c_to_o
	o_to_so
}

pub struct CompileError {
	Error
pub:
	kind CompileType
	err  string
}

fn (err CompileError) msg() string {
	enum_to_text := match err.kind {
		.v_to_c {
			'.v to .c'
		}
		.c_to_o {
			'.c to .o'
		}
		.o_to_so {
			'.o to .so'
		}
	}
	return 'failed to compile ${enum_to_text}:\n${err.err}'
}

// compile_v_to_c compiles V sources to their Android compatible C counterpart.
// compile_v_to_c will also compile any supported C dependencies a vlib module might have.
// See also: compile_v_imports_c_dependencies
pub fn compile_v_to_c(opt CompileOptions) !VMetaInfo {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		return error('${err_sig}: failed making directory "${opt.work_dir}". ${err}')
	}

	if opt.verbosity > 0 {
		println('Compiling V to C')
		if opt.v_flags.len > 0 {
			println('V flags: `${opt.v_flags}`')
		}
	}

	v_compile_opt := VCompileOptions{
		verbosity: opt.verbosity
		cache:     opt.cache
		flags:     opt.v_flags
		work_dir:  os.join_path(opt.work_dir, 'v')
		input:     opt.input
	}

	v_meta_dump := v_dump_meta(v_compile_opt)!
	imported_modules := v_meta_dump.imports

	if imported_modules.len == 0 {
		return error('${err_sig}: empty module dump.')
	}

	v_output_file := os.join_path(opt.work_dir, 'v_android.c')

	// Boehm-Demers-Weiser Garbage Collector (bdwgc / libgc)
	uses_gc := opt.uses_gc()
	if opt.verbosity > 1 {
		println('Garbage collection is ${uses_gc}')
	}

	vexe := vxt.vexe()
	// Compile to Android compatible C file
	mut v_cmd := [
		vexe,
		'-os android',
	]
	if !uses_gc {
		v_cmd << '-gc none'
	}
	if 'sokol.sapp' in imported_modules {
		v_cmd << '-apk'
	} else {
		v_cmd << '-d no_sokol_app'
	}
	if !opt.cache {
		v_cmd << '-nocache'
	}
	v_cmd << opt.v_flags
	v_cmd << [
		'-o "${v_output_file}"',
	]
	v_cmd << opt.input

	util.verbosity_print_cmd(v_cmd, opt.verbosity)
	v_dump_res := util.run_or_error(v_cmd)!
	if opt.verbosity > 2 {
		println(v_dump_res)
	}
	return v_meta_dump
}

pub fn compile(opt CompileOptions) ! {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		return error('${err_sig}: failed making directory "${opt.work_dir}". ${err}')
	}
	build_dir := opt.build_directory()!

	v_meta_dump := compile_v_to_c(opt) or {
		return IError(CompileError{
			kind: .v_to_c
			err:  err.msg()
		})
	}
	v_cflags := v_meta_dump.c_flags
	imported_modules := v_meta_dump.imports

	v_output_file := os.join_path(opt.work_dir, 'v_android.c')
	v_thirdparty_dir := os.join_path(vxt.home(), 'thirdparty')

	uses_gc := opt.uses_gc()

	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	if opt.cache && os.exists(build_dir) && os.exists(v_output_file) {
		mut bytes := os.read_bytes(v_output_file) or {
			return error('${err_sig}: failed reading "${v_output_file}".\n${err}')
		}
		bytes << '${opt.str()}-${opt.cache_key}'.bytes()
		hash = md5.sum(bytes).hex()

		if os.exists(hash_file) {
			prev_hash := os.read_file(hash_file) or { '' }
			if hash == prev_hash {
				if opt.verbosity > 1 {
					println('Skipping compile. Hashes match ${hash}')
				}
				return
			}
		}
	}

	if hash != '' && os.exists(v_output_file) {
		if opt.verbosity > 2 {
			println('Writing new hash ${hash}')
		}
		os.rm(hash_file) or {}
		mut hash_fh := os.open_file(hash_file, 'w+', 0o700) or {
			return error('${err_sig}: failed opening "${hash_file}". ${err}')
		}
		hash_fh.write(hash.bytes()) or {
			return error('${err_sig}: failed writing to "${hash_file}".\n${err}')
		}
		hash_fh.close()
	}

	// Remove any previous builds
	if os.is_dir(build_dir) {
		os.rmdir_all(build_dir) or {
			return error('${err_sig}: failed removing "${build_dir}": ${err}')
		}
	}
	os.mkdir(build_dir) or {
		return error('${err_sig}: failed making directory "${build_dir}".\n${err}')
	}

	archs := opt.archs()!

	if opt.verbosity > 0 {
		println('Compiling V import C dependencies (.c to .o for ${archs})' +
			if opt.parallel { ' in parallel' } else { '' })
	}

	vicd := compile_v_c_dependencies(opt, v_meta_dump) or {
		return IError(CompileError{
			kind: .c_to_o
			err:  err.msg()
		})
	}
	mut o_files := vicd.o_files.clone()
	mut a_files := vicd.a_files.clone()

	// For all compilers
	mut cflags := opt.c_flags.clone()
	mut includes := []string{}
	mut defines := []string{}
	mut ldpaths := []string{}
	mut ldflags := []string{}

	// Grab any external C flags
	for line in v_cflags {
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
		if line.starts_with('-L') {
			ldpaths << line
		}
		if line.starts_with('-l') {
			if line.contains('-lgc') {
				// compiled in
				continue
			}
			if line.contains('-lpthread') {
				// pthread is built into bionic
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

	cflags << ['-Wall', '-Wextra']

	cflags << ['-Wno-unused-parameter'] // sokol_app.h

	// TODO V compile warnings - here to make the compiler(s) shut up :/
	cflags << ['-Wno-unused-variable', '-Wno-unused-result', '-Wno-unused-function',
		'-Wno-unused-label']
	cflags << ['-Wno-missing-braces', '-Werror=implicit-function-declaration']
	cflags << ['-Wno-enum-conversion', '-Wno-unused-value', '-Wno-pointer-sign',
		'-Wno-incompatible-pointer-types']

	defines << '-DAPPNAME="${opt.lib_name}"'
	defines << ['-DANDROID', '-D__ANDROID__', '-DANDROIDVERSION=${opt.api_level}']

	// Include NDK headers
	mut android_includes := []string{}
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('${err_sig}: getting NDK sysroot path.\n${err}')
	}
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include') + '"'
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include', 'android') + '"'

	is_debug_build := opt.is_debug_build()

	// Sokol sapp
	if 'sokol.sapp' in imported_modules {
		if opt.verbosity > 1 {
			println('Including sokol_sapp support via sokol.sapp module')
		}
		if is_debug_build {
			if opt.verbosity > 1 {
				println('Define SOKOL_DEBUG')
			}
			defines << '-DSOKOL_DEBUG'
		}

		if opt.verbosity > 1 {
			println('Using GLES ${opt.gles_version}')
		}

		ldflags << '-lEGL'
		if opt.gles_version == 3 {
			defines << ['-DSOKOL_GLES3']
			ldflags << '-lGLESv3'
		} else {
			defines << ['-DSOKOL_GLES2']
			ldflags << '-lGLESv2'
		}

		ldflags << ['-uANativeActivity_onCreate', '-usokol_main']
	}

	if uses_gc {
		includes << '-I"' + os.join_path(v_thirdparty_dir, 'libgc', 'include') + '"'
	}

	// misc
	ldflags << ['-llog', '-landroid', '-lm']
	ldflags << ['-shared'] // <- Android loads native code via a library in NativeActivity

	mut cflags_arm64 := ['-m64']
	mut cflags_arm32 := ['-mfloat-abi=softfp', '-m32']
	mut cflags_x86 := ['-march=i686', '-mssse3', '-mfpmath=sse', '-m32']
	mut cflags_x86_64 := ['-march=x86-64', '-msse4.2', '-mpopcnt', '-m64']

	mut arch_cc := map[string]string{}
	mut arch_libs := map[string]string{}
	for arch in archs {
		compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			return error('${err_sig}: failed getting NDK compiler.\n${err}')
		}
		arch_cc[arch] = compiler

		arch_lib := ndk.libs_path(opt.ndk_version, arch, opt.api_level) or {
			return error('${err_sig}: failed getting NDK libs path.\n${err}')
		}
		arch_libs[arch] = arch_lib
	}

	mut arch_cflags := map[string][]string{}
	arch_cflags['arm64-v8a'] = cflags_arm64
	arch_cflags['armeabi-v7a'] = cflags_arm32
	arch_cflags['x86'] = cflags_x86
	arch_cflags['x86_64'] = cflags_x86_64

	if opt.verbosity > 0 {
		println('Compiling C output for ${archs}' + if opt.parallel { ' in parallel' } else { '' })
	}

	mut jobs := []job_util.ShellJob{}

	for arch in archs {
		arch_cflags[arch] << [
			'-target ' + ndk.compiler_triplet(arch) + opt.min_sdk_version.str(),
		]
		if arch == 'armeabi-v7a' {
			arch_cflags[arch] << ['-march=armv7-a']
		}
	}

	// Cross compile v.c to v.o lib files
	for arch in archs {
		arch_o_dir := os.join_path(build_dir, 'o', arch)
		if !os.is_dir(arch_o_dir) {
			os.mkdir_all(arch_o_dir) or {
				return error('${err_sig}: failed making directory "${arch_o_dir}". ${err}')
			}
		}

		arch_o_file := os.join_path(arch_o_dir, '${opt.lib_name}.o')
		// Compile .o
		build_cmd := [
			arch_cc[arch],
			cflags.join(' '),
			android_includes.join(' '),
			includes.join(' '),
			defines.join(' '),
			arch_cflags[arch].join(' '),
			'-c "${v_output_file}"',
			'-o "${arch_o_file}"',
		]

		o_files[arch] << arch_o_file

		jobs << job_util.ShellJob{
			cmd: build_cmd
		}
	}

	job_util.run_jobs(jobs, opt.parallel, opt.verbosity) or {
		return IError(CompileError{
			kind: .c_to_o
			err:  err.msg()
		})
	}
	jobs.clear()

	if opt.no_so_build && opt.verbosity > 1 {
		println('Skipping .so build since .no_so_build == true')
	}

	// Cross compile .o files to .so lib file
	if !opt.no_so_build {
		for arch in archs {
			arch_lib_dir := os.join_path(build_dir, 'lib', arch)
			os.mkdir_all(arch_lib_dir) or {
				return error('${err_sig}: failed making directory "${arch_lib_dir}".\n${err}')
			}

			arch_o_files := o_files[arch].map('"${it}"')
			arch_a_files := a_files[arch].map('"${it}"')

			build_cmd := [
				arch_cc[arch],
				arch_o_files.join(' '),
				'-o "${arch_lib_dir}/lib${opt.lib_name}.so"',
				arch_a_files.join(' '),
				'-L"' + arch_libs[arch] + '"',
				ldpaths.join(' '),
				ldflags.join(' '),
			]

			jobs << job_util.ShellJob{
				cmd: build_cmd
			}
		}

		job_util.run_jobs(jobs, opt.parallel, opt.verbosity) or {
			return IError(CompileError{
				kind: .o_to_so
				err:  err.msg()
			})
		}

		if 'armeabi-v7a' in archs {
			// TODO fix DT_NAME crash instead of including a copy of the armeabi-v7a lib
			armeabi_lib_dir := os.join_path(build_dir, 'lib', 'armeabi')
			os.mkdir_all(armeabi_lib_dir) or {
				return error('${err_sig}: failed making directory "${armeabi_lib_dir}".\n${err}')
			}

			armeabi_lib_src := os.join_path(build_dir, 'lib', 'armeabi-v7a', 'lib${opt.lib_name}.so')
			armeabi_lib_dst := os.join_path(armeabi_lib_dir, 'lib${opt.lib_name}.so')
			os.cp(armeabi_lib_src, armeabi_lib_dst) or {
				return error('${err_sig}: failed copying "${armeabi_lib_src}" to "${armeabi_lib_dst}".\n${err}')
			}
		}
	}
}

pub struct VCompileOptions {
pub:
	verbosity int // level of verbosity
	cache     bool
	work_dir  string // temporary work directory
	input     string
	flags     []string // flags to pass to the v compiler
}

// uses_gc returns true if a `-gc` flag is found among the passed v flags.
pub fn (opt VCompileOptions) uses_gc() bool {
	mut uses_gc := true // V default
	for v_flag in opt.flags {
		if v_flag.starts_with('-gc') {
			if v_flag.ends_with('none') {
				uses_gc = false
			}
			break
		}
	}
	return uses_gc
}

pub struct VMetaInfo {
pub:
	imports []string
	c_flags []string
}

// v_dump_meta returns the information dumped by
// -dump-modules and -dump-c-flags.
pub fn v_dump_meta(opt VCompileOptions) !VMetaInfo {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		return error('${err_sig}: failed making directory "${opt.work_dir}". ${err}')
	}

	vexe := vxt.vexe()

	uses_gc := opt.uses_gc()

	// Dump modules and C flags to files
	v_cflags_file := os.join_path(opt.work_dir, 'v.cflags')
	os.rm(v_cflags_file) or {}
	v_dump_modules_file := os.join_path(opt.work_dir, 'v.modules')
	os.rm(v_dump_modules_file) or {}

	mut v_cmd := [
		vexe,
		'-os android',
	]
	if !uses_gc {
		v_cmd << '-gc none'
	}
	if !opt.cache {
		v_cmd << '-nocache'
	}
	v_cmd << opt.flags
	v_cmd << [
		'-cc clang',
		'-dump-modules "${v_dump_modules_file}"',
		'-dump-c-flags "${v_cflags_file}"',
	]
	v_cmd << opt.input

	// NOTE this command fails with a C compile error but the output we need is still
	// present... Yes - not exactly pretty.
	// VCROSS_COMPILER_NAME is needed (on at least Windows) - just get whatever compiler is available
	os.setenv('VCROSS_COMPILER_NAME', ndk.compiler_min_api(.c, ndk.default_version(),
		'arm64-v8a') or { '' }, true)

	util.verbosity_print_cmd(v_cmd, opt.verbosity)
	v_dump_res := util.run(v_cmd)
	if opt.verbosity > 3 {
		println(v_dump_res)
	}

	// Read in the dumped cflags
	cflags := os.read_file(v_cflags_file) or {
		flat_cmd := v_cmd.join(' ')
		return error('${err_sig}: failed reading C flags to "${v_cflags_file}". ${err}\nCompile output of `${flat_cmd}`:\n${v_dump_res}')
	}

	// Parse imported modules from dump
	mut imported_modules := os.read_file(v_dump_modules_file) or {
		flat_cmd := v_cmd.join(' ')
		return error('${err_sig}: failed reading module dump file "${v_dump_modules_file}". ${err}\nCompile output of `${flat_cmd}`:\n${v_dump_res}')
	}.split('\n').filter(it != '')
	imported_modules.sort()
	if opt.verbosity > 2 {
		println('Imported modules: ${imported_modules}')
	}

	return VMetaInfo{
		imports: imported_modules
		c_flags: cflags.split('\n')
	}
}

struct VImportCDeps {
pub:
	o_files map[string][]string
	a_files map[string][]string
}

// compile_v_c_dependencies compiles the C dependencies in the V code.
pub fn compile_v_c_dependencies(opt CompileOptions, v_meta_info VMetaInfo) !VImportCDeps {
	err_sig := @MOD + '.' + @FN

	imported_modules := v_meta_info.imports

	// The following detects `#flag /path/to/file.o` entries in V source code that matches a module.
	//
	// Find all "*.o" entries in the C flags dump (obtained via `-dump-c-flags`).
	// Match the (file)name of these .o files with what modules are actually imported
	// (imports are obtained via `-dump-modules`)
	// If they are module .o files - look for the corresponding `.o.description.txt` that V produces
	// as `~/.vmodules/cache/<hex>/<hash>.o.description.txt`.
	// If the file exists read in it's contents to obtain the exact flags passed to the C compiler.
	mut v_module_o_files := map[string][][]string{}
	for line in v_meta_info.c_flags {
		line_trimmed := line.trim('\'"')
		if line_trimmed.contains('.module.') && line_trimmed.ends_with('.o') {
			module_name := line_trimmed.all_after('.module.').all_before_last('.o')
			if module_name in imported_modules {
				description_file := line_trimmed.all_before_last('.o') + '.description.txt'
				if os.is_file(description_file) {
					if description_contents := os.read_file(description_file) {
						desc := description_contents.split(' ').map(it.trim_space()).filter(it != '')
						index_of_at := desc.index('@')
						index_of_o := desc.index('-o')
						index_of_c := desc.index('-c')
						if desc.len <= 3 || index_of_at <= 0 || index_of_o <= 0 || index_of_c <= 0 {
							if opt.verbosity > 2 {
								println('Description file "${description_file}" does not seem to have valid contents for object file generation')
								println('Description file contents:\n---\n"${description_contents}"\n---')
							}
							continue
						}
						v_module_o_files[module_name] << (desc[index_of_at + 2..])
					}
				}
			}
		}
	}

	mut o_files := map[string][]string{}
	mut a_files := map[string][]string{}

	uses_gc := opt.uses_gc()
	build_dir := opt.build_directory()!
	is_debug_build := opt.is_debug_build()

	// For all compilers
	mut cflags_common := opt.c_flags.clone()
	if opt.is_prod {
		cflags_common << ['-Os']
	} else {
		cflags_common << ['-O0']
	}
	cflags_common << ['-fPIC']
	cflags_common << ['-Wall', '-Wextra']

	mut android_includes := []string{}
	// Include NDK headers
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('${err_sig}: getting NDK sysroot path.\n${err}')
	}
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include') + '"'
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include', 'android') + '"'

	v_thirdparty_dir := os.join_path(vxt.home(), 'thirdparty')

	archs := opt.archs()!

	mut jobs := []job_util.ShellJob{}
	for arch in archs {
		mut cflags := cflags_common.clone()
		arch_o_dir := os.join_path(build_dir, 'o', arch)
		if !os.is_dir(arch_o_dir) {
			os.mkdir_all(arch_o_dir) or {
				return error('${err_sig}: failed making directory "${arch_o_dir}".\n${err}')
			}
		}

		compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			return error('${err_sig}: failed getting NDK compiler.\n${err}')
		}

		// Support builtin libgc which is enabled by default in V or via explicit passed `-gc` flag.
		if uses_gc {
			if opt.verbosity > 1 {
				println('Compiling libgc (${arch}) via -gc flag')
			}

			mut defines := []string{}
			if is_debug_build {
				defines << '-DGC_ASSERTIONS'
				defines << '-DGC_ANDROID_LOG'
			}
			if !opt.has_v_d_flag('no_gc_threads') {
				defines << '-DGC_THREADS=1'
			}
			defines << '-DGC_BUILTIN_ATOMIC=1'
			defines << '-D_REENTRANT'
			// NOTE it's currently a little unclear why this is needed.
			// V UI can crash and with when the gc is built into the exe and started *without* GC_INIT() the error would occur:
			defines << '-DUSE_MMAP' // Will otherwise crash with a message with a path to the lib in GC_unix_mmap_get_mem+528

			o_file := os.join_path(arch_o_dir, 'gc.o')
			build_cmd := [
				compiler,
				cflags.join(' '),
				'-I"' + os.join_path(v_thirdparty_dir, 'libgc', 'include') + '"',
				defines.join(' '),
				'-c "' + os.join_path(v_thirdparty_dir, 'libgc', 'gc.c') + '"',
				'-o "${o_file}"',
			]
			util.verbosity_print_cmd(build_cmd, opt.verbosity)
			o_res := util.run_or_error(build_cmd)!
			if opt.verbosity > 2 {
				eprintln(o_res)
			}

			o_files[arch] << o_file

			jobs << job_util.ShellJob{
				cmd: build_cmd
			}
		}

		// Compile all detected `#flag /path/to/xxx.o` V source code entires that matches an imported module.
		// NOTE: currently there's no way in V source to pass flags for specific architectures so these flags need
		// to be added specially here. It should probably be supported as compile options from commandline...
		for module_name, mod_compile_lines in v_module_o_files {
			if opt.verbosity > 1 {
				println('Compiling .o files from module ${module_name} for arch ${arch}...')
			}

			if module_name == 'stbi' && arch == 'armeabi-v7a' {
				if opt.verbosity > 1 {
					println('Applying fix flag to stb_image_resize2.h (for ${arch}, via stbi module)')
				}
				cflags << '-mfpu=neon-vfpv4'
				$if gcc {
					cflags << '-mfp16-format=ieee'
				}
			}

			for compile_line in mod_compile_lines {
				index_o_arg := compile_line.index('-o') + 1
				mut o_file := ''
				if path := compile_line[index_o_arg] {
					file_name := os.file_name(path).trim_space().trim('\'"')
					o_file = os.join_path(arch_o_dir, '${file_name}')
				}
				mut build_cmd := [
					compiler,
					cflags.join(' '),
				]
				for i, entry in compile_line {
					if i == index_o_arg {
						build_cmd << '"${o_file}"'
						continue
					}
					build_cmd << entry
				}

				if opt.verbosity > 1 {
					println('Compiling "${o_file}" from module ${module_name} for arch ${arch}...')
				}

				util.verbosity_print_cmd(build_cmd, opt.verbosity)
				o_res := util.run_or_error(build_cmd)!
				if opt.verbosity > 2 {
					eprintln(o_res)
				}

				o_files[arch] << o_file

				jobs << job_util.ShellJob{
					cmd: build_cmd
				}
			}
		}
	}

	job_util.run_jobs(jobs, opt.parallel, opt.verbosity)!

	return VImportCDeps{
		o_files: o_files
		a_files: a_files
	}
}

// compile_v_imports_c_dependencies compiles the C dependencies of V's module imports.
// It is replaced by compile_v_c_dependencies that has better support for `#flag /path/to/xxx.o` V source entries.
@[deprecated: 'use compile_v_c_dependencies() instead']
@[deprecated_after: '2025-01-01']
pub fn compile_v_imports_c_dependencies(opt CompileOptions, imported_modules []string) !VImportCDeps {
	err_sig := @MOD + '.' + @FN

	mut o_files := map[string][]string{}
	mut a_files := map[string][]string{}

	uses_gc := opt.uses_gc()
	build_dir := opt.build_directory()!
	is_debug_build := opt.is_debug_build()

	// For all compilers
	mut cflags_common := opt.c_flags.clone()
	if opt.is_prod {
		cflags_common << ['-Os']
	} else {
		cflags_common << ['-O0']
	}
	cflags_common << ['-fPIC']
	cflags_common << ['-Wall', '-Wextra']

	mut android_includes := []string{}
	// Include NDK headers
	ndk_sysroot := ndk.sysroot_path(opt.ndk_version) or {
		return error('${err_sig}: getting NDK sysroot path.\n${err}')
	}
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include') + '"'
	android_includes << '-I"' + os.join_path(ndk_sysroot, 'usr', 'include', 'android') + '"'

	v_thirdparty_dir := os.join_path(vxt.home(), 'thirdparty')

	archs := opt.archs()!

	mut jobs := []job_util.ShellJob{}
	for arch in archs {
		mut cflags := cflags_common.clone()
		arch_o_dir := os.join_path(build_dir, 'o', arch)
		if !os.is_dir(arch_o_dir) {
			os.mkdir_all(arch_o_dir) or {
				return error('${err_sig}: failed making directory "${arch_o_dir}".\n${err}')
			}
		}

		compiler := ndk.compiler(.c, opt.ndk_version, arch, opt.api_level) or {
			return error('${err_sig}: failed getting NDK compiler.\n${err}')
		}

		if uses_gc {
			if opt.verbosity > 1 {
				println('Compiling libgc (${arch}) via -gc flag')
			}

			mut defines := []string{}
			if is_debug_build {
				defines << '-DGC_ASSERTIONS'
				defines << '-DGC_ANDROID_LOG'
			}
			defines << '-DGC_THREADS=1'
			defines << '-DGC_BUILTIN_ATOMIC=1'
			defines << '-D_REENTRANT'
			// NOTE it's currently a little unclear why this is needed.
			// V UI can crash and with when the gc is built into the exe and started *without* GC_INIT() the error would occur:
			defines << '-DUSE_MMAP' // Will otherwise crash with a message with a path to the lib in GC_unix_mmap_get_mem+528

			o_file := os.join_path(arch_o_dir, 'gc.o')
			build_cmd := [
				compiler,
				cflags.join(' '),
				'-I"' + os.join_path(v_thirdparty_dir, 'libgc', 'include') + '"',
				defines.join(' '),
				'-c "' + os.join_path(v_thirdparty_dir, 'libgc', 'gc.c') + '"',
				'-o "${o_file}"',
			]
			util.verbosity_print_cmd(build_cmd, opt.verbosity)
			o_res := util.run_or_error(build_cmd)!
			if opt.verbosity > 2 {
				eprintln(o_res)
			}

			o_files[arch] << o_file

			jobs << job_util.ShellJob{
				cmd: build_cmd
			}
		}

		// stb_image via `stbi` module
		if 'stbi' in imported_modules {
			if opt.verbosity > 1 {
				println('Compiling stb_image (${arch}) via stbi module')
			}
			if arch == 'armeabi-v7a' {
				cflags << '-mfpu=neon-vfpv4'
				$if gcc {
					cflags << '-mfp16-format=ieee'
				}
			}

			o_file := os.join_path(arch_o_dir, 'stbi.o')
			build_cmd := [
				compiler,
				cflags.join(' '),
				'-Wno-sign-compare',
				'-I"' + os.join_path(v_thirdparty_dir, 'stb_image') + '"',
				'-c "' + os.join_path(v_thirdparty_dir, 'stb_image', 'stbi.c') + '"',
				'-o "${o_file}"',
			]

			o_files[arch] << o_file

			jobs << job_util.ShellJob{
				cmd: build_cmd
			}
		}

		// cJson via `json` module
		if 'json' in imported_modules {
			if opt.verbosity > 1 {
				println('Compiling cJSON (${arch}) via json module')
			}
			o_file := os.join_path(arch_o_dir, 'cJSON.o')
			build_cmd := [
				compiler,
				cflags.join(' '),
				'-I"' + os.join_path(v_thirdparty_dir, 'cJSON') + '"',
				'-c "' + os.join_path(v_thirdparty_dir, 'cJSON', 'cJSON.c') + '"',
				'-o "${o_file}"',
			]

			o_files[arch] << o_file

			jobs << job_util.ShellJob{
				cmd: build_cmd
			}
		}
	}

	job_util.run_jobs(jobs, opt.parallel, opt.verbosity)!

	return VImportCDeps{
		o_files: o_files
		a_files: a_files
	}
}
