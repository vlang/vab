// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
import android

const (
	valid_ids   = [
		'valid.package_id.ok',
		'your.org.android',
		'your_.org.android',
		'your._org.android',
		'your.o11rg.android',
		'your11.org.android',
		'yo11ur.org.android',
		'your.org23.android',
		'your.org.android23d',
		'your.org_.android',
		'your.org._android',
		'your.org_._android',
		'your.org.android_',
		'your.org.android32',
		'your.1.org.11212e',
	]
	invalid_ids = [
		'_ouch.invalid.package_id',
		'1.invalid.package_id',
		'abc',
		'',
		'a.b.10',
		'your.org.11212',
		'a..b.c',
	]
)

fn test_package_ids() {
	for id in valid_ids {
		assert android.is_valid_package_id(id)
	}
	for id in invalid_ids {
		assert android.is_valid_package_id(id) == false
	}
}

fn test_upported_target_archs() {
	should_support_archs := ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
	for should_support_arch in should_support_archs {
		assert should_support_arch in android.supported_target_archs
	}
}
