package com.moneytrack.moneytrack

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterFragmentActivity
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterFragmentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
    }
    override fun onPause() {
        window.decorView.foreground = android.graphics.drawable.ColorDrawable(android.graphics.Color.BLACK)
        super.onPause()
    }
    private var documents: DocumentBridge? = null
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: android.content.Intent?) {
        if (documents?.onResult(requestCode, resultCode, data) != true) super.onActivityResult(requestCode, resultCode, data)
    }
    private var permissionResult: MethodChannel.Result? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        SecurityBridge(this).register(flutterEngine.dartExecutor.binaryMessenger)
        documents = DocumentBridge(this).also { it.register(flutterEngine.dartExecutor.binaryMessenger) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "moneytrack/reminders").setMethodCallHandler { call, result ->
            when (call.method) {
                "allowed" -> result.success(LocalReminders.allowed(this))
                "request" -> {
                    if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        if (permissionResult != null) result.error("BUSY", "Permission request already in progress", null)
                        else { permissionResult = result; requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 3103) }
                    } else result.success(LocalReminders.allowed(this))
                }
                "replace" -> {
                    try {
                        val items = JSONArray()
                        (call.arguments as? List<*>)?.forEach { items.put(JSONObject(it as Map<*, *>)) }
                        LocalReminders.replace(this, items)
                        result.success(true)
                    } catch (e: Exception) { result.error("REMINDER", "Could not schedule local reminders", null) }
                }
                else -> result.notImplemented()
            }
        }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 3103) { permissionResult?.success(LocalReminders.allowed(this)); permissionResult = null }
    }
}
