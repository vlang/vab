// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
import vab.android.ndk

fn test_ndk_host_arch() {
	$if linux {
		assert ndk.host_arch() == 'linux-x86_64'
	} $else $if macos {
		assert ndk.host_arch() == 'darwin-x86_64'
	} $else $if windows {
		assert ndk.host_arch() == 'windows-x86_64'
	} $else {
		assert ndk.host_arch() == 'unknown'
	}
}

fn test_ndk_arch_to_instruction_set() {
	assert ndk.arch_to_instruction_set('armeabi-v7a') == 'armv7a'
	assert ndk.arch_to_instruction_set('arm64-v8a') == 'aarch64'
	assert ndk.arch_to_instruction_set('x86') == 'i686'
	assert ndk.arch_to_instruction_set('x86_64') == 'x86_64'
}

fn test_compiler_triplet() {
	assert ndk.compiler_triplet('armeabi-v7a') == 'armv7a-linux-androideabi'
	assert ndk.compiler_triplet('arm64-v8a') == 'aarch64-linux-android'
	assert ndk.compiler_triplet('x86') == 'i686-linux-android'
	assert ndk.compiler_triplet('x86_64') == 'x86_64-linux-android'
}
