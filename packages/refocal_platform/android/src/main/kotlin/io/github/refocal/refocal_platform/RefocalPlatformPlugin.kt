// SPDX-License-Identifier: Apache-2.0
package io.github.refocal.refocal_platform

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.graphics.Bitmap
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.OpenableColumns
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.IOException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Platform services over Pigeon (ADR-0005). No GMS/androidx dependencies (COMP-FDR-007):
 * the system photo picker (ACTION_PICK_IMAGES) where available, else the document picker.
 */
class RefocalPlatformPlugin :
    FlutterPlugin,
    ActivityAware,
    RefocalPlatformApi,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener {
  private lateinit var context: Context
  private var binding: ActivityPluginBinding? = null
  private var pending: CompletableDeferred<Uri?>? = null
  private var pendingPermission: CompletableDeferred<Boolean>? = null
  private var events: RefocalPlatformEvents? = null

  override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
    context = b.applicationContext
    RefocalPlatformApi.setUp(b.binaryMessenger, this)
    events = RefocalPlatformEvents(b.binaryMessenger)
    instance = this
  }

  override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
    RefocalPlatformApi.setUp(b.binaryMessenger, null)
    events = null
    if (instance === this) instance = null
  }

  override fun onAttachedToActivity(b: ActivityPluginBinding) {
    binding = b
    b.addActivityResultListener(this)
    b.addRequestPermissionsResultListener(this)
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)

  override fun onDetachedFromActivity() {
    binding?.removeActivityResultListener(this)
    binding?.removeRequestPermissionsResultListener(this)
    binding = null
  }

  override fun getDirs(): AppDirs =
      AppDirs(support = context.noBackupFilesDir.absolutePath, cache = context.cacheDir.absolutePath)

  override fun lastExitReason(): String? {
    if (Build.VERSION.SDK_INT < 30) return null
    val am = context.getSystemService(ActivityManager::class.java) ?: return null
    val info = am.getHistoricalProcessExitReasons(context.packageName, 0, 1).firstOrNull() ?: return null
    return when (info.reason) {
      ApplicationExitInfo.REASON_CRASH_NATIVE, ApplicationExitInfo.REASON_ANR -> "native_crash"
      ApplicationExitInfo.REASON_LOW_MEMORY,
      ApplicationExitInfo.REASON_USER_REQUESTED,
      ApplicationExitInfo.REASON_USER_STOPPED,
      ApplicationExitInfo.REASON_EXIT_SELF,
      ApplicationExitInfo.REASON_SIGNALED -> "os_kill"
      else -> null
    }
  }

  override suspend fun pickImage(inboxDir: String): PickedImage? {
    val activity = binding?.activity ?: throw FlutterError("no_activity", "No foreground activity")
    if (pending != null) throw FlutterError("busy", "A picker is already open")
    val deferred = CompletableDeferred<Uri?>()
    pending = deferred
    activity.startActivityForResult(pickerIntent(), REQUEST_PICK)
    val uri = deferred.await() ?: return null
    return withContext(Dispatchers.IO) { copyToInbox(uri, File(inboxDir)) }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    if (requestCode != REQUEST_PICK) return false
    val d = pending ?: return true
    pending = null
    d.complete(if (resultCode == Activity.RESULT_OK) data?.data else null)
    return true
  }

  private fun pickerIntent(): Intent {
    val hasPhotoPicker =
        Build.VERSION.SDK_INT >= 33 ||
            (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)
    return if (hasPhotoPicker) {
      Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*")
    } else {
      Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("image/*")
    }
  }

  override suspend fun requestNotificationPermission(): Boolean {
    if (Build.VERSION.SDK_INT < 33) return true
    if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED) {
      return true
    }
    val activity = binding?.activity ?: return false
    if (pendingPermission != null) return false
    val d = CompletableDeferred<Boolean>()
    pendingPermission = d
    activity.requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), REQUEST_NOTIFICATIONS)
    return d.await()
  }

  override fun onRequestPermissionsResult(code: Int, permissions: Array<out String>, results: IntArray): Boolean {
    if (code != REQUEST_NOTIFICATIONS) return false
    val d = pendingPermission ?: return true
    pendingPermission = null
    d.complete(results.isNotEmpty() && results[0] == PackageManager.PERMISSION_GRANTED)
    return true
  }

  override fun startProcessing(title: String) = ProcessingService.start(context, title)

  override fun updateProcessing(text: String, percent: Long) =
      ProcessingService.update(context, text, percent.toInt())

  override fun stopProcessing(finishedText: String?) {
    val state = ActivityManager.RunningAppProcessInfo()
    ActivityManager.getMyMemoryState(state)
    val foreground = state.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND
    ProcessingService.stop(context, finishedText, foreground)
  }

  private fun copyToInbox(uri: Uri, inbox: File): PickedImage {
    val cr = context.contentResolver
    var name: String? = null
    cr.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
      if (c.moveToFirst()) name = c.getString(0)
    }
    val mime = cr.getType(uri)
    if (!inbox.isDirectory && !inbox.mkdirs()) throw IOException("cannot create inbox")
    val ext = when (mime) {
      "image/jpeg" -> "jpg"
      "image/png" -> "png"
      "image/heic", "image/heif" -> "heic"
      "image/webp" -> "webp"
      "image/avif" -> "avif"
      else -> "img"
    }
    val dst = File(inbox, "in-${System.currentTimeMillis()}.$ext")
    val tmp = File(inbox, dst.name + ".part")
    (cr.openInputStream(uri) ?: throw IOException("cannot open selection")).use { input ->
      tmp.outputStream().use { input.copyTo(it, 1 shl 16) }
    }
    if (!tmp.renameTo(dst)) throw IOException("rename failed")
    if (Build.VERSION.SDK_INT < 30 && ext == "heic") return heicToPng(dst, name)
    return PickedImage(path = dst.absolutePath, sizeBytes = dst.length(), displayName = name, mimeType = mime)
  }

  /**
   * Android 10 has no AImageDecoder for the core (ADR-0003): decode HEIC here (orientation and
   * color handled by the platform) and hand the core a lossless PNG. EXIF is not carried.
   */
  private fun heicToPng(src: File, name: String?): PickedImage {
    val bmp = ImageDecoder.decodeBitmap(ImageDecoder.createSource(src)) { d, _, _ ->
      d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
    }
    val png = File(src.parentFile, src.nameWithoutExtension + ".png")
    val tmp = File(png.path + ".part")
    try {
      tmp.outputStream().use { if (!bmp.compress(Bitmap.CompressFormat.PNG, 100, it)) throw IOException("PNG encode failed") }
    } finally {
      bmp.recycle()
    }
    if (!tmp.renameTo(png)) throw IOException("rename failed")
    src.delete()
    return PickedImage(path = png.absolutePath, sizeBytes = png.length(), displayName = name, mimeType = "image/png")
  }

  override suspend fun saveToGallery(path: String, displayName: String, mimeType: String): String =
      withContext(Dispatchers.IO) {
        val cr = context.contentResolver
        val values =
            ContentValues().apply {
              put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
              put(MediaStore.Images.Media.MIME_TYPE, mimeType)
              put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/Refocal")
              put(MediaStore.Images.Media.IS_PENDING, 1)
            }
        val collection = MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
        val uri = cr.insert(collection, values) ?: throw IOException("MediaStore insert failed")
        try {
          (cr.openOutputStream(uri) ?: throw IOException("cannot open gallery item")).use { out ->
            File(path).inputStream().use { it.copyTo(out, 1 shl 16) }
          }
          values.clear()
          values.put(MediaStore.Images.Media.IS_PENDING, 0)
          cr.update(uri, values, null, null)
        } catch (e: Exception) {
          cr.delete(uri, null, null)
          throw e
        }
        uri.toString()
      }

  companion object {
    private const val REQUEST_PICK = 0x5EF0
    private const val REQUEST_NOTIFICATIONS = 0x5EF1
    private val main = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    @Volatile private var instance: RefocalPlatformPlugin? = null

    /** From [ProcessingService] (notification actions, FGS timeout) to Dart. */
    fun dispatchAction(action: String) {
      main.launch {
        try {
          instance?.events?.onProcessingAction(action)
        } catch (_: Exception) {
          // Dart side gone: nothing is running to pause or cancel.
        }
      }
    }
  }
}
