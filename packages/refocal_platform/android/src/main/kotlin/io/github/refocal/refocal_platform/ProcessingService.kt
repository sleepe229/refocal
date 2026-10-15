// SPDX-License-Identifier: Apache-2.0
package io.github.refocal.refocal_platform

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Foreground service that keeps the process at foreground priority while a photo is processed
 * with the app in the background (ADR-0019, FR-BATCH-004). The work itself runs in the native
 * core inside this process; the service only holds the notification (progress, Pause, Cancel).
 *
 * Type: mediaProcessing on Android 15+, dataSync on 10-14 (mediaProcessing does not exist
 * there). On the Android 15 time limit, onTimeout asks Dart to pause (checkpoint) and leaves a
 * "Continue" notification.
 */
class ProcessingService : Service() {
  /** The texts of the current run, from the start intent; null until it arrives. */
  private var texts: ProcessingTexts? = null

  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_PAUSE, ACTION_CANCEL -> {
        RefocalPlatformPlugin.dispatchAction(this, if (intent.action == ACTION_PAUSE) "pause" else "cancel")
        stopIfIdle(startId)
      }
      ACTION_UPDATE -> {
        notifyProgress(intent.getStringExtra(EXTRA_TEXT) ?: "", intent.getIntExtra(EXTRA_PERCENT, -1))
        stopIfIdle(startId)
      }
      ACTION_START -> {
        val t = textsOf(intent)
        texts = t
        ensureChannel(this, t)
        val n = buildNotification(t, "", -1)
        if (Build.VERSION.SDK_INT >= 35) {
          startForeground(ID_PROGRESS, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROCESSING)
        } else {
          startForeground(ID_PROGRESS, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC)
        }
      }
    }
    // Not sticky: after a kill the job is continued from its checkpoint by the user (FR-BATCH-007).
    return START_NOT_STICKY
  }

  override fun onTimeout(startId: Int, fgsType: Int) {
    RefocalPlatformPlugin.dispatchAction(this, "timeout")
    texts?.let { postFinished(this, it.timedOut) }
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  override fun onTimeout(startId: Int) = onTimeout(startId, 0)

  /**
   * A tap or update that reached a stopped service (it raced a stop, or the process was
   * restarted for it) would otherwise leave a plain background service behind.
   */
  private fun stopIfIdle(startId: Int) {
    if (texts == null) stopSelf(startId)
  }

  private fun notifyProgress(text: String, percent: Int) {
    val t = texts ?: return
    getSystemService(NotificationManager::class.java)?.notify(ID_PROGRESS, buildNotification(t, text, percent))
  }

  private fun buildNotification(t: ProcessingTexts, text: String, percent: Int): Notification {
    val b = Notification.Builder(this, CHANNEL)
        .setSmallIcon(R.drawable.ic_stat_refocal)
        .setContentTitle(t.title)
        .setContentText(text)
        .setOngoing(true)
        .setOnlyAlertOnce(true)
        .setContentIntent(openApp(this))
        .setProgress(100, percent.coerceIn(0, 100), percent < 0)
        .addAction(Notification.Action.Builder(null, t.pause, action(ACTION_PAUSE, 1)).build())
        .addAction(Notification.Action.Builder(null, t.cancel, action(ACTION_CANCEL, 2)).build())
    if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
    return b.build()
  }

  private fun action(action: String, code: Int): PendingIntent =
      PendingIntent.getService(
          this, code, Intent(this, ProcessingService::class.java).setAction(action), PendingIntent.FLAG_IMMUTABLE)

  companion object {
    private const val CHANNEL = "processing"
    private const val ID_PROGRESS = 1
    private const val ID_FINISHED = 2
    private const val ACTION_START = "io.github.refocal.START"
    private const val ACTION_UPDATE = "io.github.refocal.UPDATE"
    private const val ACTION_PAUSE = "io.github.refocal.PAUSE"
    private const val ACTION_CANCEL = "io.github.refocal.CANCEL"
    private const val EXTRA_TEXT = "text"
    private const val EXTRA_PERCENT = "percent"
    private val TEXT_KEYS = listOf("title", "pause", "cancel", "timedOut", "channelName", "channelDescription")

    /** Must be called while the app is in the foreground (a user action, ADR-0019). */
    fun start(context: Context, t: ProcessingTexts) {
      context.getSystemService(NotificationManager::class.java)?.cancel(ID_FINISHED)
      val values = listOf(t.title, t.pause, t.cancel, t.timedOut, t.channelName, t.channelDescription)
      val intent = Intent(context, ProcessingService::class.java).setAction(ACTION_START)
      TEXT_KEYS.zip(values).forEach { (k, v) -> intent.putExtra(k, v) }
      context.startForegroundService(intent)
    }

    /** Allowed from the background: the running foreground service keeps the app foreground. */
    fun update(context: Context, text: String, percent: Int) {
      context.startService(
          Intent(context, ProcessingService::class.java)
              .setAction(ACTION_UPDATE)
              .putExtra(EXTRA_TEXT, text)
              .putExtra(EXTRA_PERCENT, percent))
    }

    fun stop(context: Context, finishedText: String?, appInForeground: Boolean) {
      context.stopService(Intent(context, ProcessingService::class.java))
      context.getSystemService(NotificationManager::class.java)?.cancel(ID_PROGRESS)
      if (finishedText != null && !appInForeground) postFinished(context, finishedText)
    }

    private fun textsOf(i: Intent): ProcessingTexts {
      val v = TEXT_KEYS.map { i.getStringExtra(it) ?: "" }
      return ProcessingTexts(v[0], v[1], v[2], v[3], v[4], v[5])
    }

    /** Creates the channel, or renames it after a language change (same call, same id). */
    private fun ensureChannel(context: Context, t: ProcessingTexts) {
      context.getSystemService(NotificationManager::class.java)?.createNotificationChannel(
          NotificationChannel(CHANNEL, t.channelName, NotificationManager.IMPORTANCE_LOW).apply {
            description = t.channelDescription
          })
    }

    private fun openApp(context: Context): PendingIntent? {
      val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
      launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
      return PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE)
    }

    /** On the channel the start created (a finished text only follows a start). */
    private fun postFinished(context: Context, text: String) {
      val n = Notification.Builder(context, CHANNEL)
          .setSmallIcon(R.drawable.ic_stat_refocal)
          .setContentTitle(context.applicationInfo.loadLabel(context.packageManager))
          .setContentText(text)
          .setStyle(Notification.BigTextStyle().bigText(text))
          .setAutoCancel(true)
          .setContentIntent(openApp(context))
          .build()
      context.getSystemService(NotificationManager::class.java)?.notify(ID_FINISHED, n)
    }
  }
}
