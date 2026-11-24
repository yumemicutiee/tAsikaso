package com.tasikaso.study_app

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        /** Tapping the ringing alert opens the app and stops the alarm. */
        const val ACTION_STOP_ALARM = "com.tasikaso.STOP_ALARM"
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        stopAlarmIfAsked(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        stopAlarmIfAsked(intent)
    }

    private fun stopAlarmIfAsked(intent: Intent?) {
        if (intent?.action == ACTION_STOP_ALARM) TimerAlarm.stop(this)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Opens the phone's notification settings for this app, for a student
        // who once tapped "Don't allow" (Android then never asks again).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasikaso/settings")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openNotificationSettings" -> result.success(openNotificationSettings())
                    else -> result.notImplemented()
                }
            }
        // The timer's alarm, rung by the app itself (TimerAlarm.kt).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "tasikaso/alarm")
            .setMethodCallHandler { call, result ->
                try {
                    when (call.method) {
                        "canSchedule" -> result.success(TimerAlarm.canSchedule(this))
                        "schedule" -> result.success(
                            TimerAlarm.schedule(
                                this,
                                call.argument<Int>("id")!!,
                                (call.argument<Number>("at")!!).toLong(),
                                call.argument<String>("title") ?: "",
                                call.argument<String>("body") ?: "",
                                call.argument<Boolean>("sound") ?: true,
                                call.argument<Boolean>("vibrate") ?: true,
                            ),
                        )
                        "ringNow" -> result.success(
                            TimerAlarm.ringNow(
                                this,
                                call.argument<Int>("id")!!,
                                call.argument<String>("title") ?: "",
                                call.argument<String>("body") ?: "",
                                call.argument<Boolean>("sound") ?: true,
                                call.argument<Boolean>("vibrate") ?: true,
                            ),
                        )
                        "cancel" -> {
                            TimerAlarm.cancel(this, call.argument<Int>("id")!!)
                            result.success(null)
                        }
                        "stop" -> {
                            TimerAlarm.stop(this)
                            result.success(null)
                        }
                        "ringing" -> result.success(TimerAlarmService.ringing)
                        else -> result.notImplemented()
                    }
                } catch (e: Exception) {
                    result.error("alarm", e.message, null)
                }
            }
    }

    private fun openNotificationSettings(): Boolean {
        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS)
                .putExtra(Settings.EXTRA_APP_PACKAGE, packageName)
        } else {
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
        }
        return try {
            startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
            true
        } catch (e: Exception) {
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName"))
                        .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                )
                true
            } catch (e: Exception) {
                false
            }
        }
    }
}
