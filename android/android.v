// Copyright(C) 2019-2024 Lars Pontoppidan. All rights reserved.
// Use of this source code is governed by an MIT license file distributed with this software package
module android

pub const default_app_name = $d('vab:default_app_name', 'V Test App')
pub const default_package_id = $d('vab:default_package_id', 'io.v.android')
pub const default_activity_name = $d('vab:default_activity_name', 'VActivity')
pub const default_package_format = $d('vab:default_package_format', 'apk')
pub const default_min_sdk_version = int($d('vab:default_min_sdk_version', 21))
pub const default_base_files_path = get_default_base_files_path()
pub const supported_package_formats = ['apk', 'aab']
pub const supported_lib_folders = ['armeabi', 'arm64-v8a', 'armeabi-v7a', 'x86', 'x86_64']
pub const mipmap_icon_sizes = [192, 144, 96, 72, 48]! // xxxhdpi, xxhdpi, xhdpi, hdpi, mdpi

pub type OptionTypes = CompileOptions | PackageOptions | DeployOptions
