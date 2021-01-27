package io.v.android;

import android.app.NativeActivity;

/*
import android.support.v7.app.AppCompatActivity;
import android.os.Bundle;
import android.widget.Toast;
*/

public class V extends NativeActivity {
	static { System.loadLibrary("v"); }
}
