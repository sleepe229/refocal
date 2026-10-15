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
import android.graphics.ColorSpace
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
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Platform services over Pigeon (ADR-0005). No GMS/androidx dependencies (COMP-FDR-007):
 * the system photo picker (ACTION_PICK_IMAGES) where available, else the document picker;
 * images shared to the app (ACTION_SEND, FR-SHARE-001); saving to a user-chosen document.
 */
class RefocalPlatformPlugin :
    FlutterPlugin,
    ActivityAware,
    RefocalPlatformApi,
    PluginRegistry.ActivityResultListener,
    PluginRegistry.RequestPermissionsResultListener,
    PluginRegistry.NewIntentListener {
  private lateinit var context: Context
  private var binding: ActivityPluginBinding? = null
  private var pending: CompletableDeferred<Uri?>? = null
  private var pendingCreate: CompletableDeferred<Uri?>? = null
  private var shared: Uri? = null
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
    b.addOnNewIntentListener(this)
    takeShare(b.activity.intent)
  }

  override fun onDetachedFromActivityForConfigChanges() = onDetachedFromActivity()

  override fun onReattachedToActivityForConfigChanges(b: ActivityPluginBinding) = onAttachedToActivity(b)

  override fun onDetachedFromActivity() {
    binding?.removeActivityResultListener(this)
    binding?.removeRequestPermissionsResultListener(this)
    binding?.removeOnNewIntentListener(this)
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
    val d =
        when (requestCode) {
          REQUEST_PICK -> pending.also { pending = null }
          REQUEST_CREATE -> pendingCreate.also { pendingCreate = null }
          else -> return false
        } ?: return true
    d.complete(if (resultCode == Activity.RESULT_OK) data?.data else null)
    return true
  }

  override fun onNewIntent(intent: Intent): Boolean {
    if (!takeShare(intent)) return false
    main.launch {
      try {
        events?.onSharedImage()
      } catch (_: Exception) {
        // Dart side not ready: it asks for the share when the home screen starts anyway.
      }
    }
    return true
  }

  /** Remembers an image shared with ACTION_SEND; the intent is consumed so a recreated activity does not repeat it. */
  private fun takeShare(intent: Intent?): Boolean {
    if (intent?.action != Intent.ACTION_SEND || intent.type?.startsWith("image/") != true) return false
    val uri =
        if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
        else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM)
    intent.action = null
    shared = uri ?: return false
    return true
  }

  override fun shareFile(path: String, mimeType: String, chooserTitle: String) {
    val activity = binding?.activity ?: throw FlutterError("no_activity", "No foreground activity")
    val uri = ShareProvider.uriFor(context, File(path), mimeType)
    val send =
        Intent(Intent.ACTION_SEND)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    activity.startActivity(Intent.createChooser(send, chooserTitle))
  }

  override suspend fun takeSharedImage(inboxDir: String): PickedImage? {
    val uri = shared ?: return null
    shared = null
    return withContext(Dispatchers.IO) { copyToInbox(uri, File(inboxDir)) }
  }

  override suspend fun saveToFile(path: String, displayName: String, mimeType: String): String? {
    val activity = binding?.activity ?: throw FlutterError("no_activity", "No foreground activity")
    if (pendingCreate != null) throw FlutterError("busy", "A save dialog is already open")
    val deferred = CompletableDeferred<Uri?>()
    pendingCreate = deferred
    activity.startActivityForResult(
        Intent(Intent.ACTION_CREATE_DOCUMENT)
            .addCategory(Intent.CATEGORY_OPENABLE)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_TITLE, displayName),
        REQUEST_CREATE)
    val uri = deferred.await() ?: return null
    withContext(Dispatchers.IO) {
      (context.contentResolver.openOutputStream(uri, "wt") ?: throw IOException("cannot open document")).use { out ->
        File(path).inputStream().use { it.copyTo(out, 1 shl 16) }
      }
    }
    return uri.toString()
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

  override fun startProcessing(texts: ProcessingTexts) = ProcessingService.start(context, texts)

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
    // Random, not a timestamp: several images arrive within the same millisecond (multi-pick).
    val dst = File(inbox, "in-${UUID.randomUUID()}.$ext")
    val tmp = File(inbox, dst.name + ".part")
    try {
      (cr.openInputStream(uri) ?: throw IOException("cannot open selection")).use { input ->
        tmp.outputStream().use { input.copyTo(it, 1 shl 16) }
      }
      if (!tmp.renameTo(dst)) throw IOException("rename failed")
    } finally {
      tmp.delete() // no-op after the rename
    }
    if (Build.VERSION.SDK_INT < 30 && ext == "heic") return heicToPng(dst, name)
    return PickedImage(path = dst.absolutePath, sizeBytes = dst.length(), displayName = name, mimeType = mime)
  }

  /**
   * Android 10 has no AImageDecoder for the core (ADR-0003): decode HEIC here and hand the core a
   * lossless PNG. The size limits of the core (SEC-INP-002) are checked on the header, before the
   * pixels are allocated; colors are converted to sRGB as the core's platform decoder does.
   * EXIF is not carried. Neither the HEIC copy nor a partial PNG is left behind on failure.
   */
  private fun heicToPng(src: File, name: String?): PickedImage {
    val png = File(src.parentFile, src.nameWithoutExtension + ".png")
    val tmp = File(png.path + ".part")
    try {
      val bmp =
          ImageDecoder.decodeBitmap(ImageDecoder.createSource(src)) { d, info, _ ->
            val w = info.size.width.toLong()
            val h = info.size.height.toLong()
            if (w > MAX_SIDE || h > MAX_SIDE || w * h > MAX_PIXELS) {
              throw FlutterError("limit", "Image is larger than ${MAX_SIDE}px per side or 200 MP")
            }
            d.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
            d.setTargetColorSpace(ColorSpace.get(ColorSpace.Named.SRGB))
          }
      try {
        tmp.outputStream().use {
          if (!bmp.compress(Bitmap.CompressFormat.PNG, 100, it)) throw IOException("PNG encode failed")
        }
      } finally {
        bmp.recycle()
      }
      if (!tmp.renameTo(png)) throw IOException("rename failed")
      return PickedImage(path = png.absolutePath, sizeBytes = png.length(), displayName = name, mimeType = "image/png")
    } finally {
      tmp.delete()
      src.delete()
    }
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
    private const val REQUEST_CREATE = 0x5EF2
    // SEC-INP-002, as in the core (native/core/src/image/decode.hpp: kMaxSide, kMaxPixels).
    private const val MAX_SIDE = 30000L
    private const val MAX_PIXELS = 200_000_000L
    private val main = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    @Volatile private var instance: RefocalPlatformPlugin? = null

    /**
     * From [ProcessingService] (notification actions, FGS timeout) to Dart. Without a Dart side
     * nothing can pause or cancel, nor receive the job's events: the service and its
     * notification are removed instead of staying with dead buttons.
     */
    fun dispatchAction(context: Context, action: String) {
      val app = context.applicationContext
      main.launch {
        val events = instance?.events
        val delivered =
            events != null &&
                try {
                  events.onProcessingAction(action)
                  true
                } catch (_: Exception) {
                  false // the Dart side went away meanwhile
                }
        if (!delivered) ProcessingService.stop(app, null, appInForeground = true)
      }
    }
  }
}
