import os
import vab.vabxt
import vab.vxt
import vab.android.util

const test_dir_base = os.join_path(os.vtmp_dir(), 'vab', 'tests', 'runtime')
const apk_arch_dirs = ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64', 'armeabi']

fn setup_apk_build(id string) (string, string) {
	test_dir := os.join_path(test_dir_base, id)
	os.rm(test_dir) or {}
	os.mkdir_all(test_dir) or { panic('mkdir_all failed making "${test_dir}": ${err}') }

	// vab (per design) implicitly deploys to any devices sat via `--device-id`.
	// Make sure no deployment is done after build if CI/other sets `ANDROID_SERIAL`
	os.unsetenv('ANDROID_SERIAL')
	vab := vabxt.vabexe()
	assert vab != '', 'vab needs to be installed to run this test'
	return vab, test_dir
}

fn v_example(path string) string {
	v_root := vxt.home()
	examples_root := os.join_path(v_root, 'examples')
	example := os.join_path(examples_root, ...path.split('/'))
	assert os.is_file(example) || os.is_dir(example) == true, 'example not found. Ensure a full V source install (with examples) is present'
	return example
}

fn run(cmd string) {
	eprintln('running: ${cmd}')
	res := os.execute(cmd)
	if res.exit_code != 0 {
		dump(res.output)
	}
	assert res.exit_code == 0
}

fn extract_and_check_apk(libname string, path string) {
	expected_lib_name := libname
	expected_apk := os.join_path(path, '${expected_lib_name}.apk')
	assert os.is_file(expected_apk)

	extract_dir := os.join_path(path, 'extracted')
	extracted_apk_path := os.join_path(extract_dir, expected_lib_name)
	util.unzip(expected_apk, extracted_apk_path) or {
		panic('unzip failed extracting "${expected_apk}": ${err}')
	}

	dump(os.ls(extracted_apk_path) or { panic('ls failed on "${extracted_apk_path}": ${err}') })
	// test that expected libs are actually present in the apk
	for arch in apk_arch_dirs {
		lib_dir := os.join_path(extracted_apk_path, 'lib', arch)
		dump(os.ls(lib_dir) or { panic('ls failed on "${lib_dir}": ${err}') })
		assert os.is_file(os.join_path(lib_dir, 'lib${expected_lib_name}.so'))
	}
}

fn test_build_apk_way_1() {
	vab, test_dir := setup_apk_build(@FN)

	vab_cmd := [vab, '-o', test_dir, v_example('gg/worker_thread.v')].join(' ')
	run(vab_cmd)

	extract_and_check_apk('v_test_app', test_dir)
}

fn test_build_apk_way_2() {
	vab, test_dir := setup_apk_build(@FN)

	vab_cmd := [vab, v_example('sokol/particles'), '-o', test_dir].join(' ')
	run(vab_cmd)

	extract_and_check_apk('v_test_app', test_dir)
}

fn test_build_apk_way_3() {
	vab, test_dir := setup_apk_build(@FN)

	vab_cmd := [vab, '-f "-d trace_moves_spool_to_sbin"', v_example('sokol/particles'),
		'-o', test_dir].join(' ')
	run(vab_cmd)

	extract_and_check_apk('v_test_app', test_dir)
}
