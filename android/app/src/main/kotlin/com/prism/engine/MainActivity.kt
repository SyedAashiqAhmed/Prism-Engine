package com.prism.engine

import android.content.ComponentName
import android.content.Intent
import android.provider.Settings
import android.text.TextUtils
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            NOTIFICATION_ACCESS_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "hasPermission" -> result.success(hasListenerPermission())
                "openSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                    )
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun hasListenerPermission(): Boolean {
        val enabledListeners = Settings.Secure.getString(
            contentResolver,
            "enabled_notification_listeners",
        ) ?: return false
        val target = ComponentName(
            this,
            PrismNotificationListenerService::class.java,
        )
        return enabledListeners.split(':').any { flattened ->
            val component = ComponentName.unflattenFromString(flattened)
            TextUtils.equals(target.packageName, component?.packageName) &&
                TextUtils.equals(target.className, component?.className)
        }
    }

    companion object {
        private const val NOTIFICATION_ACCESS_CHANNEL =
            "com.prism.engine/notification_access"
    }
}
