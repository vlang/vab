package org.v.vtest;

import android.app.NativeActivity;

public class Native extends NativeActivity {
	static { System.loadLibrary("vtest"); }
}