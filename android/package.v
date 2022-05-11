// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import regex
import java
import android.env
import android.sdk
import android.util

pub const (
	default_app_name          = 'V Test App'
	default_package_id        = 'io.v.android'
	default_activity_name     = 'VActivity'
	default_package_format    = 'apk'
	default_min_sdk_version   = 21
	supported_package_formats = ['apk', 'aab']
)

// PackageFormat holds all supported package formats
pub enum PackageFormat {
	apk
	aab
}

// PackageOptions represents an Android package configuration
pub struct PackageOptions {
	verbosity       int
	work_dir        string
	is_prod         bool
	api_level       string
	min_sdk_version int = android.default_min_sdk_version
	gles_version    int
	build_tools     string
	format          PackageFormat = .apk
	app_name        string
	lib_name        string
	package_id      string
	activity_name   string
	icon            string
	version_code    int
	v_flags         []string
	input           string
	assets_extra    []string
	output_file     string
	keystore        Keystore
	base_files      string
	overrides_path  string // Path to user provided files that will override `base_files`. `java` (and later `kotlin` TODO) subdirs are recognized
}

// package outputs one of the supported Android package formats based on
// `PackageOptions`
pub fn package(opt PackageOptions) bool {
	if opt.verbosity > 0 {
		println('Preparing package "$opt.package_id"...')
	}
	// Validate package_id to our best effort
	if !is_valid_package_id(opt.package_id) {
		eprintln('Package id "$opt.package_id" seems invalid.')
		eprintln('Please consult the Android documentation for details:')
		eprintln('https://developer.android.com/studio/build/application-id')
		return false
	}
	if opt.is_prod && opt.package_id == android.default_package_id {
		eprintln('Package id "$opt.package_id" is used by the V team.')
		eprintln('Please do not deploy to app stores using package id "$android.default_package_id".')
		return false
	}
	// Build APK
	return match opt.format {
		.apk {
			package_apk(opt)
		}
		.aab {
			package_aab(opt)
		}
	}
}

