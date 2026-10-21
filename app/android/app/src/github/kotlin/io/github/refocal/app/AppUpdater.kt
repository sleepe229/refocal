package io.github.refocal.app

import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.Build
import android.provider.Settings
import io.github.refocal.refocal_platform.AppUpdateApi
import io.github.refocal.refocal_platform.FlutterError
import java.io.File
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

/**
 * Installs a downloaded, already verified APK over this app (ADR-0027). Android checks that it
 * is signed with the same key; Dart checked its size and SHA-256 against the signed
 * app-update.json before calling [install].
 */
class AppUpdater(context: Context) : AppUpdateApi {
  private val app = context.applicationContext

  override fun installedVersionCode(): Long =
      app.packageManager.getPackageInfo(app.packageName, 0).longVersionCode

  override fun sdkInt(): Long = Build.VERSION.SDK_INT.toLong()

  override fun unmetered(): Boolean {
    val cm = app.getSystemService(ConnectivityManager::class.java)
    val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
    return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_NOT_METERED)
  }

  override fun canInstall(): Boolean = app.packageManager.canRequestPackageInstalls()

  override fun openInstallSettings() {
    app.startActivity(
        Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES, Uri.parse("package:${app.packageName}"))
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
  }

  override suspend fun install(apkPath: String): String {
    val apk = File(apkPath)
    val installer = app.packageManager.packageInstaller
    val params =
        PackageInstaller.SessionParams(PackageInstaller.SessionParams.MODE_FULL_INSTALL).apply {
          setAppPackageName(app.packageName)
          setSize(apk.length())
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setRequireUserAction(PackageInstaller.SessionParams.USER_ACTION_NOT_REQUIRED)
          }
          if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            setRequestUpdateOwnership(true)
          }
        }
    val result = CompletableDeferred<String>()
    pending = result
    withContext(Dispatchers.IO) {
      val id = installer.createSession(params)
      try {
        installer.openSession(id).use { session ->
          session.openWrite("base.apk", 0, apk.length()).use { out ->
            apk.inputStream().use { it.copyTo(out) }
            session.fsync(out)
          }
          val intent = Intent(app, InstallResultReceiver::class.java)
          // Mutable: the installer adds the status extras to it.
          val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE
          session.commit(PendingIntent.getBroadcast(app, id, intent, flags).intentSender)
        }
      } catch (e: Exception) {
        installer.abandonSession(id)
        throw FlutterError("install", e.message ?: e.javaClass.simpleName)
      }
    }
    return result.await()
  }

  internal companion object {
    /** The install waiting for its result; one at a time. */
    @Volatile var pending: CompletableDeferred<String>? = null
  }
}

/** The PackageInstaller session's status (the app is still running unless it succeeded). */
class InstallResultReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val status = intent.getIntExtra(PackageInstaller.EXTRA_STATUS, PackageInstaller.STATUS_FAILURE)
    val pending = AppUpdater.pending
    when (status) {
      PackageInstaller.STATUS_PENDING_USER_ACTION -> {
        // First update after an install from the browser: Android's own dialog.
        @Suppress("DEPRECATION")
        val confirm = intent.getParcelableExtra<Intent>(Intent.EXTRA_INTENT)
        confirm?.let { context.startActivity(it.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        pending?.complete("pending_user")
      }
      PackageInstaller.STATUS_SUCCESS -> pending?.complete("success")
      else -> {
        val message = intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE) ?: "status $status"
        pending?.completeExceptionally(FlutterError("install", message))
      }
    }
  }
}
