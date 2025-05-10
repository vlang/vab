// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import stbi
import regex
import semver
import vab.java
import vab.paths
import vab.util as vabutil
import vab.android.env
import vab.android.sdk
import vab.android.util

// PackageFormat holds all supported package formats
pub enum PackageFormat {
	apk
	aab
}

// PackageOptions represents an Android package configuration
pub struct PackageOptions {
pub:
	verbosity       int
	work_dir        string
	is_prod         bool
	api_level       string
	min_sdk_version int = default_min_sdk_version
	gles_version    int
	build_tools     string
	format          PackageFormat = .apk
	app_name        string
	lib_name        string
	package_id      string
	activity_name   string
	icon            string
	icon_mipmaps    bool
	version_code    int
	v_flags         []string
	input           string
	assets_extra    []string
	libs_extra      []string
	output_file     string
	keystore        Keystore
	base_files      string = default_base_files_path
	overrides_path  string // Path to user provided files that will override `base_files`. `java` (and later `kotlin` TODO) subdirs are recognized
	prepare_base_fn fn (PackageOptions) !PackageBase = prepare_package_base // function used to prepare package base files
	// Defaults (allows for runtime redefinition)
	default_package_id    string // Reserved for defining the default package_id at runtime
	default_activity_name string // Reserved for defining the default activity_name at runtime
}

// verbose prints `msg` to STDOUT if `PackageOptions.verbosity` level is >= `verbosity_level`.
pub fn (po &PackageOptions) verbose(verbosity_level int, msg string) {
	if po.verbosity >= verbosity_level {
		println(msg)
	}
}

// package_root returns the path to the "package base files" that `vab`
// (and the Java/SDK packaging tools) uses as a base for what to include in
// the resulting APK or AAB package file archive.
pub fn (po &PackageOptions) package_root() string {
	return os.join_path(po.work_dir, 'package', '${po.format}')
}

fn get_default_base_files_path() string {
	user_default_base_files_path := $d('vab:default_base_files_path', '')
	if user_default_base_files_path != '' {
		return user_default_base_files_path
	}
	// Look next to the executable
	mut path := os.join_path(os.dir(os.real_path(os.executable())), 'platforms', 'android')
	if os.is_dir(path) {
		return path
	}
	// Assume they are in .vmodules/vab/...
	vmodules_path := os.getenv_opt('VMODULES') or { os.join_path(os.home_dir(), '.vmodules') }
	path = os.join_path(vmodules_path, 'vab', 'platforms', 'android')
	if os.is_dir(path) {
		return path
	}
	return ''
}

