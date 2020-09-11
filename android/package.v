module android

import os

import java

import android.sdk

pub struct PackageOptions {
	verbosity		int
	work_dir		string

	api_level		string
	build_tools		string

	input			string
	assets_extra	[]string
	output_file		string

	keystore		string
	keystore_alias	string
	base_files		string
}

pub fn package(opt PackageOptions) bool {

	// Build APK
	if opt.verbosity > 0 {
		println('Preparing package')
	}

	build_path := os.join_path(opt.work_dir, 'build')
	build_tools_path := os.join_path(sdk.build_tools_root(),opt.build_tools)

	javac := os.join_path(java.jdk_root(),'bin','javac')
	keytool := os.join_path(java.jdk_root(),'bin','keytool')
	aapt := os.join_path(build_tools_path,'aapt')
	dx := os.join_path(build_tools_path,'dx')
	zipalign := os.join_path(build_tools_path,'zipalign')
	apksigner := os.join_path(build_tools_path,'apksigner')

	//work_dir := opt.work_dir
	//VAPK_OUT=${VAPK}/..

	package_path := os.join_path(opt.work_dir, 'package')
	os.mkdir_all(package_path)

	base_files_path := opt.base_files

	cp_all(base_files_path, package_path, false)


	if opt.verbosity > 0 {
		println('Copying assets')
	}

	assets_path := os.join_path(package_path, 'assets')
	os.mkdir_all(assets_path)

	/*
	test_asset := os.join_path(assets_path, 'test.txt')
	os.rm(test_asset)
	mut fh := open_file(test_asset, 'w+', 0o755) or { panic(err) }
	fh.write('test')
	fh.close()*/

	mut assets_by_side_path := opt.input
	if ! os.is_dir(opt.input) {
		assets_by_side_path = os.dir(opt.input)
	}

	// Look for "assets" dir in same location as input
	assets_by_side := os.join_path(assets_by_side_path,'assets')
	if os.is_dir(assets_by_side) {
		if opt.verbosity > 0 {
			println('Including assets from ${assets_by_side}')
		}
		cp_all(assets_by_side, assets_path, false)
	}

	// Look for "assets" dir in current dir
	assets_in_dir := 'assets'
	if os.is_dir(assets_in_dir) {
		if opt.verbosity > 0 {
			println('Including assets from ${assets_in_dir}')
		}
		cp_all(assets_in_dir, assets_path, false)
	}

	// Look in user provided dir
	for user_asset in opt.assets_extra {
		if os.is_dir(user_asset) {
			if opt.verbosity > 0 {
				println('Including assets from ${user_asset}')
			}
			os.cp_all(user_asset, assets_path, false)
		} else {
			os.cp(user_asset, assets_path) or {
				eprintln('Skipping invalid asset file ${user_asset}')
			}
		}
	}

	output_fn := os.file_name(opt.output_file).replace(os.file_ext(opt.output_file),'')
	tmp_product := os.join_path(opt.work_dir, '${output_fn}.apk')
	tmp_unsigned_product := os.join_path(opt.work_dir, '${output_fn}.unsigned.apk')
	tmp_unaligned_product := os.join_path(opt.work_dir, '${output_fn}.unaligned.apk')

	os.rm(tmp_product)
	os.rm(tmp_unsigned_product)
	os.rm(tmp_unaligned_product)

	android_runtime := os.join_path(sdk.platforms_root(),'android-'+opt.api_level,'android.jar')

	src_path := os.join_path(package_path,'src')
	res_path := os.join_path(package_path,'res')

	obj_path := os.join_path(package_path, 'obj')
	os.mkdir_all(obj_path)
	bin_path := os.join_path(package_path, 'bin')
	os.mkdir_all(bin_path)

	mut aapt_cmd := [
		aapt,
		'package',
		'-v',
		'-f',
		'-m',
		'-M '+os.join_path(package_path,'AndroidManifest.xml'),
		'-S '+res_path,
		'-J '+src_path,
		'-A '+assets_path,
		'-I '+android_runtime
		//'--target-sdk-version ${ANDROIDTARGET}'
	]
	verbosity_print_cmd(aapt_cmd, opt.verbosity)
	run_else_exit(aapt_cmd)

	pwd := os.getwd()
	os.chdir(package_path)

	// Compile java sources
	java_sources := walk_ext(os.join_path(package_path,'src'), '.java')

	mut javac_cmd := [
		javac,
		'-d obj', //+obj_path,
		'-source 1.7',
		'-target 1.7',
		'-sourcepath src',
		'-bootclasspath '+android_runtime
	]
	javac_cmd << java_sources

	verbosity_print_cmd(javac_cmd, opt.verbosity)
	run_else_exit(javac_cmd)

	// Dex
	dx_cmd := [
		dx,
		'--verbose',
		'--dex',
		'--output='+os.join_path('bin','classes.dex'),
		'obj', //obj_path
	]
	verbosity_print_cmd(dx_cmd, opt.verbosity)
	run_else_exit(dx_cmd)

	// Second run
	aapt_cmd = [
		aapt,
		'package',
		'-v',
		'-f',
		'-S '+res_path,
		'-M '+os.join_path(package_path,'AndroidManifest.xml'),
		'-A '+assets_path,
		'-I '+android_runtime,
		'-F '+tmp_unaligned_product,
		'bin' //bin_path
	]
	verbosity_print_cmd(aapt_cmd, opt.verbosity)
	run_else_exit(aapt_cmd)


	os.chdir(build_path)

	collect_libs := walk_ext(os.join_path(build_path,'lib'), '.so')

	for lib in collect_libs {
		lib_s := lib.replace(build_path+os.path_separator, '')
		aapt_cmd = [
			aapt,
			'add',
			'-v',
			tmp_unaligned_product,
			lib_s
		]
		verbosity_print_cmd(aapt_cmd, opt.verbosity)
		run_else_exit(aapt_cmd)
	}

	os.chdir(pwd)


	zipalign_cmd := [
		zipalign,
		'-v',
		'-f 4',
		tmp_unaligned_product,
		tmp_unsigned_product
	]
	verbosity_print_cmd(zipalign_cmd, opt.verbosity)
	run_else_exit(zipalign_cmd)

	// Sign the APK
	keystore_file := opt.keystore
	if !os.is_file(keystore_file) {
		if opt.verbosity > 0 {
			println('Generating debug.keystore')
		}
		keytool_cmd := [
			keytool,
			'-genkeypair',
			'-keystore '+keystore_file,
			'-storepass android',
			'-alias androiddebugkey',
			'-keypass android',
			'-keyalg RSA',
			'-validity 10000',
			'-dname \'CN=,OU=,O=,L=,S=,C=\''
		]
		verbosity_print_cmd(keytool_cmd, opt.verbosity)
		run_else_exit(keytool_cmd)
	}

	// Defaults from Android debug key
	mut keystore_alias := 'androiddebugkey'
	mut keystore_password := 'android'
	mut keystore_alias_password := keystore_password

	if opt.keystore_alias != '' {
		keystore_alias = opt.keystore_alias
	}
	if os.getenv('KEYSTORE_PASSWORD') != '' {
		keystore_password = os.getenv('KEYSTORE_PASSWORD')
	}
	if os.getenv('KEYSTORE_ALIAS_PASSWORD') != '' {
		keystore_alias_password = os.getenv('KEYSTORE_ALIAS_PASSWORD')
	}

	mut apksigner_cmd := [
		apksigner,
		'sign',
		'--ks "'+keystore_file+'"',
		'--ks-pass pass:'+keystore_password,
		'--key-pass pass:'+keystore_alias_password,
		'--ks-key-alias "'+keystore_alias+'"',
		'--out '+tmp_product,
		tmp_unsigned_product
	]
	verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	run_else_exit(apksigner_cmd)

	apksigner_cmd = [
		apksigner,
		'verify',
		'-v',
		tmp_product,
	]
	verbosity_print_cmd(apksigner_cmd, opt.verbosity)
	run_else_exit(apksigner_cmd)

	os.mv_by_cp(tmp_product, opt.output_file) or { panic(err) }

	return true
}
