package org.v.android;

import android.app.NativeActivity;

public class Native extends NativeActivity {
	static { System.loadLibrary("v"); }
}