// package outputs one of the supported Android package formats based on
// `PackageOptions`
pub fn package(opt PackageOptions) ! {
	error_tag := @MOD + '.' + @FN
	opt.verbose(1, 'Preparing package "${opt.package_id}"...')
	// Validate package_id to our best effort
	is_valid_package_id(opt.package_id) or {
		return error('${error_tag}: "${opt.package_id}" is not a valid package id:\n${err}.
Please consult the Android documentation for details:
https://developer.android.com/studio/build/application-id')
	}
	if opt.is_prod {
		ensure_no_developer_team_package_id(opt)!
	}
	// Build APK
	match opt.format {
		.apk {
			package_apk(opt)!
		}
		.aab {
			package_aab(opt)!
		}
	}
}

// package_apk ouputs an Android .apk package file based on the `PackageOptions`.
fn package_apk(opt PackageOptions) ! {
	error_tag := @MOD + '.' + @FN
	pwd := os.getwd()

	build_path := os.join_path(opt.work_dir, 'build')
	artifacts_path := os.join_path(opt.work_dir, 'artifacts')
	libs_extra_path := os.join_path(opt.work_dir, 'libs')
	build_tools_path := os.join_path(sdk.build_tools_root(), opt.build_tools)

	// Remove any previous extra libs
	if os.is_dir(libs_extra_path) {
		os.rmdir_all(libs_extra_path) or {
			return error('${error_tag}: could not remove "${libs_extra_path}":\n${err}')
		}
	}
	for supported_lib_folder in supported_lib_folders {
		supported_lib_folder_path := os.join_path(libs_extra_path, 'lib', supported_lib_folder)
		os.mkdir_all(supported_lib_folder_path) or {
			return error('${error_tag}: error while making directory "${supported_lib_folder_path}":\n${err}')
		}
	}

	// Remove any previous artifacts libs
	os.rmdir_all(artifacts_path) or {}
	os.mkdir_all(artifacts_path) or {
		return error('${error_tag}: error while making directory "${artifacts_path}":\n${err}')
	}

	// Used for various bug workarounds below
	build_tools_semantic_version := semver.from(opt.build_tools) or {
		return error('${error_tag}:' + @LINE +
			' error converting build-tools version "${opt.build_tools}" to semantic version.\nsemver: ${err}')
	}

	// Used for various bug workarounds below
	jdk_semantic_version := semver.from(java.jdk_version()) or {
		return error('${error_tag}:' + @LINE +
			' error converting jdk_version "${java.jdk_version()}" to semantic version.\nsemver: ${err}')
	}

	javac := os.join_path(java.jdk_bin_path(), 'javac')
	aapt := os.join_path(build_tools_path, 'aapt')
	mut dx := os.join_path(build_tools_path, 'dx')
	mut d8 := os.join_path(build_tools_path, 'd8') // Not available prior to build-tools v28.0.1
	$if windows {
		dx += '.bat'
		d8 += '.bat'
	}
	zipalign := os.join_path(build_tools_path, 'zipalign')
	mut apksigner := os.join_path(build_tools_path, 'apksigner')
	$if windows {
		apksigner += '.bat'
	}

	// Prepare and modify package skeleton shipped with vab
	// Copy assets etc.
	package_base := opt.prepare_base_fn(opt)!
	package_path := package_base.package_path
	assets_path := package_base.assets_path

	output_fn := os.file_name(opt.output_file).replace(os.file_ext(opt.output_file), '')
	tmp_product := os.join_path(opt.work_dir, '${output_fn}.apk')
	tmp_unsigned_product := os.join_path(opt.work_dir, '${output_fn}.unsigned.apk')
	tmp_unaligned_product := os.join_path(opt.work_dir, '${output_fn}.unaligned.apk')

	os.rm(tmp_product) or {}
	os.rm(tmp_unsigned_product) or {}
	os.rm(tmp_unaligned_product) or {}

	android_runtime := os.join_path(sdk.platforms_root(), 'android-' + opt.api_level,
		'android.jar')

	src_path := os.join_path(package_path, 'src')
	res_path := os.join_path(package_path, 'res')

	obj_path := os.join_path(package_path, 'obj')
	os.mkdir_all(obj_path) or {
		return error('${error_tag}: error while making directory "${obj_path}":\n${err}')
	}
	bin_path := os.join_path(package_path, 'bin')
	os.mkdir_all(bin_path) or {
		return error('${error_tag}: error while making directory "${bin_path}":\n${err}')
	}

	mut aapt_cmd := [
		aapt,
		'package',
		'-v',
		'-f',
		'-m',
		'-M "' + os.join_path(package_path, 'AndroidManifest.xml') + '"',
		'-S "' + res_path + '"',
		'-J "' + src_path + '"',
		'-A "' + assets_path + '"',
		'-I "' + android_runtime + '"', // TODO use '--target-sdk-version ${ANDROIDTARGET}' ?
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_error(aapt_cmd)!

	os.chdir(package_path) or {
		return error('${error_tag}: error while changing work directory to "${package_path}":\n${err}')
	}

	mut javac_source_version := '1.7'
	mut javac_target_version := '1.7'
	if jdk_semantic_version >= semver.build(20, 0, 0) {
		javac_source_version = '1.8'
		javac_target_version = '1.8'
	}

	// Compile java sources
	opt.verbose(2, 'Compiling java sources ${javac_source_version}/${javac_target_version}')
	java_sources := os.walk_ext(os.join_path(package_path, 'src'), '.java')

	mut javac_cmd := [
		javac,
		'-d obj', // NOTE `+obj_path` can be specified
		'-source ${javac_source_version}',
		'-target ${javac_target_version}',
		'-classpath .',
		'-sourcepath src',
		'-bootclasspath "' + android_runtime + '"',
	]
	javac_cmd << java_sources

	util.verbosity_print_cmd(javac_cmd, opt.verbosity)
	util.run_or_error(javac_cmd)!

	$if windows {
		// TODO Workaround dx and Java > 8 (1.8.0) BUG
		// Error message we are trying to prevent:
		// -Djava.ext.dirs=C:<path>lib is not supported.  Use -classpath instead.
		if jdk_semantic_version > semver.build(1, 8, 0) {
			if os.exists(dx) {
				mut patched_dx := os.join_path(os.dir(dx), os.file_name(dx).all_before_last('.') +
					'_patched.bat')
				if !os.exists(patched_dx) {
					mut dx_contents := os.read_file(dx) or { '' }
					if dx_contents != '' && dx_contents.contains('-Djava.ext.dirs=') {
						dx_contents = dx_contents.replace_once('-Djava.ext.dirs=', '-classpath ')
						os.write_file(patched_dx, dx_contents) or { patched_dx = dx }
					} else {
						patched_dx = dx
					}
					opt.verbose(2, 'Using patched dx (${patched_dx})')
				}
				dx = patched_dx
			}

			if os.exists(d8) {
				mut patched_d8 := os.join_path(os.dir(d8), os.file_name(d8).all_before_last('.') +
					'_patched.bat')
				if !os.exists(patched_d8) {
					mut d8_contents := os.read_file(d8) or { '' }
					if d8_contents != '' && d8_contents.contains('-Djava.ext.dirs=') {
						d8_contents = d8_contents.replace_once('-Djava.ext.dirs=', '-classpath ')
						os.write_file(patched_d8, d8_contents) or { patched_d8 = d8 }
					} else {
						patched_d8 = d8
					}
					opt.verbose(2, 'Using patched d8 (${patched_d8})')
				}
				d8 = patched_d8
			}
		}
		// Workaround END
	}

	// Dex either with `dx` or `d8`
	if build_tools_semantic_version >= semver.build(28, 0, 1) {
		mut class_files := os.walk_ext('obj', '.class')
		class_files = class_files.map(fn (e string) string {
			$if windows {
				return '"${e}"'
			}
			return "'${e}'" // NOTE inclosing with ' is important since the files can contain `$` chars
		})
		mut dex_type := if opt.is_prod { '--release' } else { '--debug' }
		mut d8_cmd := [
			d8,
			'--min-api ${opt.min_sdk_version}',
			dex_type,
			'--lib "' + android_runtime + '"',
			'--classpath obj',
			'--output ' + 'classes.zip',
		]
		d8_cmd << class_files
		util.verbosity_print_cmd(d8_cmd, opt.verbosity)
		util.run_or_error(d8_cmd)!
		util.unzip('classes.zip', 'bin') or {
			return error('${error_tag}:' + @LINE + ' error unzipping classes.zip to bin: ${err}')
		}
		os.cp('classes.zip', os.join_path(artifacts_path, 'classes.zip')) or {
			return error(err.msg())
		}
		os.rm('classes.zip') or { return error(err.msg()) }
	} else {
		dx_cmd := [
			dx,
			'--verbose',
			'--dex',
			'--output=' + os.join_path('bin', 'classes.dex'),
			'obj', // TODO specify obj_path ?
		]
		util.verbosity_print_cmd(dx_cmd, opt.verbosity)
		util.run_or_error(dx_cmd)!
	}

	/*
	$if !windows {
		// TODO
		if opt.verbosity > 2 {
			dexdump_cmd := [
				os.join_path(build_tools_path, 'dexdump'),
				'dexdump',
				'-d',
				os.join_path('bin', 'classes.dex'),
			]
			util.verbosity_print_cmd(dexdump_cmd, 3)
			util.run_or_error(dexdump_cmd) !
		}
	}*/

	// Second run
	aapt_cmd = [
		aapt,
		'package',
		'-v',
		'-f',
		'-S "' + res_path + '"',
		'-M "' + os.join_path(package_path, 'AndroidManifest.xml') + '"',
		'-A "' + assets_path + '"',
		'-I "' + android_runtime + '"',
		'-F "' + tmp_unaligned_product + '"',
		'bin', // TODO specify bin_path ?
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_error(aapt_cmd)!

	opt.verbose(2, 'Adding libs to "${tmp_unaligned_product}"...')

	// Add libs to product
	mut collected_libs := map[string][]string{}
	collected_libs[build_path] = os.walk_ext(os.join_path(build_path, 'lib'), '.so')
	for lib_extra_path in opt.libs_extra {
		collected_extra_libs := os.walk_ext(os.join_path(lib_extra_path), '.so')
		for collected_extra_lib in collected_extra_libs {
			path_split := collected_extra_lib.split(os.path_separator)
			for path_part in path_split {
				if path_part in supported_lib_folders {
					opt.verbose(3, 'Adding extra lib "${collected_extra_lib}"...')
					os.cp(collected_extra_lib, os.join_path(libs_extra_path, 'lib', path_part,
						os.file_name(collected_extra_lib))) or { return error(err.msg()) }
					break
				}
			}
		}
	}
	collected_libs[libs_extra_path] = os.walk_ext(os.join_path(libs_extra_path, 'lib'),
		'.so')

	for lib_path, libs in collected_libs {
		os.chdir(lib_path) or {}
		for lib in libs {
			mut lib_s := lib.replace(lib_path + os.path_separator, '')
			$if windows {
				// NOTE This is necessary for paths to work when packaging up on Windows
				lib_s = lib_s.replace(os.path_separator, '/')
			}
			aapt_cmd = [
				aapt,
				'add',
				'-v',
				'"' + tmp_unaligned_product + '"',
				'"' + lib_s + '"',
			]
			util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
			util.run_or_error(aapt_cmd)!
		}
	}

	os.chdir(pwd) or {
		return error('${error_tag}: error while changing work directory to "${pwd}":\n${err}')
	}

	zipalign_cmd := [
		zipalign,
		'-v',
		'-f 4',
		'"' + tmp_unaligned_product + '"',
		'"' + tmp_unsigned_product + '"',
	]
	util.verbosity_print_cmd(zipalign_cmd, opt.verbosity)
	util.run_or_error(zipalign_cmd)!

	// Sign the APK
	keystore := resolve_keystore(opt.keystore)!

	if opt.is_prod && os.file_name(keystore.path) == 'debug.keystore' {
		vabutil.vab_warning('It looks like you are using the debug.keystore file to sign your application built in production mode ("-prod").')
	}

	$if windows {
		// TODO Workaround apksigner and Java > 8 (1.8.0) BUG
		// Error message we are trying to prevent:
		// -Djava.ext.dirs=C:<path>lib is not supported.  Use -classpath instead.
		if jdk_semantic_version > semver.build(1, 8, 0) && os.exists(apksigner) {
			mut patched_apksigner := os.join_path(os.dir(apksigner),
				os.file_name(apksigner).all_before_last('.') + '_patched.bat')
			if !os.exists(patched_apksigner) {
				mut contents := os.read_file(apksigner) or { '' }
				if contents != '' && contents.contains('-Djava.ext.dirs=') {
					contents = contents.replace_once('-Djava.ext.dirs=', '-classpath ')
					os.write_file(patched_apksigner, contents) or { patched_apksigner = apksigner }
				} else {
					patched_apksigner = apksigner
				}
				opt.verbose(2, 'Using patched apksigner (${patched_apksigner})')
			}
			apksigner = patched_apksigner
		}
		// Workaround END
	}

	mut apksigner_cmd := [
		apksigner,
		'sign',
		'--ks "' + keystore.path + '"',
		'--ks-pass pass:' + keystore.password,
		'--ks-key-alias "' + keystore.alias + '"',
		'--key-pass pass:' + keystore.alias_password,
		'--out "' + tmp_product + '"',
		'"' + tmp_unsigned_product + '"',
	]
	util.verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	util.run_or_error(apksigner_cmd)!

	apksigner_cmd = [
		apksigner,
		'verify',
		'-v',
		'"' + tmp_product + '"',
	]
	util.verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	util.run_or_error(apksigner_cmd)!

	if os.is_file(opt.output_file) {
		opt.verbose(2, 'Removing previous output "${opt.output_file}"')
		os.rm(opt.output_file) or {
			return error('${error_tag}: error while removing "${opt.output_file}":\n${err}')
		}
	}

	opt.verbose(2, 'Moving product from "${tmp_product}" to "${opt.output_file}"')

	os.mv_by_cp(tmp_product, opt.output_file) or {
		return error('${error_tag}: error while moving product "${tmp_product}" to "${opt.output_file}": ${err}')
	}
}

// package_aab ouputs an Android .aab package file based on the `PackageOptions`.
fn package_aab(opt PackageOptions) ! {
	error_tag := @MOD + '.' + @FN
	// Initially adapted from:
	// https://musteresel.github.io/posts/2019/07/build-android-app-bundle-on-command-line.html
	pwd := os.getwd()

	build_path := os.join_path(opt.work_dir, 'build')
	libs_extra_path := os.join_path(opt.work_dir, 'libs')
	build_tools_path := os.join_path(sdk.build_tools_root(), opt.build_tools)

	// Remove any previous extra libs
	if os.is_dir(libs_extra_path) {
		os.rmdir_all(libs_extra_path) or {}
	}
	for supported_lib_folder in supported_lib_folders {
		supported_lib_folder_path := os.join_path(libs_extra_path, 'lib', supported_lib_folder)
		os.mkdir_all(supported_lib_folder_path) or {
			return error('${error_tag}: error while making directory "${supported_lib_folder_path}":\n${err}')
		}
	}

	// Used for various bug workarounds below
	build_tools_semantic_version := semver.from(opt.build_tools) or {
		return error('${error_tag}' + ':' + @LINE +
			' error converting build-tools version "${opt.build_tools}" to semantic version.\nsemver: ${err}')
	}

	// Used for various bug workarounds below
	jdk_semantic_version := semver.from(java.jdk_version()) or {
		return error('${error_tag}' + ':' + @LINE +
			' error converting jdk_version "${java.jdk_version()}" to semantic version.\nsemver: ${err}')
	}

	java_exe := os.join_path(java.jre_bin_path(), 'java')
	javac := os.join_path(java.jdk_bin_path(), 'javac')
	jarsigner := os.join_path(java.jdk_bin_path(), 'jarsigner')
	mut dx := os.join_path(build_tools_path, 'dx')
	mut d8 := os.join_path(build_tools_path, 'd8') // Not available prior to build-tools v28.0.1
	$if windows {
		dx += '.bat'
		d8 += '.bat'
	}
	bundletool := env.bundletool() // Run with "java -jar ..."
	aapt2 := env.aapt2()

	// Prepare and modify package skeleton shipped with vab
	// Copy assets etc.
	package_base := opt.prepare_base_fn(opt)!
	package_path := package_base.package_path
	assets_path := package_base.assets_path

	output_fn := os.file_name(opt.output_file).replace(os.file_ext(opt.output_file), '')
	tmp_product := os.join_path(opt.work_dir, '${output_fn}.aab')
	tmp_unsigned_product := os.join_path(opt.work_dir, '${output_fn}.unsigned.aab')
	// tmp_unaligned_product := os.join_path(opt.work_dir, '${output_fn}.unaligned.apk')

	os.rm(tmp_product) or {}
	os.rm(tmp_unsigned_product) or {}
	// os.rm(tmp_unaligned_product) or { }

	android_runtime := os.join_path(sdk.platforms_root(), 'android-' + opt.api_level,
		'android.jar')

	src_path := os.join_path(package_path, 'src')
	res_path := os.join_path(package_path, 'res')

	classes_path := os.join_path(package_path, 'classes')
	os.mkdir_all(classes_path) or {
		return error('${error_tag}: error while making directory "${classes_path}":\n${err}')
	}
	staging_path := os.join_path(package_path, 'staging')
	// os.mkdir_all(staging_path) or { panic(err) }
	os.rmdir(staging_path) or {}

	os.chdir(package_path) or {
		return error('${error_tag}: error while changing work directory to "${package_path}":\n${err}')
	}

	opt.verbose(2, 'Compiling resources...')

	compiled_resources_path := 'compiled_resources'
	// https://developer.android.com/studio/command-line/aapt2#compile
	// NOTE aapt2 compile project/app/src/main/res/**/* -o compiled_resources
	// The above expansion of "*" does not work on all platforms - so on Windows we gather the files manually.
	// On Unix we then save a lot of tool invokations.
	$if !windows {
		aapt2_cmd := [
			aapt2,
			'compile',
			os.join_path(res_path, '**', '*'),
			'-o',
			'compiled_resources.tmp.zip',
		]
		util.verbosity_print_cmd(aapt2_cmd, opt.verbosity)
		util.run_or_error(aapt2_cmd)!
		util.unzip('compiled_resources.tmp.zip', compiled_resources_path) or {
			return error('${error_tag}: error while unpacking compiled_resources.tmp.zip to "${compiled_resources_path}":\n${err}')
		}
	} $else {
		mut files := []string{}
		os.walk_with_context(res_path, &files, fn (mut files []string, path string) {
			if os.is_file(path) {
				files << path
			}
		})
		os.mkdir(compiled_resources_path) or {}
		for file in files {
			aapt2_cmd := [
				aapt2,
				'compile',
				'"${file}"',
				'-o',
				compiled_resources_path,
			]
			util.verbosity_print_cmd(aapt2_cmd, opt.verbosity)
			util.run_or_error(aapt2_cmd)!
		}
	}

	opt.verbose(2, 'Preparing resources and assets...')

	// aapt2 link --proto-format -o temporary.apk \
	//      -I android_sdk/platforms/android-NN/android.jar \
	//      --manifest project/app/src/main/AndroidManifest.xml \
	//      -R compiled_resources/*.flat \
	//      --auto-add-overlay --java gen
	$if !windows {
		aapt2_link_cmd := [
			aapt2,
			'link',
			'--proto-format',
			'-o',
			'temporary.apk',
			'-I "' + android_runtime + '"',
			'--manifest "' + os.join_path(package_path, 'AndroidManifest.xml') + '"',
			'-R',
			os.join_path('compiled_resources', '*.flat'),
			'-A "' + assets_path + '"',
			'--auto-add-overlay --java gen',
		]
		util.verbosity_print_cmd(aapt2_link_cmd, opt.verbosity)
		util.run_or_error(aapt2_link_cmd)!
	} $else {
		mut files := []string{}
		os.walk_with_context(compiled_resources_path, &files, fn (mut files []string, path string) {
			if path.ends_with('.flat') {
				files << path
			}
		})
		mut file_args := ''
		for file in files {
			file_args += '"${file}" '
		}
		file_args = file_args.trim(' ')
		aapt2_link_cmd := [
			aapt2,
			'link',
			'--proto-format',
			'-o',
			'temporary.apk',
			'-I "' + android_runtime + '"',
			'--manifest "' + os.join_path(package_path, 'AndroidManifest.xml') + '"',
			'-R',
			file_args,
			'-A "' + assets_path + '"',
			'--auto-add-overlay --java gen',
		]
		util.verbosity_print_cmd(aapt2_link_cmd, opt.verbosity)
		util.run_or_error(aapt2_link_cmd)!
	}

	mut javac_source_version := '1.7'
	mut javac_target_version := '1.7'
	if jdk_semantic_version >= semver.build(20, 0, 0) {
		javac_source_version = '1.8'
		javac_target_version = '1.8'
	}

	// Compile java sources
	opt.verbose(2, 'Compiling java sources ${javac_source_version}/${javac_target_version}...')

	java_sources := os.walk_ext(src_path, '.java')
	java_gen_sources := os.walk_ext(os.join_path(package_path, 'gen'), '.java')

	// javac -source 1.7 -target 1.7 \
	//  -bootclasspath $JAVA_HOME/jre/lib/rt.jar \
	//  -classpath android_sdk/platforms/android-NN/android.jar \
	//  -d classes \
	//  gen/**/*.java project/app/src/main/java/**/*.java

	mut javac_cmd := [
		javac,
		'-source ${javac_source_version}',
		'-target ${javac_target_version}',
		'-bootclasspath "' + android_runtime + '"',
		'-d classes',
		'-classpath .',
	]
	javac_cmd << java_gen_sources
	javac_cmd << java_sources

	util.verbosity_print_cmd(javac_cmd, opt.verbosity)
	util.run_or_error(javac_cmd)!

	// unzip temporary.apk -d staging
	util.unzip('temporary.apk', staging_path) or {
		return error('${error_tag}: error while unpacking temporary.apk to "${staging_path}":\n${err}')
	}

	manifest_dir := os.join_path(staging_path, 'manifest')
	os.mkdir_all(manifest_dir) or {
		return error('${error_tag}: error while making directory "${manifest_dir}":\n${err}')
	}
	os.mv(os.join_path(staging_path, 'AndroidManifest.xml'), manifest_dir) or {
		return error('${error_tag}: error while moving AndroidManifest from "${staging_path}" to "${manifest_dir}":\n${err}')
	}

	opt.verbose(2, 'Adding libs...')

	// Add libs to product
	mut collected_libs := map[string][]string{}
	collected_libs[build_path] = os.walk_ext(os.join_path(build_path, 'lib'), '.so')
	for lib_extra_path in opt.libs_extra {
		collected_extra_libs := os.walk_ext(os.join_path(lib_extra_path), '.so')
		for collected_extra_lib in collected_extra_libs {
			path_split := collected_extra_lib.split(os.path_separator)
			for path_part in path_split {
				if path_part in supported_lib_folders {
					opt.verbose(3, 'Adding extra lib "${collected_extra_lib}"...')
					os.cp(collected_extra_lib, os.join_path(libs_extra_path, 'lib', path_part,
						os.file_name(collected_extra_lib))) or { panic(err) }
					break
				}
			}
		}
	}
	collected_libs[libs_extra_path] = os.walk_ext(os.join_path(libs_extra_path, 'lib'),
		'.so')

	for lib_path, libs in collected_libs {
		for lib in libs {
			lib_base := lib.replace(lib_path + os.path_separator, '')
			os.mkdir_all(os.join_path(staging_path, os.dir(lib_base))) or {
				return error('${error_tag}: error while making directory to "${os.join_path(staging_path,
					os.dir(lib_base))}":\n${err}')
			}
			os.cp_all(lib, os.join_path(staging_path, lib_base), true) or {
				return error('${error_tag}:' + @LINE +
					' error copying "${lib}" to ${os.join_path(staging_path, lib_base)}:\n${err}')
			}
		}
	}

	$if windows {
		// TODO Workaround dx and Java > 8 (1.8.0) BUG
		// Error message we are trying to prevent:
		// -Djava.ext.dirs=C:<path>lib is not supported.  Use -classpath instead.
		if jdk_semantic_version > semver.build(1, 8, 0) {
			if os.exists(dx) {
				mut patched_dx := os.join_path(os.dir(dx), os.file_name(dx).all_before_last('.') +
					'_patched.bat')
				if !os.exists(patched_dx) {
					mut dx_contents := os.read_file(dx) or { '' }
					if dx_contents != '' && dx_contents.contains('-Djava.ext.dirs=') {
						dx_contents = dx_contents.replace_once('-Djava.ext.dirs=', '-classpath ')
						os.write_file(patched_dx, dx_contents) or { patched_dx = dx }
					} else {
						patched_dx = dx
					}
					opt.verbose(2, 'Using patched dx (${patched_dx})')
				}
				dx = patched_dx
			}

			if os.exists(d8) {
				mut patched_d8 := os.join_path(os.dir(d8), os.file_name(d8).all_before_last('.') +
					'_patched.bat')
				if !os.exists(patched_d8) {
					mut d8_contents := os.read_file(d8) or { '' }
					if d8_contents != '' && d8_contents.contains('-Djava.ext.dirs=') {
						d8_contents = d8_contents.replace_once('-Djava.ext.dirs=', '-classpath ')
						os.write_file(patched_d8, d8_contents) or { patched_d8 = d8 }
					} else {
						patched_d8 = d8
					}
					opt.verbose(2, 'Using patched d8 (${patched_d8})')
				}
				d8 = patched_d8
			}
		}
		// Workaround END
	}

	dex_output_path := os.join_path(staging_path, 'dex')
	os.mkdir_all(dex_output_path) or {
		return error('${error_tag}: could not make directory "${dex_output_path}":\n${err}')
	}

	// Dex either with `dx` or `d8`
	if build_tools_semantic_version >= semver.build(28, 0, 1) {
		mut class_files := os.walk_ext('classes', '.class')
		class_files = class_files.filter(!it.contains('$')) // Filter out R$xxx.class files
		class_files = class_files.map(fn (e string) string {
			return '"${e}"'
		})
		mut dex_type := if opt.is_prod { '--release' } else { '--debug' }
		mut d8_cmd := [
			d8,
			dex_type,
			'--lib "' + android_runtime + '"',
			'--classpath .',
			'--output ' + 'classes.zip',
		]
		d8_cmd << class_files
		util.verbosity_print_cmd(d8_cmd, opt.verbosity)
		util.run_or_error(d8_cmd)!
		util.unzip('classes.zip', dex_output_path) or {
			return error('${error_tag}:' + @LINE +
				' error unzipping classes.zip to ${dex_output_path}: ${err}')
		}
		os.rm('classes.zip') or {
			return error('${error_tag}: error while removing "classes.zip":\n${err}')
		}
	} else {
		// dx --dex --output=staging/dex/classes.dex classes/
		dx_cmd := [
			dx,
			'--verbose',
			'--dex',
			'--output=' + os.join_path(dex_output_path, 'classes.dex'),
			'classes/',
		]
		util.verbosity_print_cmd(dx_cmd, opt.verbosity)
		util.run_or_error(dx_cmd)!
	}

	// cd staging; zip -r ../base.zip *
	os.chdir(staging_path) or {
		return error('${error_tag}: error while changing work directory to "${staging_path}":\n${err}')
	}

	base_zip_file := os.join_path(package_path, 'base.zip')

	util.zip_folder(staging_path, base_zip_file) or {
		return error('${error_tag}: error while zip packing "${staging_path}" as "${base_zip_file}":\n${err}')
	}

	// TODO Workaround bundletool, Java <= 8 (1.8.0) and ZIP64 BUG - Android development. just. keeps. giving...
	// NOTE This workaround probably won't work for zip files larger than 4GB...
	// Error message we are trying to prevent:
	// com.android.tools.build.bundletool.model.exceptions.CommandExecutionException: File 'base.zip' does not seem to be a valid ZIP file.
	// ...
	// Caused by: java.util.zip.ZipException: invalid CEN header (bad signature)
	if jdk_semantic_version <= semver.build(1, 8, 0)
		|| (jdk_semantic_version >= semver.build(20, 0, 0)
		&& jdk_semantic_version < semver.build(21, 0, 0)) {
		$if !windows {
			opt.verbose(2, 'Working around Java/bundletool/ZIP64 BUG...')
			os.rm(base_zip_file) or {}
			zip_cmd := [
				'zip',
				'-r',
				base_zip_file,
				'*',
			]
			util.verbosity_print_cmd(zip_cmd, opt.verbosity)
			util.run_or_error(zip_cmd)!
		}
	}
	// Workaround END

	os.chdir(package_path) or {
		return error('${error_tag}: error while changing work directory to "${package_path}":\n${err}')
	}

	// java -jar bundletool build-bundle --modules=base.zip --output=bundle.aab
	bundletool_cmd := [
		java_exe,
		'-jar',
		bundletool,
		'build-bundle',
		'--modules=' + 'base.zip',
		'--output=' + tmp_unsigned_product,
	]
	util.verbosity_print_cmd(bundletool_cmd, opt.verbosity)
	util.run_or_error(bundletool_cmd)!

	os.cp_all(tmp_unsigned_product, tmp_product, true) or {
		return error('${error_tag}: error while copying "${tmp_unsigned_product}" to "${tmp_product}":\n${err}')
	}

	// Make debug signing key if nothing else is provided
	keystore := resolve_keystore(opt.keystore)!

	// Sign the APK
	if opt.is_prod && os.file_name(keystore.path) == 'debug.keystore' {
		vabutil.vab_warning('It looks like you are using the debug.keystore\nfile to sign your application build in production mode ("-prod").')
	}
	// jarsigner -verbose -keystore ~/.android/debug.keystore -storepass android -keypass android path/to/my.apk androiddebugkey
	jarsigner_cmd := [
		jarsigner,
		'-verbose',
		'-keystore "' + keystore.path + '"',
		'-storepass',
		keystore.password,
		'-keypass',
		keystore.alias_password,
		'"' + tmp_product + '"',
		keystore.alias,
	]
	util.verbosity_print_cmd(jarsigner_cmd, opt.verbosity)
	util.run_or_error(jarsigner_cmd)!

	// java -jar bundletool.jar validate --bundle application.aab
	bundletool_validate_cmd := [
		java_exe,
		'-jar',
		'"' + bundletool + '"',
		'validate',
		'--bundle',
		// tmp_unsigned_product
		'"' + tmp_product + '"',
	]
	util.verbosity_print_cmd(bundletool_validate_cmd, opt.verbosity)
	// println(util.run(bundletool_validate_cmd).output)
	util.run_or_error(bundletool_validate_cmd)!

	os.chdir(pwd) or {
		return error('${error_tag}: error while changing work directory to "${pwd}":\n${err}')
	}

	opt.verbose(2, 'Moving product from "${tmp_product}" to "${opt.output_file}"')
	os.mv_by_cp(tmp_product, opt.output_file) or {
		return error('${error_tag}: error while moving product "${tmp_product}" to "${opt.output_file}":\n${err}')
	}
}

// ensure_no_developer_team_package_id returns an error if the `opt.package_id` is the
// same as `opt.default_package_id` or the same package_id domain as `android.default_package_id`.
pub fn ensure_no_developer_team_package_id(opt PackageOptions) ! {
	is_default_pkg_id := opt.package_id == opt.default_package_id
	if is_default_pkg_id || opt.package_id.starts_with(default_package_id) {
		if opt.package_id.starts_with(default_package_id) {
			return error('Do not deploy to app stores using the default package id namespace ("${default_package_id}.*")\nYou can set your own package ID with the --package-id flag')
		} else {
			return error('Do not deploy to app stores using the default package id "${opt.default_package_id}"\nYou can set your own package ID with the --package-id flag')
		}
	}
}

pub struct PackageBase {
pub:
	package_path string // Path to the base setup
	assets_path  string // Path to assets
}

// prepare_package_base prepares, modifies a "package base files" / app skeleton
// and returns useful paths to itself and paths within it.
//
// An "Package base files" / App skeleton" is a special structure of files and
// directories that `vab`'s packaging step use as a basis to make the final APK or AAB package.
// prepare_package_base is run before Java tooling does the actual packaging.
//
// Preparing includes operations such as:
// * Creating the directory structures that are returned
// * Modifying template files, like `AndroidManifest.xml` or the Java Activity
// * Moving files into place
// * Copy assets to a location where `vab` can pick them up
pub fn prepare_package_base(opt PackageOptions) !PackageBase {
	opt.verbose(1, 'Preparing ${opt.format} base"')
	package_path := opt.package_root()
	opt.verbose(2, 'Removing previous package directory "${package_path}"')
	os.rmdir_all(package_path) or {}
	paths.ensure(package_path) or { return error('${@FN}: ${err}') }

	base_files_path := opt.base_files
	if os.is_dir(base_files_path) {
		if opt.verbosity > 1 {
			opt.verbose(2, 'Copying base files from "${base_files_path}" to "${package_path}"')
			if opt.verbosity > 2 {
				os.walk(base_files_path, fn (entry string) {
					println(entry)
				})
			}
		}
		os.cp_all(base_files_path, package_path, true) or { return error('${@FN}: ${err}') }
	}

	// Figure out path overrides
	// TODO overrides is currently based on heuristics - this should probably change to avoid accidental copying of huge data amounts
	mut overrides_path := opt.overrides_path
	if overrides_path == '' {
		if os.is_dir(opt.input) {
			if os.is_dir(os.join_path(opt.input, 'java')) {
				overrides_path = os.join_path(opt.input, 'java')
			}
		} else {
			if os.is_dir(os.join_path(os.dir(opt.input), 'java')) {
				overrides_path = os.join_path(os.dir(opt.input), 'java')
			}
		}
	}

	mut is_override := false
	if os.is_dir(overrides_path) {
		if opt.verbosity > 1 {
			opt.verbose(2, 'Copying base file overrides from "${overrides_path}" to "${package_path}"')
			if opt.verbosity > 2 {
				os.walk(overrides_path, fn (entry string) {
					println(entry)
				})
			}
		}
		os.cp_all(overrides_path, package_path, true) or { return error('${@FN}: ${err}') }
		is_override = true
	} else {
		opt.verbose(3, 'No overrides found in "${overrides_path}"')
	}

	opt.verbose(1, 'Modifying base files...')

	pkg_id_split := opt.package_id.split('.')
	package_id_path := pkg_id_split.join(os.path_separator)
	paths.ensure(os.join_path(package_path, 'src', package_id_path)) or {
		return error('${@FN}: ${err}')
	}

	default_pkg_id_split := opt.default_package_id.split('.')
	default_pkg_id_path := default_pkg_id_split.join(os.path_separator)

	native_activity_path := os.join_path(package_path, 'src', default_pkg_id_path)
	activity_file_name := opt.default_activity_name + '.java'
	native_activity_file := os.join_path(native_activity_path, activity_file_name)
	$if debug {
		eprintln('Native activity file: "${native_activity_file}"')
	}
	if os.is_file(native_activity_file) {
		opt.verbose(2, 'Modifying native activity "${native_activity_file}"')

		mut java_src := os.read_file(native_activity_file) or { return error('${@FN}: ${err}') }

		if !is_override {
			// Change package id in template
			// r'.*package\s+(io.v.android).*'
			mut re := regex.regex_opt(r'.*package\s+(' + opt.default_package_id + r');') or {
				return error('${@FN}: ${err}')
			}
			mut start, _ := re.match_string(java_src)
			// Set new package ID if found
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := java_src[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing package id "${r}" with "${opt.package_id}"')
				}
				java_src = java_src[0..re.groups[0]] + opt.package_id +
					java_src[re.groups[1]..java_src.len]
			}
		} else {
			opt.verbose(2, 'Skipping replacing package id since "${opt.package_id}" is user provided')
		}

		// Set lib_name
		mut re := regex.regex_opt(r'.*loadLibrary.*"(.*)".*') or { return error('${@FN}: ${err}') }
		mut start, _ := re.match_string(java_src)
		// Set new package ID if found
		if start >= 0 && re.groups.len > 0 {
			if opt.verbosity > 1 {
				r := java_src[re.groups[0]..re.groups[1]]
				opt.verbose(2, 'Replacing init library "${r}" with "${opt.lib_name}"')
			}
			java_src = java_src[0..re.groups[0]] + opt.lib_name +
				java_src[re.groups[1]..java_src.len]
		}
		os.write_file(os.join_path(package_path, 'src', package_id_path, activity_file_name),
			java_src) or { return error('${@FN}: ${err}') }

		// Remove left-overs from vab's copied skeleton
		if opt.package_id != opt.default_package_id {
			os.rm(native_activity_file) or { panic(err) }
			mut v_default_package_id := default_pkg_id_split.clone()
			for i := v_default_package_id.len - 1; i >= 0; i-- {
				if os.is_dir_empty(os.join_path(package_path, 'src', v_default_package_id.join(os.path_separator))) {
					if opt.verbosity > 1 {
						p := os.join_path(package_path, 'src', v_default_package_id.join(os.path_separator))
						opt.verbose(2, 'Removing default left-over directory "${p}"')
					}
					os.rmdir_all(os.join_path(package_path, 'src', v_default_package_id.join(os.path_separator))) or {
						return error('${@FN}: ${err}')
					}
				}
				v_default_package_id.pop()
			}
		}
	}
	// Replace in AndroidManifest.xml
	if !is_override {
		manifest_path := os.join_path(package_path, 'AndroidManifest.xml')
		if os.is_file(manifest_path) {
			opt.verbose(2, 'Modifying manifest "${manifest_path}"')
			mut manifest := os.read_file(manifest_path) or { return error('${@FN}: ${err}') }
			mut re := regex.regex_opt(r'.*<manifest\s.*\spackage\s*=\s*"(.+)".*>') or {
				return error('${@FN}: ${err}')
			}
			mut start, _ := re.match_string(manifest)
			// Set package ID if found
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing package id "${r}" with "${opt.package_id}"')
				}
				manifest = manifest[0..re.groups[0]] + opt.package_id +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*<manifest\s.*\sandroid:versionCode\s*=\s*"(.+)".*>') or {
				return error('${@FN}: ${err}')
			}
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing version code "${r}" with "${opt.version_code}"')
				}
				manifest = manifest[0..re.groups[0]] + opt.version_code.str() +
					manifest[re.groups[1]..manifest.len]
			}

			is_debug_build := ('-cg' in opt.v_flags)
			re = regex.regex_opt(r'.*<application\s.*android:debuggable\s*=\s*"(.*)".*>') or {
				return error('${@FN}: ${err}')
			}
			start, _ = re.match_string(manifest)
			// Set debuggable attribute if found
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing debuggable "${r}" with "${is_debug_build}"')
				}
				manifest = manifest[0..re.groups[0]] + is_debug_build.str() +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*\s+android:minSdkVersion\s*=\s*"(.*)".*') or {
				return error('${@FN}: ${err}')
			}
			start, _ = re.match_string(manifest)
			// TODO figure out this absolute mess.
			// When building with Android native it's recommended (even, sometimes, quite necessary) that minSdkVersion is equal to compiled sdk version :(
			// Otherwise you have all kinds of cryptic errors when the app is started.
			// Google Play, at the time of writing, requires to build against level 29 as a minimum (App will be rejected otherwise).
			// OTOH According to e.g. http://android-doc.github.io/ndk/guides/stable_apis.html it *should* be safe
			// that we specify 21 as a minimum API level and then live happily ever after...
			// What a complete mess :(
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing minimum SDK version "${r}" with "${opt.min_sdk_version}"')
				}
				manifest = manifest[0..re.groups[0]] + opt.min_sdk_version.str() +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*\s+android:targetSdkVersion\s*=\s*"(.*)".*') or {
				return error('${@FN}: ${err}')
			}
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing target SDK version "${r}" with "${opt.api_level}"')
				}
				manifest = manifest[0..re.groups[0]] + opt.api_level +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*uses-feature android:glEsVersion\s*=\s*"(.*)".*') or {
				return error('${@FN}: ${err}')
			}
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				gles_version_hex := '0x000' + opt.gles_version.str() + '0000'
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing declaration of OpenGL ES version "${r}" with "${gles_version_hex}"')
				}
				manifest = manifest[0..re.groups[0]] + gles_version_hex +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*<activity\s.*android:name\s*=\s*"(.*)".*>') or {
				return error('${@FN}: ${err}')
			}
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				fq_activity_name := opt.package_id + '.' + opt.activity_name
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					opt.verbose(2, 'Replacing activity name "${r}" with "${fq_activity_name}"')
				}
				manifest = manifest[0..re.groups[0]] + fq_activity_name +
					manifest[re.groups[1]..manifest.len]
			}

			os.write_file(manifest_path, manifest) or { return error('${@FN}: ${err}') }
		}
	}
	// Replace in res/values/strings.xml
	strings_path := os.join_path(package_path, 'res', 'values', 'strings.xml')
	if os.is_file(strings_path) {
		mut content := os.read_file(strings_path) or { return error('${@FN}: ${err}') }
		mut re := regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"v_app_name"\s*>(.*)</string.*') or {
			return error('${@FN}: ${err}')
		}
		mut start, _ := re.match_string(content)
		// Set app name if found
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.app_name + content[re.groups[1]..content.len]
		}
		// Set lib name if found
		re = regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"v_lib_name"\s*>(.*)</string.*') or {
			return error('${@FN}: ${err}')
		}
		start, _ = re.match_string(content)
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.lib_name + content[re.groups[1]..content.len]
		}
		// Set package ID if found
		re = regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"v_package_name"\s*>(.*)</string.*') or {
			return error('${@FN}: ${err}')
		}
		start, _ = re.match_string(content)
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.package_id + content[re.groups[1]..content.len]
		}

		os.write_file(strings_path, content) or { return error('${@FN}: ${err}') }
	}

	return PackageBase{
		package_path: package_path
		assets_path:  prepare_assets(opt)!
	}
}

