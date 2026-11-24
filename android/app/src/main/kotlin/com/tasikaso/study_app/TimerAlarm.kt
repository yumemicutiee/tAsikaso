package com.tasikaso.study_app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.os.VibrationAttributes
import android.os.VibrationEffect
import android.os.Vibrator
import android.os.VibratorManager
import android.provider.Settings
import android.util.Log

/**
 * "When Time Is Up", rung by the app itself, like the phone's Clock app:
 * the end of a Pomodoro or a break is set as an alarm clock alarm
 * ([AlarmManager.setAlarmClock]); when it goes off, [TimerAlarmService]
 * plays the phone's alarm sound on the ALARM volume and vibrates as an
 * ALARM vibration, both on repeat, until the student taps Stop (or the
 * alert). Silent mode, the notification volume and a muted notification
 * channel can't silence it, unlike a notification's own sound.
 *
 * Used when the phone allows exact alarms; otherwise the app falls back to
 * a scheduled notification (lib/services/notification_service_io.dart).
 */
object TimerAlarm {
    private const val TAG = "TimerAlarm"
    const val EXTRA_ID = "id"
    const val EXTRA_TITLE = "title"
    const val EXTRA_BODY = "body"
    const val EXTRA_SOUND = "sound"
    const val EXTRA_VIBRATE = "vibrate"

    fun canSchedule(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        val am = context.getSystemService(AlarmManager::class.java) ?: return false
        return am.canScheduleExactAlarms()
    }

    /** Sets alarm [id] (1 = Pomodoro, 3 = break) for [atMillis]. */
    fun schedule(
        context: Context, id: Int, atMillis: Long, title: String, body: String,
        sound: Boolean, vibrate: Boolean,
    ): Boolean {
        if (!canSchedule(context)) return false
        val am = context.getSystemService(AlarmManager::class.java) ?: return false
        val fire = Intent(context, TimerAlarmReceiver::class.java)
            .setAction("com.tasikaso.TIMER_ALARM.$id")
            .putExtra(EXTRA_ID, id)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_BODY, body)
            .putExtra(EXTRA_SOUND, sound)
            .putExtra(EXTRA_VIBRATE, vibrate)
        val firePi = PendingIntent.getBroadcast(
            context, id, fire,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val show = PendingIntent.getActivity(
            context, 100 + id, Intent(context, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return try {
            am.setAlarmClock(AlarmManager.AlarmClockInfo(atMillis, show), firePi)
            true
        } catch (e: SecurityException) {
            Log.w(TAG, "Exact alarm refused", e)
            false
        }
    }

    /**
     * Rings alarm [id] now: when the timer ends with the app on screen (a
     * foreground app may always start the ringing; no alarm permission is
     * needed). False if Android refused.
     */
    fun ringNow(
        context: Context, id: Int, title: String, body: String,
        sound: Boolean, vibrate: Boolean,
    ): Boolean {
        val ring = Intent(context, TimerAlarmService::class.java)
            .setAction(TimerAlarmService.ACTION_RING)
            .putExtra(EXTRA_ID, id)
            .putExtra(EXTRA_TITLE, title)
            .putExtra(EXTRA_BODY, body)
            .putExtra(EXTRA_SOUND, sound)
            .putExtra(EXTRA_VIBRATE, vibrate)
        return try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(ring)
            } else {
                context.startService(ring)
            }
            true
        } catch (e: Exception) {
            Log.w(TAG, "Couldn't ring now", e)
            false
        }
    }

    /** Takes back alarm [id] if it hasn't gone off yet. */
    fun cancel(context: Context, id: Int) {
        val am = context.getSystemService(AlarmManager::class.java) ?: return
        val fire = Intent(context, TimerAlarmReceiver::class.java)
            .setAction("com.tasikaso.TIMER_ALARM.$id")
        val pi = PendingIntent.getBroadcast(
            context, id, fire,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        am.cancel(pi)
        pi.cancel()
    }

    /** Stops the alarm that is ringing, if any. */
    fun stop(context: Context) {
        if (!TimerAlarmService.ringing) return
        context.startService(
            Intent(context, TimerAlarmService::class.java).setAction(TimerAlarmService.ACTION_STOP),
        )
    }
}

/** Woken by the alarm clock alarm: starts the ringing. */
class TimerAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val ring = Intent(context, TimerAlarmService::class.java)
            .setAction(TimerAlarmService.ACTION_RING)
            .putExtras(intent)
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(ring)
            } else {
                context.startService(ring)
            }
        } catch (e: Exception) {
            Log.e("TimerAlarm", "Could not start the alarm", e)
        }
    }
}

/** Rings and vibrates until Stop, with a notification that has Stop. */
class TimerAlarmService : Service() {
    companion object {
        const val ACTION_RING = "com.tasikaso.TIMER_ALARM_RING"
        const val ACTION_STOP = "com.tasikaso.TIMER_ALARM_STOP"
        const val CHANNEL = "timer_ringing"
        private const val TAG = "TimerAlarm"

        @Volatile
        var ringing = false
            private set

        private val buzz = longArrayOf(0, 600, 300, 600, 300, 600, 1200)
    }

