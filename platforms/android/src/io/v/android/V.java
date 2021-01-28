package io.v.android;

import android.app.NativeActivity;

public class V extends NativeActivity {
	static { System.loadLibrary("v"); }
}