// prepare_assets depends on prepare_package_base...
fn prepare_assets(opt PackageOptions) !string {
	package_path := opt.package_root()

	opt.verbose(1, 'Copying assets...')

	icon_path := os.join_path(package_path, 'res', 'mipmap')
	is_default_pkg_id := opt.package_id == opt.default_package_id
	if !is_default_pkg_id && os.is_file(opt.icon) && os.file_ext(opt.icon) == '.png' {
		paths.ensure(icon_path) or { return error('${@FN}: ${err}') }
		icon_file := os.join_path(icon_path, 'icon.png')
		opt.verbose(1, 'Copying icon...')
		os.rm(icon_file) or {}
		os.cp(opt.icon, icon_file) or { return error('${@FN}: ${err}') }
	}
	if opt.icon_mipmaps {
		out_path := os.dir(icon_path) // should be "res" directory
		template_icon_file := if opt.icon != '' {
			opt.icon
		} else {
			ls := os.walk_ext(icon_path, '.png')
			ls[ls.index(ls[0] or { '' })] or { '' }
		}
		if os.is_file(template_icon_file) {
			opt.verbose(1, 'Generating mipmap icons...')
			make_icon_mipmaps(template_icon_file, out_path)
		}
	}

	assets_path := os.join_path(package_path, 'assets')
	paths.ensure(assets_path) or { return error('${@FN}: ${err}') }

	mut included_asset_paths := []string{}

	/*
	NOTE kept for debugging purposes
	test_asset := os.join_path(assets_path, 'test.txt')
	os.rm(test_asset)
	mut fh := open_file(test_asset, 'w+', 0o755) or { panic(err) }
	fh.write('test')
	fh.close()
	*/

	mut assets_by_side_path := opt.input
	if os.is_file(opt.input) {
		assets_by_side_path = os.dir(opt.input)
	}
	// Look for "assets" dir in same location as input
	assets_by_side := os.join_path(assets_by_side_path, 'assets')
	if os.is_dir(assets_by_side) {
		opt.verbose(1, 'Including assets from "${assets_by_side}"')
		os.cp_all(assets_by_side, assets_path, false) or { return error('${@FN}: ${err}') }
		included_asset_paths << os.real_path(assets_by_side)
	}
	// Look for "assets" in dir above input dir.
	// This is mostly an exception for the shared example assets in V examples.
	if os.real_path(assets_by_side_path).contains(os.join_path('v', 'examples')) {
		assets_above := os.real_path(os.join_path(assets_by_side_path, '..', 'assets'))
		if os.is_dir(assets_above) {
			if os.real_path(assets_above) in included_asset_paths {
				opt.verbose(2, 'Skipping "${assets_above}" since it\'s already included')
			} else {
				opt.verbose(1, 'Including assets from "${assets_above}"')
				os.cp_all(assets_above, assets_path, false) or { return error('${@FN}: ${err}') }
				included_asset_paths << os.real_path(assets_by_side)
			}
		}
	}
	// Look for "assets" dir in current dir
	assets_in_dir := 'assets'
	if os.is_dir(assets_in_dir) {
		assets_in_dir_resolved := os.real_path(os.join_path(os.getwd(), assets_in_dir))
		if assets_in_dir_resolved in included_asset_paths {
			opt.verbose(2, 'Skipping "${assets_in_dir}" since it\'s already included')
		} else {
			opt.verbose(1, 'Including assets from "${assets_in_dir}"')
			os.cp_all(assets_in_dir, assets_path, false) or { return error('${@FN}: ${err}') }
			included_asset_paths << assets_in_dir_resolved
		}
	}
	// Look in user provided dir
	for user_asset in opt.assets_extra {
		if os.is_dir(user_asset) {
			user_asset_resolved := os.real_path(user_asset)
			if user_asset_resolved in included_asset_paths {
				opt.verbose(2, 'Skipping "${user_asset}" since it\'s already included')
			} else {
				opt.verbose(1, 'Including assets from "${user_asset}"')
				os.cp_all(user_asset, assets_path, false) or { return error('${@FN}: ${err}') }
				included_asset_paths << user_asset_resolved
			}
		} else {
			os.cp(user_asset, assets_path) or {
				vabutil.vab_notice('Skipping invalid or non-existent asset file "${user_asset}"')
			}
		}
	}
	return assets_path
}