    private var player: MediaPlayer? = null
    private var vibrator: Vibrator? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var notificationId = 0

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_RING) {
            ring(intent)
        } else {
            stopRinging()
        }
        return START_NOT_STICKY
    }

    private fun ring(intent: Intent) {
        stopSound()
        val id = intent.getIntExtra(TimerAlarm.EXTRA_ID, 1)
        val title = intent.getStringExtra(TimerAlarm.EXTRA_TITLE) ?: "Time is up"
        val body = intent.getStringExtra(TimerAlarm.EXTRA_BODY) ?: ""
        val sound = intent.getBooleanExtra(TimerAlarm.EXTRA_SOUND, true)
        val vibrate = intent.getBooleanExtra(TimerAlarm.EXTRA_VIBRATE, true)

        val notification = buildNotification(id, title, body)
        if (notificationId != 0 && notificationId != id) {
            getSystemService(NotificationManager::class.java)?.cancel(notificationId)
        }
        notificationId = id
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK)
            } else {
                startForeground(id, notification)
            }
        } catch (e: Exception) {
            // Not allowed to run in the foreground: show the alert at least,
            // and still ring while the app's process is alive.
            Log.e(TAG, "Foreground refused", e)
            getSystemService(NotificationManager::class.java)?.notify(id, notification)
        }
        ringing = true
        acquireWakeLock()
        if (sound) playSound()
        if (vibrate) startVibration()
    }

    private fun buildNotification(id: Int, title: String, body: String): Notification {
        val nm = getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && nm?.getNotificationChannel(CHANNEL) == null) {
            // Silent channel: the app plays the alarm itself.
            val channel = NotificationChannel(CHANNEL, "Timer: ringing", NotificationManager.IMPORTANCE_HIGH).apply {
                description = "When a Pomodoro or a break ends (the alarm and vibration are played by the app)"
                setSound(null, null)
                enableVibration(false)
                setBypassDnd(true)
                lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            }
            nm?.createNotificationChannel(channel)
        }
        val stop = PendingIntent.getService(
            this, 200 + id, Intent(this, TimerAlarmService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val open = PendingIntent.getActivity(
            this, 300 + id,
            Intent(this, MainActivity::class.java).setAction(MainActivity.ACTION_STOP_ALARM),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this).setPriority(Notification.PRIORITY_MAX)
        }
        return builder
            .setSmallIcon(R.drawable.ic_stat_notify)
            .setContentTitle(title)
            .setContentText(body)
            .setCategory(Notification.CATEGORY_ALARM)
            .setVisibility(Notification.VISIBILITY_PUBLIC)
            .setOngoing(true)
            .setAutoCancel(false)
            .setContentIntent(open)
            .setDeleteIntent(stop)
            .addAction(Notification.Action.Builder(null, "Stop", stop).build())
            .build()
    }

    private fun alarmUris(): List<Uri> = listOfNotNull(
        RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_ALARM),
        Settings.System.DEFAULT_ALARM_ALERT_URI,
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
        RingtoneManager.getActualDefaultRingtoneUri(this, RingtoneManager.TYPE_RINGTONE),
        RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
    )

    private fun playSound() {
        val attributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .build()
        for (uri in alarmUris()) {
            try {
                val p = MediaPlayer()
                p.setAudioAttributes(attributes)
                p.setDataSource(this, uri)
                p.isLooping = true
                p.prepare()
                p.start()
                player = p
                return
            } catch (e: Exception) {
                Log.w(TAG, "Alarm sound $uri didn't play", e)
            }
        }
    }

    private fun startVibration() {
        val v = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            getSystemService(VibratorManager::class.java)?.defaultVibrator
        } else {
            @Suppress("DEPRECATION")
            getSystemService(VIBRATOR_SERVICE) as? Vibrator
        } ?: return
        if (!v.hasVibrator()) return
        vibrator = v
        try {
            when {
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU -> v.vibrate(
                    VibrationEffect.createWaveform(buzz, 0),
                    VibrationAttributes.createForUsage(VibrationAttributes.USAGE_ALARM),
                )
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O -> {
                    @Suppress("DEPRECATION")
                    v.vibrate(
                        VibrationEffect.createWaveform(buzz, 0),
                        AudioAttributes.Builder().setUsage(AudioAttributes.USAGE_ALARM).build(),
                    )
                }
                else -> {
                    @Suppress("DEPRECATION")
                    v.vibrate(buzz, 0)
                }
            }
        } catch (e: Exception) {
            Log.w(TAG, "Vibration refused", e)
        }
    }

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        wakeLock = getSystemService(PowerManager::class.java)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "tAsikaso:timerAlarm")
            ?.apply { acquire(60 * 60 * 1000L) }
    }

    private fun stopSound() {
        try {
            player?.stop()
        } catch (_: Exception) {
        }
        player?.release()
        player = null
        vibrator?.cancel()
        vibrator = null
    }

    private fun stopRinging() {
        stopSound()
        ringing = false
        if (wakeLock?.isHeld == true) wakeLock?.release()
        wakeLock = null
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        if (notificationId != 0) {
            getSystemService(NotificationManager::class.java)?.cancel(notificationId)
        }
        notificationId = 0
        stopSelf()
    }

    override fun onDestroy() {
        stopSound()
        ringing = false
        if (wakeLock?.isHeld == true) wakeLock?.release()
        super.onDestroy()
    }
}
