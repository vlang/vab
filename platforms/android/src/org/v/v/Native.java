package org.v.v;

import android.app.NativeActivity;

public class Native extends NativeActivity {
	static { System.loadLibrary("v"); }
}