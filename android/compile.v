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
pub mut:
	v_arch string // architecture V compiles the C for; compile sets it per ABI
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

// v_target_arch names the architecture V compiles for, given a vab ABI name.
fn v_target_arch(abi string) string {
	return match abi {
		'arm64-v8a' { 'arm64' }
		'armeabi-v7a' { 'arm32' }
		'x86' { 'x86' }
		'x86_64' { 'amd64' }
		else { abi }
	}
}

// v_compiler_flags returns the flags for the V compiler, with the target
// architecture added once compile has set one.
fn (opt CompileOptions) v_compiler_flags() []string {
	mut flags := opt.v_flags.clone()
	if opt.v_arch.len > 0 {
		flags << '-arch ${opt.v_arch}'
	}
	return flags
}

// v_c_file is the C file compile_v_to_c writes. Each architecture gets its own,
// because comptime-selected code such as closure trampolines differs per target.
fn (opt CompileOptions) v_c_file() string {
	if opt.v_arch.len == 0 {
		return os.join_path(opt.work_dir, 'v_android.c')
	}
	return os.join_path(opt.work_dir, 'v_android_${opt.v_arch}.c')
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
		flags:     opt.v_compiler_flags()
		work_dir:  os.join_path(opt.work_dir, 'v')
		input:     opt.input
	}

	v_meta_dump := v_dump_meta(v_compile_opt)!
	imported_modules := v_meta_dump.imports

	if imported_modules.len == 0 {
		return error('${err_sig}: empty module dump.')
	}

	v_output_file := opt.v_c_file()

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
	v_cmd << opt.v_compiler_flags()
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

	archs := opt.archs()!

	// V runs once per ABI. Comptime-selected code, the closure trampolines among
	// it, follows the target architecture, so one C file cannot serve them all.
	// The first architecture's dump supplies the flags shared by every ABI.
	mut v_output_files := map[string]string{}
	mut v_meta_dump := VMetaInfo{}
	for i, arch in archs {
		mut arch_opt := opt
		arch_opt.v_arch = v_target_arch(arch)
		arch_meta := compile_v_to_c(arch_opt) or {
			return IError(CompileError{
				kind: .v_to_c
				err:  err.msg()
			})
		}
		if i == 0 {
			v_meta_dump = arch_meta
		}
		v_output_files[arch] = arch_opt.v_c_file()
	}
	v_cflags := v_meta_dump.c_flags
	imported_modules := v_meta_dump.imports

	v_thirdparty_dir := os.join_path(vxt.home(), 'thirdparty')

	uses_gc := opt.uses_gc()

	// Poor man's cache check
	mut hash := ''
	hash_file := os.join_path(opt.work_dir, 'v_android.hash')
	mut all_c_exist := true
	for arch in archs {
		all_c_exist = all_c_exist && os.exists(v_output_files[arch])
	}
	if opt.cache && os.exists(build_dir) && all_c_exist {
		mut content := ''
		for arch in archs {
			content += os.read_file(v_output_files[arch]) or {
				return error('${err_sig}: failed reading "${v_output_files[arch]}".\n${err}')
			}
		}
		hash = md5.sum((content + '${opt.str()}-${opt.cache_key}').bytes()).hex()

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

	if hash != '' && all_c_exist {
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
	cflags << ['-Wno-unused-variable', '-Wno-unused-result', '-Wno-unused-function', '-Wno-unused-label']
	cflags << '-Wno-missing-braces'
	// The C output of recent V versions calls C functions that V compiles in
	// separate translation units (e.g. `android_print` from
	// `vlib/builtin/android_print.c`) without emitting their declarations, the
	// same way V's own C build does (it builds with `-w`). An implicitly
	// declared function is caught at link time instead.
	cflags << '-Wno-implicit-function-declaration'
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
			'-c "${v_output_files[arch]}"',
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
	// c_sources contains the C source files that V itself compiles for the
	// program: builtin helpers and thirdparty code pulled in by the imported
	// modules. vab cross-compiles these for each target architecture.
	c_sources []string
}

// v_dump_meta returns information about the program that vab needs for the
// Android build: the imported modules, the C flags needed to build its C
// output and the C sources that V itself compiles for the program.
//
// The information is obtained by letting V generate a C project for the
// program (`-generate-c-project`): V writes the program's C output, a
// `build.sh` with the full C build command - from which the C flags and C
// sources are extracted - and, via `-dump-files`, the list of V source files
// used - from which the imported modules are derived.
//
// NOTE: `-dump-modules` and `-dump-c-flags` are no longer used, as they are
// either not supported or only written on a *successful* C build by V 0.5.x.
// The C project approach above works with C generation only: V skips its own
// C build step entirely for it.
pub fn v_dump_meta(opt VCompileOptions) !VMetaInfo {
	err_sig := @MOD + '.' + @FN
	os.mkdir_all(opt.work_dir) or {
		return error('${err_sig}: failed making directory "${opt.work_dir}". ${err}')
	}

	vexe := vxt.vexe()

	uses_gc := opt.uses_gc()

	c_project_dir := os.join_path(opt.work_dir, 'cproject')
	if os.is_dir(c_project_dir) {
		os.rmdir_all(c_project_dir) or {
			return error('${err_sig}: failed removing directory "${c_project_dir}". ${err}')
		}
	}
	os.mkdir_all(c_project_dir) or {
		return error('${err_sig}: failed making directory "${c_project_dir}". ${err}')
	}

	// The dumped list of V source files used by the program.
	v_files_dump := os.join_path(opt.work_dir, 'v.files')
	os.rm(v_files_dump) or {}

	// The C output generated here is discarded: the C file used for the
	// Android build is generated by `compile_v_to_c` with the sokol flags
	// applied.
	discard_c_file := os.join_path(opt.work_dir, 'v_discard.c')
	os.rm(discard_c_file) or {}

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
		'-generate-c-project "${c_project_dir}"',
		'-dump-files "${v_files_dump}"',
		'-o "${discard_c_file}"',
	]
	v_cmd << opt.input

	util.verbosity_print_cmd(v_cmd, opt.verbosity)
	util.run_or_error(v_cmd) or {
		return error('${err_sig}: failed generating C project for "${opt.input}". ${err}')
	}

	// Extract C flags and C sources from the build command in the generated
	// build script.
	build_sh := os.read_file(os.join_path(c_project_dir, 'build.sh')) or {
		return error('${err_sig}: failed reading the C project build script in "${c_project_dir}". ${err}')
	}
	build_args := parse_single_quoted_args(build_sh)
	mut c_flags := []string{}
	mut c_sources := []string{}
	mut i := 0
	for i < build_args.len {
		arg := build_args[i]
		if arg == '-o' {
			// Skip the output path of the built executable.
			i += 2
			continue
		}
		if (arg == '-I' || arg == '-L') && i + 1 < build_args.len {
			c_flags << '${arg}"${build_args[i + 1]}"'
			i += 2
			continue
		}
		if arg.starts_with('-I') || arg.starts_with('-L') || arg.starts_with('-D')
			|| (arg.starts_with('-l') && arg.len > 2) {
			c_flags << arg
			i++
			continue
		}
		if arg.starts_with('-') {
			i++
			continue
		}
		// Skip the C output of the program itself: V writes it into the
		// generated C project directory. The real C sources to cross-compile
		// are the ones V lists from `vlib` and `thirdparty`.
		if os.file_ext(arg) == '.c' && !arg.starts_with(c_project_dir) {
			c_sources << arg
		}
		i++
	}

	// Derive the imported modules from the dumped V source files. For files
	// in V's own `vlib` the module is the file's path relative to `vlib`
	// (e.g. `vlib/sokol/sapp` becomes `sokol.sapp`), which is also the form
	// V's old `-dump-modules` wrote. For files outside of `vlib` the module
	// is the name in the file's own `module` declaration.
	vlib_dir := os.join_path(os.dir(os.real_path(vexe)), 'vlib')
	vlib_prefix := vlib_dir + os.path_separator
	mut imported_modules := []string{}
	if os.exists(v_files_dump) {
		v_files := (os.read_file(v_files_dump) or { '' }).split('\n').filter(it.ends_with('.v'))
		for v_file in v_files {
			mut module_name := ''
			if v_file.starts_with(vlib_prefix) {
				module_rel := v_file.all_after(vlib_prefix)
				if module_rel.contains(os.path_separator) {
					module_name = module_rel.all_before_last(os.path_separator).replace(os.path_separator,
						'.')
				}
			} else {
				module_name = module_declaration_of(v_file)
			}
			if module_name == '' || module_name in imported_modules {
				continue
			}
			imported_modules << module_name
		}
	}
	imported_modules.sort()
	if opt.verbosity > 2 {
		println('Imported modules: ${imported_modules}')
	}

	return VMetaInfo{
		imports:   imported_modules
		c_flags:   c_flags
		c_sources: c_sources
	}
}