// package_apk ouputs an Android .apk package file based on the `PackageOptions`.
fn package_apk(opt PackageOptions) bool {
	pwd := os.getwd()

	build_path := os.join_path(opt.work_dir, 'build')
	build_tools_path := os.join_path(sdk.build_tools_root(), opt.build_tools)

	javac := os.join_path(java.jdk_bin_path(), 'javac')
	aapt := os.join_path(build_tools_path, 'aapt')
	mut dx := os.join_path(build_tools_path, 'dx')
	$if windows {
		dx += '.bat'
	}
	zipalign := os.join_path(build_tools_path, 'zipalign')
	mut apksigner := os.join_path(build_tools_path, 'apksigner')
	$if windows {
		apksigner += '.bat'
	}

	// work_dir := opt.work_dir
	// VAPK_OUT=${VAPK}/..

	// Prepare and modify package skeleton shipped with vab
	// Copy assets etc.
	package_path, assets_path := prepare_base(opt)

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
	os.mkdir_all(obj_path) or { panic(err) }
	bin_path := os.join_path(package_path, 'bin')
	os.mkdir_all(bin_path) or { panic(err) }

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
		'-I "' + android_runtime + '"' /* '--target-sdk-version ${ANDROIDTARGET}' */,
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_exit(aapt_cmd)

	os.chdir(package_path) or {}

	// Compile java sources
	if opt.verbosity > 1 {
		println('Compiling java sources')
	}
	java_sources := os.walk_ext(os.join_path(package_path, 'src'), '.java')

	mut javac_cmd := [
		javac,
		'-d obj', /* +obj_path, */
		'-source 1.7',
		'-target 1.7',
		'-classpath .',
		'-sourcepath src',
		'-bootclasspath "' + android_runtime + '"',
	]
	javac_cmd << java_sources

	util.verbosity_print_cmd(javac_cmd, opt.verbosity)
	util.run_or_exit(javac_cmd)

	// Dex
	dx_cmd := [
		dx,
		'--verbose',
		'--dex',
		'--output=' + os.join_path('bin', 'classes.dex'),
		'obj' /* obj_path, */,
	]
	util.verbosity_print_cmd(dx_cmd, opt.verbosity)
	util.run_or_exit(dx_cmd)

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
		'bin' /* bin_path */,
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_exit(aapt_cmd)

	os.chdir(build_path) or {}

	collected_libs := os.walk_ext(os.join_path(build_path, 'lib'), '.so')

	for lib in collected_libs {
		mut lib_s := lib.replace(build_path + os.path_separator, '')
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
		util.run_or_exit(aapt_cmd)
	}

	os.chdir(pwd) or {}

	zipalign_cmd := [
		zipalign,
		'-v',
		'-f 4',
		'"' + tmp_unaligned_product + '"',
		'"' + tmp_unsigned_product + '"',
	]
	util.verbosity_print_cmd(zipalign_cmd, opt.verbosity)
	util.run_or_exit(zipalign_cmd)

	// Sign the APK
	keystore := resolve_keystore(opt.keystore, opt.verbosity)

	if opt.is_prod && os.file_name(keystore.path) == 'debug.keystore' {
		eprintln('Warning: It looks like you are using the debug.keystore file to sign your application built in production mode ("-prod").')
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
	util.run_or_exit(apksigner_cmd)

	apksigner_cmd = [
		apksigner,
		'verify',
		'-v',
		'"' + tmp_product + '"',
	]
	util.verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	util.run_or_exit(apksigner_cmd)

	if opt.verbosity > 1 {
		println('Moving product from "$tmp_product" to "$opt.output_file"')
	}
	os.mv_by_cp(tmp_product, opt.output_file) or { panic(err) }

	return true
}

// package_aab ouputs an Android .aab package file based on the `PackageOptions`.
fn package_aab(opt PackageOptions) bool {
	// Initially adapted from:
	// https://musteresel.github.io/posts/2019/07/build-android-app-bundle-on-command-line.html
	pwd := os.getwd()

	build_path := os.join_path(opt.work_dir, 'build')
	build_tools_path := os.join_path(sdk.build_tools_root(), opt.build_tools)

	java_exe := os.join_path(java.jre_bin_path(), 'java')
	javac := os.join_path(java.jdk_bin_path(), 'javac')
	jarsigner := os.join_path(java.jdk_bin_path(), 'jarsigner')
	mut dx := os.join_path(build_tools_path, 'dx')
	$if windows {
		dx += '.bat'
	}
	bundletool := env.bundletool() // Run with "java -jar ..."
	aapt2 := env.aapt2()

	package_path, assets_path := prepare_base(opt)

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
	os.mkdir_all(classes_path) or { panic(err) }
	staging_path := os.join_path(package_path, 'staging')
	// os.mkdir_all(staging_path) or { panic(err) }
	os.rmdir(staging_path) or {}

	os.chdir(package_path) or {}

	if opt.verbosity > 1 {
		println('Compiling resources')
	}

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
		util.run_or_exit(aapt2_cmd)
		util.unzip('compiled_resources.tmp.zip', compiled_resources_path) or { panic(err) }
	} $else {
		mut files := []string{}
		os.walk_with_context(res_path, &files, fn (mut files []string, path string) {
			files << path
		})
		os.mkdir(compiled_resources_path) or {}
		for file in files {
			aapt2_cmd := [
				aapt2,
				'compile',
				'"$file"',
				'-o',
				compiled_resources_path,
			]
			util.verbosity_print_cmd(aapt2_cmd, opt.verbosity)
			util.run_or_exit(aapt2_cmd)
		}
	}

	if opt.verbosity > 1 {
		println('Preparing resources and assets')
	}
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
		util.run_or_exit(aapt2_link_cmd)
	} $else {
		mut files := []string{}
		os.walk_with_context(compiled_resources_path, &files, fn (mut files []string, path string) {
			if path.ends_with('.flat') {
				files << path
			}
		})
		mut file_args := ''
		for file in files {
			file_args += '"$file" '
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
		util.run_or_exit(aapt2_link_cmd)
	}

	if opt.verbosity > 1 {
		println('Compiling java sources')
	}
	java_sources := os.walk_ext(src_path, '.java')
	java_gen_sources := os.walk_ext(os.join_path(package_path, 'gen'), '.java')

	// javac -source 1.7 -target 1.7 \
	//  -bootclasspath $JAVA_HOME/jre/lib/rt.jar \
	//  -classpath android_sdk/platforms/android-NN/android.jar \
	//  -d classes \
	//  gen/**/*.java project/app/src/main/java/**/*.java

	mut javac_cmd := [
		javac,
		'-source 1.7',
		'-target 1.7',
		//'-bootclasspath ' + os.join_path(java.jre_root(),'lib','rt.jar')
		'-bootclasspath "' + android_runtime + '"',
		//'-classpath ' + android_runtime,
		'-d classes',
		'-classpath .',
	]
	javac_cmd << java_gen_sources
	javac_cmd << java_sources

	util.verbosity_print_cmd(javac_cmd, opt.verbosity)
	util.run_or_exit(javac_cmd)

	// unzip temporary.apk -d staging
	util.unzip('temporary.apk', staging_path) or { panic(err) }

	os.mkdir_all(os.join_path(staging_path, 'manifest')) or { panic(err) }
	os.mv(os.join_path(staging_path, 'AndroidManifest.xml'), os.join_path(staging_path,
		'manifest')) or { panic(err) }

	// copy libs
	collected_libs := os.walk_ext(os.join_path(build_path, 'lib'), '.so')
	for lib in collected_libs {
		lib_base := lib.replace(build_path + os.path_separator, '')
		os.mkdir_all(os.join_path(staging_path, os.dir(lib_base))) or { panic(err) }
		os.cp_all(lib, os.join_path(staging_path, lib_base), true) or { panic(err) }
	}
	// os.chdir(pwd) or {}

	os.mkdir_all(os.join_path(staging_path, 'dex')) or { panic(err) }
	// dx --dex --output=staging/dex/classes.dex classes/
	dx_cmd := [
		dx,
		'--verbose',
		'--dex',
		'--output=' + os.join_path(staging_path, 'dex', 'classes.dex'),
		'classes/',
	]
	util.verbosity_print_cmd(dx_cmd, opt.verbosity)
	util.run_or_exit(dx_cmd)

	// cd staging; zip -r ../base.zip *
	os.chdir(staging_path) or {}

	util.zip_folder(staging_path, os.join_path(package_path, 'base.zip')) or { panic(err) }

	// TODO temp CI investigation
	list_zip_cmd := [
		'unzip',
		'-l',
		os.join_path(package_path, 'base.zip'),
	]
	util.verbosity_print_cmd(zip_cmd, opt.verbosity)
	println(util.run(list_zip_cmd))

	os.chdir(package_path) or {}

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
	util.run_or_exit(bundletool_cmd)

	os.cp_all(tmp_unsigned_product, tmp_product, true) or { panic(err) }

	// Make debug signing key if nothing else is provided
	keystore := resolve_keystore(opt.keystore, opt.verbosity)

	// Sign the APK
	if opt.is_prod && os.file_name(keystore.path) == 'debug.keystore' {
		eprintln('Warning: It looks like you are using the debug.keystore\nfile to sign your application build in production mode ("-prod").')
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
	util.run_or_exit(jarsigner_cmd)

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
	util.run_or_exit(bundletool_validate_cmd)

	os.chdir(pwd) or {}

	if opt.verbosity > 1 {
		println('Moving product from "$tmp_product" to "$opt.output_file"')
	}
	os.mv_by_cp(tmp_product, opt.output_file) or { panic(err) }

	return true
}

fn prepare_base(opt PackageOptions) (string, string) {
	format := match opt.format {
		.apk {
			'apk'
		}
		.aab {
			'aab'
		}
	}
	package_path := os.join_path(opt.work_dir, 'package', format)
	if opt.verbosity > 0 {
		println('Removing previous package directory "$package_path"')
	}
	os.rmdir_all(package_path) or {}
	os.mkdir_all(package_path) or { panic(err) }

	base_files_path := opt.base_files
	if os.is_dir(base_files_path) {
		if opt.verbosity > 0 {
			println('Copying base files from "$base_files_path" to "$package_path"')
			if opt.verbosity > 2 {
				os.walk(base_files_path, fn (entry string) {
					println(entry)
				})
			}
		}
		os.cp_all(base_files_path, package_path, true) or { panic(err) }
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
		if opt.verbosity > 0 {
			println('Copying base file overrides from "$overrides_path" to "$package_path"')
			if opt.verbosity > 2 {
				os.walk(overrides_path, fn (entry string) {
					println(entry)
				})
			}
		}
		os.cp_all(overrides_path, package_path, true) or { panic(err) }
		is_override = true
	} else {
		if opt.verbosity > 2 {
			println('No overrides found in "$overrides_path"')
		}
	}

	if opt.verbosity > 0 {
		println('Modifying base files')
	}

	is_default_pkg_id := opt.package_id == android.default_package_id
	if opt.is_prod && (is_default_pkg_id || opt.package_id.starts_with(android.default_package_id)) {
		if opt.package_id.starts_with(android.default_package_id) {
			panic('Do not deploy to app stores using the default V package id namespace "$android.default_package_id"\nYou can set your own package ID with the --package-id flag')
		} else {
			panic('Do not deploy to app stores using the default V package id "$android.default_package_id"\nYou can set your own package ID with the --package-id flag')
		}
	}
	pkg_id_split := opt.package_id.split('.')
	package_id_path := pkg_id_split.join(os.path_separator)
	os.mkdir_all(os.join_path(package_path, 'src', package_id_path)) or { panic(err) }

	default_pkg_id_split := android.default_package_id.split('.')
	default_pkg_id_path := default_pkg_id_split.join(os.path_separator)

	native_activity_path := os.join_path(package_path, 'src', default_pkg_id_path)
	activity_file_name := android.default_activity_name + '.java'
	native_activity_file := os.join_path(native_activity_path, activity_file_name)
	$if debug {
		eprintln('Native activity file: "$native_activity_file"')
	}
	if os.is_file(native_activity_file) {
		if opt.verbosity > 1 {
			println('Modifying native activity "$native_activity_file"')
		}
		mut java_src := os.read_file(native_activity_file) or { panic(err) }

		if !is_override {
			// Change package id in template
			// r'.*package\s+(io.v.android).*'
			mut re := regex.regex_opt(r'.*package\s+(' + android.default_package_id + r');') or {
				panic(err)
			}
			mut start, _ := re.match_string(java_src)
			// Set new package ID if found
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := java_src[re.groups[0]..re.groups[1]]
					println('Replacing package id "$r" with "$opt.package_id"')
				}
				java_src = java_src[0..re.groups[0]] + opt.package_id +
					java_src[re.groups[1]..java_src.len]
			}
		} else {
			if opt.verbosity > 1 {
				println('Skipping replacing package id since "$opt.package_id" is user provided')
			}
		}

		// Set lib_name
		mut re := regex.regex_opt(r'.*loadLibrary.*"(.*)".*') or { panic(err) }
		mut start, _ := re.match_string(java_src)
		// Set new package ID if found
		if start >= 0 && re.groups.len > 0 {
			if opt.verbosity > 1 {
				r := java_src[re.groups[0]..re.groups[1]]
				println('Replacing init library "$r" with "$opt.lib_name"')
			}
			java_src = java_src[0..re.groups[0]] + opt.lib_name +
				java_src[re.groups[1]..java_src.len]
		}
		os.write_file(os.join_path(package_path, 'src', package_id_path, activity_file_name),
			java_src) or { panic(err) }

		// Remove left-overs from vab's copied skeleton
		if opt.package_id != android.default_package_id {
			os.rm(native_activity_file) or { panic(err) }
			mut v_default_package_id := default_pkg_id_split.clone()
			for i := v_default_package_id.len - 1; i >= 0; i-- {
				if os.is_dir_empty(os.join_path(package_path, 'src', v_default_package_id.join(os.path_separator))) {
					if opt.verbosity > 1 {
						p := os.join_path(package_path, 'src', v_default_package_id.join(os.path_separator))
						println('Removing default left-over directory "$p"')
					}
					os.rmdir_all(os.join_path(package_path, 'src', v_default_package_id.join(os.path_separator))) or {
						panic(err)
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
			if opt.verbosity > 1 {
				println('Modifying manifest "$manifest_path"')
			}
			mut manifest := os.read_file(manifest_path) or { panic(err) }
			mut re := regex.regex_opt(r'.*<manifest\s.*\spackage\s*=\s*"(.+)".*>') or { panic(err) }
			mut start, _ := re.match_string(manifest)
			// Set package ID if found
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					println('Replacing package id "$r" with "$opt.package_id"')
				}
				manifest = manifest[0..re.groups[0]] + opt.package_id +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*<manifest\s.*\sandroid:versionCode\s*=\s*"(.+)".*>') or {
				panic(err)
			}
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					println('Replacing version code "$r" with "$opt.version_code"')
				}
				manifest = manifest[0..re.groups[0]] + opt.version_code.str() +
					manifest[re.groups[1]..manifest.len]
			}

			is_debug_build := ('-cg' in opt.v_flags)
			re = regex.regex_opt(r'.*<application\s.*android:debuggable\s*=\s*"(.*)".*>') or {
				panic(err)
			}
			start, _ = re.match_string(manifest)
			// Set debuggable attribute if found
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					println('Replacing debuggable "$r" with "$is_debug_build"')
				}
				manifest = manifest[0..re.groups[0]] + is_debug_build.str() +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*\s+android:minSdkVersion\s*=\s*"(.*)".*') or { panic(err) }
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
					println('Replacing minimum SDK version "$r" with "$opt.min_sdk_version"')
				}
				manifest = manifest[0..re.groups[0]] + opt.min_sdk_version.str() +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*\s+android:targetSdkVersion\s*=\s*"(.*)".*') or { panic(err) }
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					println('Replacing target SDK version "$r" with "$opt.api_level"')
				}
				manifest = manifest[0..re.groups[0]] + opt.api_level +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*uses-feature android:glEsVersion\s*=\s*"(.*)".*') or {
				panic(err)
			}
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				gles_version_hex := '0x000' + opt.gles_version.str() + '0000'
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					println('Replacing declaration of OpenGL ES version "$r" with "$gles_version_hex"')
				}
				manifest = manifest[0..re.groups[0]] + gles_version_hex +
					manifest[re.groups[1]..manifest.len]
			}

			re = regex.regex_opt(r'.*<activity\s.*android:name\s*=\s*"(.*)".*>') or { panic(err) }
			start, _ = re.match_string(manifest)
			if start >= 0 && re.groups.len > 0 {
				fq_activity_name := opt.package_id + '.' + opt.activity_name
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					println('Replacing activity name "$r" with "$fq_activity_name"')
				}
				manifest = manifest[0..re.groups[0]] + fq_activity_name +
					manifest[re.groups[1]..manifest.len]
			}

			os.write_file(manifest_path, manifest) or { panic(err) }
		}
	}
	// Replace in res/values/strings.xml
	strings_path := os.join_path(package_path, 'res', 'values', 'strings.xml')
	if os.is_file(strings_path) {
		mut content := os.read_file(strings_path) or { panic(err) }
		mut re := regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"v_app_name"\s*>(.*)</string.*') or {
			panic(err)
		}
		mut start, _ := re.match_string(content)
		// Set app name if found
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.app_name + content[re.groups[1]..content.len]
		}
		// Set lib name if found
		re = regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"v_lib_name"\s*>(.*)</string.*') or {
			panic(err)
		}
		start, _ = re.match_string(content)
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.lib_name + content[re.groups[1]..content.len]
		}
		// Set package ID if found
		re = regex.regex_opt(r'.*<resources>.*<string\s*name\s*=\s*"v_package_name"\s*>(.*)</string.*') or {
			panic(err)
		}
		start, _ = re.match_string(content)
		if start >= 0 && re.groups.len > 0 {
			content = content[0..re.groups[0]] + opt.package_id + content[re.groups[1]..content.len]
		}
		// println(content)
		// println(strings_path)
		os.write_file(strings_path, content) or { panic(err) }
	}

	if opt.verbosity > 0 {
		println('Copying assets')
	}

	if !is_default_pkg_id && os.is_file(opt.icon) && os.file_ext(opt.icon) == '.png' {
		icon_path := os.join_path(package_path, 'res', 'mipmap', 'icon.png')
		if opt.verbosity > 0 {
			println('Copying icon')
		}
		os.rm(icon_path) or { panic(err) }
		os.cp(opt.icon, icon_path) or { panic(err) }
	}

	assets_path := os.join_path(package_path, 'assets')
	os.mkdir_all(assets_path) or { panic(err) }

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
		if opt.verbosity > 0 {
			println('Including assets from "$assets_by_side"')
		}
		os.cp_all(assets_by_side, assets_path, false) or { panic(err) }
		included_asset_paths << os.real_path(assets_by_side)
	}
	// Look for "assets" in dir above input dir.
	// This is mostly an exception for the shared example assets in V examples.
	if os.real_path(assets_by_side_path).contains(os.join_path('v', 'examples')) {
		assets_above := os.real_path(os.join_path(assets_by_side_path, '..', 'assets'))
		if os.is_dir(assets_above) {
			if os.real_path(assets_above) in included_asset_paths {
				if opt.verbosity > 1 {
					println('Skipping "$assets_above" since it\'s already included')
				}
			} else {
				if opt.verbosity > 0 {
					println('Including assets from "$assets_above"')
				}
				os.cp_all(assets_above, assets_path, false) or { panic(err) }
				included_asset_paths << os.real_path(assets_by_side)
			}
		}
	}
	// Look for "assets" dir in current dir
	assets_in_dir := 'assets'
	if os.is_dir(assets_in_dir) {
		assets_in_dir_resolved := os.real_path(os.join_path(os.getwd(), assets_in_dir))
		if assets_in_dir_resolved in included_asset_paths {
			if opt.verbosity > 1 {
				println('Skipping "$assets_in_dir" since it\'s already included')
			}
		} else {
			if opt.verbosity > 0 {
				println('Including assets from "$assets_in_dir"')
			}
			os.cp_all(assets_in_dir, assets_path, false) or { panic(err) }
			included_asset_paths << assets_in_dir_resolved
		}
	}
	// Look in user provided dir
	for user_asset in opt.assets_extra {
		if os.is_dir(user_asset) {
			user_asset_resolved := os.real_path(user_asset)
			if user_asset_resolved in included_asset_paths {
				if opt.verbosity > 1 {
					println('Skipping "$user_asset" since it\'s already included')
				}
			} else {
				if opt.verbosity > 0 {
					println('Including assets from "$user_asset"')
				}
				os.cp_all(user_asset, assets_path, false) or { panic(err) }
				included_asset_paths << user_asset_resolved
			}
		} else {
			os.cp(user_asset, assets_path) or {
				eprintln('Skipping invalid or non-existent asset file "$user_asset"')
			}
		}
	}
	return package_path, assets_path
}

pub fn is_valid_package_id(id string) bool {
	// https://developer.android.com/studio/build/application-id
	// https://stackoverflow.com/a/39331217
	// https://gist.github.com/rishabhmhjn/8663966
	raw_segments := id.split('.')
	if '' in raw_segments {
		// no empty (a..b.c) segments
		return false
	}
	segments := raw_segments.filter(it != '')
	if segments.len < 2 {
		// No top-level names
		return false
	}
	first := segments.first()
	first_char := first[0]
	if first_char.is_digit() {
		// 1 segment can't start with a digit
		return false
	}
	if !(first_char >= `a` && first_char <= `z`) {
		// 1 segment can't start with any other than a small letter
		return false
	}
	// segment can't be a java keyword
	for segment in segments {
		if segment in java.keywords {
			return false
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
		return false
	}

	for segment in segments {
		for c in segment {
			// is not [a-z0-9_]
			if !((c >= `a` && c <= `z`) || (c >= `0` && c <= `9`) || c == `_`) {
				return false
			}
		}
	}

	return true
}