fn make_icon_mipmaps(icon_file string, out_path string) {
	mut img := stbi.load(icon_file, desired_channels: 0) or {
		vabutil.vab_error('${@FN}: error loading ${icon_file}: ${err}')
		return
	}
	defer { img.free() }

	mut threads := []thread{}
	for size in mipmap_icon_sizes {
		threads << spawn make_icon_mipmap(img, out_path, size, size)
	}
	threads.wait()
}

fn make_icon_mipmap(img stbi.Image, out_path string, w int, h int) {
	res_str := match w {
		192 {
			'xxxhdpi'
		}
		144 {
			'xxhdpi'
		}
		96 {
			'xhdpi'
		}
		72 {
			'hdpi'
		}
		48 {
			'mdpi'
		}
		else {
			vabutil.vab_error('${@FN}: unsupported width of ${w} passed')
			return
		}
	}
	rs_img := stbi.resize_uint8(img, w, h) or {
		vabutil.vab_error('${@FN}: error resizing ${w} to ${out_path}: ${err}')
		return
	}
	defer { rs_img.free() }
	new_path := os.join_path(out_path, 'mipmap-${res_str}')

	// eprintln(rs_img)
	os.mkdir_all(new_path) or {
		vabutil.vab_error('${@FN}: error creating output directory ${new_path}: ${err}')
		return
	}
	out_file := os.join_path(new_path, 'icon.png')
	os.rm(out_file) or {}
	stbi.stbi_write_png(out_file, rs_img.width, rs_img.height, rs_img.nr_channels, rs_img.data,
		(rs_img.width * rs_img.nr_channels)) or {
		vabutil.vab_error('${@FN}: error writing output file ${out_file}: ${err}')
		return
	}
}

