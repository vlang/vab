// Copyright(C) 2019-2020 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
import android

fn test_package_ids() {
	valid_ids := [
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
		'your.1.org.11212e'
	]
	invalid_ids := [
		'1.valid.package_id',
		'abc',
		'',
		'a.b.10',
		'your.org.11212',
		'a..b.c'
	]
	for id in valid_ids {
		assert android.is_valid_package_id(id)
	}
	for id in invalid_ids {
		assert android.is_valid_package_id(id) == false
	}
}
