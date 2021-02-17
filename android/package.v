// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

import os
import regex
import java
import android.sdk
import android.util

pub const (
	default_app_name      = 'V Test App'
	default_package_id    = 'io.v.android'
	default_activity_name = 'VActivity'
)

pub struct PackageOptions {
	verbosity               int
	work_dir                string
	is_prod                 bool
	api_level               string
	build_tools             string
	app_name                string
	lib_name                string
	package_id              string
	activity_name           string
	icon                    string
	version_code            int
	v_flags                 []string
	input                   string
	assets_extra            []string
	output_file             string
	keystore                string
	keystore_alias          string
	keystore_password       string
	keystore_alias_password string
	base_files              string
}

pub fn package(opt PackageOptions) bool {
	// Build APK
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

	build_path := os.join_path(opt.work_dir, 'build')
	build_tools_path := os.join_path(sdk.build_tools_root(), opt.build_tools)

	javac := os.join_path(java.jdk_bin_path(), 'javac')
	keytool := os.join_path(java.jdk_bin_path(), 'keytool')
	aapt := os.join_path(build_tools_path, 'aapt')
	dx := os.join_path(build_tools_path, 'dx')
	zipalign := os.join_path(build_tools_path, 'zipalign')
	apksigner := os.join_path(build_tools_path, 'apksigner')

	// work_dir := opt.work_dir
	// VAPK_OUT=${VAPK}/..

	// Prepare and modify package skeleton shipped with vab
	// Copy assets etc.
	package_path, assets_path := prepare_base(opt)

	output_fn := os.file_name(opt.output_file).replace(os.file_ext(opt.output_file), '')
	tmp_product := os.join_path(opt.work_dir, '${output_fn}.apk')
	tmp_unsigned_product := os.join_path(opt.work_dir, '${output_fn}.unsigned.apk')
	tmp_unaligned_product := os.join_path(opt.work_dir, '${output_fn}.unaligned.apk')

	os.rm(tmp_product) or { }
	os.rm(tmp_unsigned_product) or { }
	os.rm(tmp_unaligned_product) or { }

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
		'-M ' + os.join_path(package_path, 'AndroidManifest.xml'),
		'-S ' + res_path,
		'-J ' + src_path,
		'-A ' + assets_path,
		'-I ' + android_runtime /* '--target-sdk-version ${ANDROIDTARGET}' */,
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_exit(aapt_cmd)

	pwd := os.getwd()
	os.chdir(package_path)

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
		'-cp .',
		'-sourcepath src',
		'-bootclasspath ' + android_runtime,
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
		'-S ' + res_path,
		'-M ' + os.join_path(package_path, 'AndroidManifest.xml'),
		'-A ' + assets_path,
		'-I ' + android_runtime,
		'-F ' + tmp_unaligned_product,
		'bin' /* bin_path */,
	]
	util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
	util.run_or_exit(aapt_cmd)

	os.chdir(build_path)

	collect_libs := os.walk_ext(os.join_path(build_path, 'lib'), '.so')

	for lib in collect_libs {
		lib_s := lib.replace(build_path + os.path_separator, '')
		aapt_cmd = [
			aapt,
			'add',
			'-v',
			tmp_unaligned_product,
			lib_s,
		]
		util.verbosity_print_cmd(aapt_cmd, opt.verbosity)
		util.run_or_exit(aapt_cmd)
	}

	os.chdir(pwd)

	zipalign_cmd := [
		zipalign,
		'-v',
		'-f 4',
		tmp_unaligned_product,
		tmp_unsigned_product,
	]
	util.verbosity_print_cmd(zipalign_cmd, opt.verbosity)
	util.run_or_exit(zipalign_cmd)

	// Sign the APK
	keystore_file := opt.keystore
	if !os.is_file(keystore_file) {
		if opt.verbosity > 0 {
			println('Generating debug.keystore')
		}
		keytool_cmd := [
			keytool,
			'-genkeypair',
			'-keystore ' + keystore_file,
			'-storepass android',
			'-alias androiddebugkey',
			'-keypass android',
			'-keyalg RSA',
			'-validity 10000',
			"-dname 'CN=,OU=,O=,L=,S=,C='",
		]
		util.verbosity_print_cmd(keytool_cmd, opt.verbosity)
		util.run_or_exit(keytool_cmd)
	}
	// Defaults from Android debug key
	mut keystore_alias := 'androiddebugkey'
	mut keystore_password := 'android'
	mut keystore_alias_password := keystore_password

	if opt.keystore_alias != '' {
		keystore_alias = opt.keystore_alias
	}
	if opt.keystore_password != '' {
		keystore_password = opt.keystore_password
	}
	if opt.keystore_alias_password != '' {
		keystore_alias_password = opt.keystore_alias_password
	}

	if opt.is_prod && os.file_name(keystore_file) == 'debug.keystore' {
		eprintln('Warning: It looks like you are using the debug.keystore\nfile to sign your application build in production mode ("-prod").')
	}

	mut apksigner_cmd := [
		apksigner,
		'sign',
		'--ks "' + keystore_file + '"',
		'--ks-pass pass:' + keystore_password,
		'--key-pass pass:' + keystore_alias_password,
		'--ks-key-alias "' + keystore_alias + '"',
		'--out ' + tmp_product,
		tmp_unsigned_product,
	]
	util.verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	util.run_or_exit(apksigner_cmd)

	apksigner_cmd = [
		apksigner,
		'verify',
		'-v',
		tmp_product,
	]
	util.verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	util.run_or_exit(apksigner_cmd)

	os.mv_by_cp(tmp_product, opt.output_file) or { panic(err) }

	return true
}

