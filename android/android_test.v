// Copyright(C) 2019-2022 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
import vab.android

const valid_ids = [
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
const invalid_ids = [
	'_ouch.invalid.package_id',
	'1.invalid.package_id',
	'abc',
	'',
	'a.b.10',
	'your.org.11212',
	'a..b.c',
]

fn test_package_ids() {
	for id in valid_ids {
		android.is_valid_package_id(id) or { assert false }
	}
	for id in invalid_ids {
		android.is_valid_package_id(id) or {
			assert true
			continue
		}
		assert false
	}
}

fn test_supported_target_archs() {
	should_support_archs := ['arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
	for should_support_arch in should_support_archs {
		assert should_support_arch in android.supported_target_archs
	}
}