pub fn is_valid_package_id(id string) ! {
	// https://developer.android.com/studio/build/application-id
	// https://stackoverflow.com/a/39331217
	// https://gist.github.com/rishabhmhjn/8663966
	raw_segments := id.split('.')
	if '' in raw_segments {
		// no empty (a..b.c) segments
		return error('"${id}" has one or more empty segments')
	}
	segments := raw_segments.filter(it != '')
	if segments.len < 2 {
		// No top-level names
		return error('"${id}" has too few segments')
	}
	first := segments.first()
	first_char := first[0]
	if first_char.is_digit() {
		// 1st segment can't start with a digit
		return error('first segment in "${id}" can not start with a digit')
	}
	if !(first_char >= `a` && first_char <= `z`) {
		// 1st segment can't start with any other than a small letter
		return error('first segment in "${id}" should start with a small letter')
	}
	// segment can't be a java keyword
	for segment in segments {
		if segment in java.keywords {
			return error('"${segment}" in "${id}" is a keyword')
		}
	}
	last := segments.last()

	mut is_all_digits := true
	for c in last {
		if !c.is_digit() {
			is_all_digits = false
			break
		}
	}
	if is_all_digits {
		// Last segment can't be all digits
		return error('"${id}" last segment can not be all digits')
	}

	for segment in segments {
		for c in segment {
			// is not [a-z0-9_]
			if !((c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) || c == `_`) {
				return error('"${c.ascii_str()}" in "${id}" is not allowed')
			}
		}
	}
}
