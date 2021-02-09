package io.v.android;

import android.app.NativeActivity;

public class VActivity extends NativeActivity {
	static { System.loadLibrary("v"); }
	private static VActivity thiz;
	// Set instance reference
	public VActivity() { thiz = this; }
	private static VActivity getVActivity() {
		return thiz;
	}
}
