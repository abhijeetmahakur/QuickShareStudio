package com.quickshare.quickshare

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bluetooth: BluetoothBridge? = null
    private var system: SystemBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        bluetooth = BluetoothBridge(applicationContext, messenger).also { it.activity = this }
        system = SystemBridge(applicationContext, messenger).also { it.activity = this }
    }

    @Deprecated("Needed for the Bluetooth enable prompt result")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (bluetooth?.onActivityResult(requestCode, resultCode) == true) return
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        bluetooth?.dispose()
        bluetooth = null
        system = null
        super.onDestroy()
    }
}
