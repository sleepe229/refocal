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
  override fun onBind(intent: Intent?): IBinder? = null

  override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
    when (intent?.action) {
      ACTION_PAUSE -> RefocalPlatformPlugin.dispatchAction("pause")
      ACTION_CANCEL -> RefocalPlatformPlugin.dispatchAction("cancel")
      else -> {
        val n = buildNotification(this, intent?.getStringExtra(EXTRA_TITLE) ?: "", "", -1)
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
    RefocalPlatformPlugin.dispatchAction("timeout")
    postFinished(this, "Paused: Android's time limit for background work was reached. Tap to continue.")
    stopForeground(STOP_FOREGROUND_REMOVE)
    stopSelf()
  }

  override fun onTimeout(startId: Int) = onTimeout(startId, 0)

  companion object {
    private const val CHANNEL = "processing"
    private const val ID_PROGRESS = 1
    private const val ID_FINISHED = 2
    private const val ACTION_PAUSE = "io.github.refocal.PAUSE"
    private const val ACTION_CANCEL = "io.github.refocal.CANCEL"
    private const val EXTRA_TITLE = "title"

    @Volatile private var title = ""

    fun start(context: Context, t: String) {
      title = t
      context.getSystemService(NotificationManager::class.java)?.cancel(ID_FINISHED)
      context.startForegroundService(
          Intent(context, ProcessingService::class.java).putExtra(EXTRA_TITLE, t))
    }

    fun update(context: Context, text: String, percent: Int) {
      val nm = context.getSystemService(NotificationManager::class.java) ?: return
      nm.notify(ID_PROGRESS, buildNotification(context, title, text, percent))
    }

    fun stop(context: Context, finishedText: String?, appInForeground: Boolean) {
      context.stopService(Intent(context, ProcessingService::class.java))
      context.getSystemService(NotificationManager::class.java)?.cancel(ID_PROGRESS)
      if (finishedText != null && !appInForeground) postFinished(context, finishedText)
    }

    private fun ensureChannel(context: Context) {
      val nm = context.getSystemService(NotificationManager::class.java) ?: return
      if (nm.getNotificationChannel(CHANNEL) == null) {
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Processing", NotificationManager.IMPORTANCE_LOW).apply {
              description = "Progress of photos being enhanced"
            })
      }
    }

    private fun openApp(context: Context): PendingIntent? {
      val launch = context.packageManager.getLaunchIntentForPackage(context.packageName) ?: return null
      launch.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)
      return PendingIntent.getActivity(context, 0, launch, PendingIntent.FLAG_IMMUTABLE)
    }

    private fun action(context: Context, action: String, code: Int): PendingIntent =
        PendingIntent.getService(
            context, code, Intent(context, ProcessingService::class.java).setAction(action),
            PendingIntent.FLAG_IMMUTABLE)

    private fun buildNotification(context: Context, title: String, text: String, percent: Int): Notification {
      ensureChannel(context)
      val b = Notification.Builder(context, CHANNEL)
          .setSmallIcon(R.drawable.ic_stat_refocal)
          .setContentTitle(title)
          .setContentText(text)
          .setOngoing(true)
          .setOnlyAlertOnce(true)
          .setContentIntent(openApp(context))
          .setProgress(100, percent.coerceIn(0, 100), percent < 0)
          .addAction(Notification.Action.Builder(null, "Pause", action(context, ACTION_PAUSE, 1)).build())
          .addAction(Notification.Action.Builder(null, "Cancel", action(context, ACTION_CANCEL, 2)).build())
      if (Build.VERSION.SDK_INT >= 31) b.setForegroundServiceBehavior(Notification.FOREGROUND_SERVICE_IMMEDIATE)
      return b.build()
    }

    private fun postFinished(context: Context, text: String) {
      ensureChannel(context)
      val n = Notification.Builder(context, CHANNEL)
          .setSmallIcon(R.drawable.ic_stat_refocal)
          .setContentTitle("Refocal")
          .setContentText(text)
          .setStyle(Notification.BigTextStyle().bigText(text))
          .setAutoCancel(true)
          .setContentIntent(openApp(context))
          .build()
      context.getSystemService(NotificationManager::class.java)?.notify(ID_FINISHED, n)
    }
  }
}