// parse_single_quoted_args splits the arguments of a command where every
// argument is enclosed in single quotes, as V's `-generate-c-project` writes
// them in the generated `build.sh`.
fn parse_single_quoted_args(script string) []string {
	mut args := []string{}
	mut i := 0
	for i < script.len {
		if script[i] != `'` {
			i++
			continue
		}
		start := i + 1
		end := script.index_after("'", start) or { break }
		args << script[start..end]
		i = end + 1
	}
	return args
}

// module_declaration_of returns the name of the module declared in the V
// source file at `path`, or '' if the file declares no module.
fn module_declaration_of(path string) string {
	if !os.exists(path) {
		return ''
	}
	head := (os.read_bytes(path) or { return '' }).bytestr()
	for line in head.split('\n') {
		line_trimmed := line.trim_space()
		if line_trimmed.starts_with('module ') {
			return line_trimmed['module '.len..].trim_space()
		}
	}
	return ''
}

struct VImportCDeps {
pub:
	o_files map[string][]string
	a_files map[string][]string
}

// compile_v_c_dependencies compiles the C dependencies in the V code.
pub fn compile_v_c_dependencies(opt CompileOptions, v_meta_info VMetaInfo) !VImportCDeps {
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

		// Compile the C sources that V itself compiles for the program: builtin
		// helpers (e.g. android printing) and thirdparty code pulled in by the
		// imported modules (e.g. stb_image). V reports these via the generated
		// C project, together with the include paths they need.
		for c_source in v_meta_info.c_sources {
			if opt.verbosity > 1 {
				println('Compiling C source ${c_source} for arch ${arch}...')
			}

			file_name := os.file_name(c_source)
			file_base := file_name.all_before_last('.')
			o_file := os.join_path(arch_o_dir, '${file_base}.o')

			mut source_cflags := cflags.clone()
			// Include paths and defines needed by the C source, as reported by V.
			for c_flag in v_meta_info.c_flags {
				if c_flag.starts_with('-I') || c_flag.starts_with('-D') {
					source_cflags << c_flag
				}
			}

			if file_name == 'stbi.c' && arch == 'armeabi-v7a' {
				if opt.verbosity > 1 {
					println('Applying fix flag to stb_image_resize2.h (for ${arch}, via stbi module)')
				}
				source_cflags << '-mfpu=neon-vfpv4'
				$if gcc {
					source_cflags << '-mfp16-format=ieee'
				}
			}

			if file_name == 'stbi.c' {
				source_cflags << '-Wno-sign-compare'
			}

			build_cmd := [
				compiler,
				source_cflags.join(' '),
				android_includes.join(' '),
				'-c "${c_source}"',
				'-o "${o_file}"',
			]

			if opt.verbosity > 1 {
				println('Compiling "${o_file}" for arch ${arch}...')
			}

			util.verbosity_print_cmd(build_cmd, opt.verbosity)
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