fn prepare_base(opt PackageOptions) (string, string) {
	package_path := os.join_path(opt.work_dir, 'package')
	if opt.verbosity > 0 {
		println('Removing previous package directory $package_path')
	}
	os.rmdir_all(package_path) or { }
	os.mkdir_all(package_path) or { panic(err) }

	base_files_path := opt.base_files
	if os.is_dir(base_files_path) {
		if opt.verbosity > 0 {
			println('Copying base files from $base_files_path to $package_path')
			if opt.verbosity > 2 {
				os.walk(base_files_path, fn (entry string) {
					println(entry)
				})
			}
		}
		os.cp_all(base_files_path, package_path, true) or { panic(err) }
	}

	mut user_files_path := ''
	if os.is_dir(opt.input) {
		if os.is_dir(os.join_path(opt.input, 'java')) {
			user_files_path = os.join_path(opt.input, 'java')
		}
	} else {
		if os.is_dir(os.join_path(os.dir(opt.input), 'java')) {
			user_files_path = os.join_path(os.dir(opt.input), 'java')
		}
	}

	mut is_custom := false
	if os.is_dir(user_files_path) {
		if opt.verbosity > 0 {
			println('Copying base files from $user_files_path to $package_path')
			if opt.verbosity > 2 {
				os.walk(user_files_path, fn (entry string) {
					println(entry)
				})
			}
		}
		os.cp_all(user_files_path, package_path, true) or { panic(err) }
		is_custom = true
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

		if !is_custom {
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
			v_default_package_id := default_pkg_id_split.clone()
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
	if !is_custom {
		manifest_path := os.join_path(package_path, 'AndroidManifest.xml')
		if os.is_file(manifest_path) {
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
			// When building with Android native it's recommended (even quite necessary) that minSdkVersion is equal to compiled sdk version :(
			// Otherwise you have all kinds of cryptic errors when the app is started.
			// Google Play, at the time of writing, requires to build against level 29 as a minimum (App will be rejected otherwise).
			if start >= 0 && re.groups.len > 0 {
				if opt.verbosity > 1 {
					r := manifest[re.groups[0]..re.groups[1]]
					println('Replacing api level "$r" with "$opt.api_level"')
				}
				manifest = manifest[0..re.groups[0]] + opt.api_level +
					manifest[re.groups[1]..manifest.len]
			}

			if opt.activity_name != '' {
				re = regex.regex_opt(r'.*<activity\s.*android:name\s*=\s*"(.*)".*>') or {
					panic(err)
				}
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

	/*
	test_asset := os.join_path(assets_path, 'test.txt')
	os.rm(test_asset)
	mut fh := open_file(test_asset, 'w+', 0o755) or { panic(err) }
	fh.write('test')
	fh.close()
	*/

	mut assets_by_side_path := opt.input
	if !os.is_dir(opt.input) {
		assets_by_side_path = os.dir(opt.input)
	}
	// Look for "assets" dir in same location as input
	assets_by_side := os.join_path(assets_by_side_path, 'assets')
	if os.is_dir(assets_by_side) {
		if opt.verbosity > 0 {
			println('Including assets from "$assets_by_side"')
		}
		os.cp_all(assets_by_side, assets_path, false) or { panic(err) }
	}
	// Look for "assets" in dir above input dir.
	// This is mostly an exception for the shared example assets in V examples.
	if os.real_path(assets_by_side_path).contains(os.join_path('v', 'examples')) {
		assets_above := os.real_path(os.join_path(assets_by_side_path, '..', 'assets'))
		if os.is_dir(assets_above) {
			if opt.verbosity > 0 {
				println('Including assets from "$assets_above"')
			}
			os.cp_all(assets_above, assets_path, false) or { panic(err) }
		}
	}
	// Look for "assets" dir in current dir
	assets_in_dir := 'assets'
	if os.is_dir(assets_in_dir) {
		if opt.verbosity > 0 {
			println('Including assets from "$assets_in_dir"')
		}
		os.cp_all(assets_in_dir, assets_path, false) or { panic(err) }
	}
	// Look in user provided dir
	for user_asset in opt.assets_extra {
		if os.is_dir(user_asset) {
			if opt.verbosity > 0 {
				println('Including assets from "$user_asset"')
			}
			os.cp_all(user_asset, assets_path, false) or { panic(err) }
		} else {
			os.cp(user_asset, assets_path) or {
				eprintln('Skipping invalid asset file "$user_asset"')
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
