// SPDX-License-Identifier: Apache-2.0
package io.github.refocal.refocal_platform

import android.Manifest
import android.app.Activity
import android.app.ActivityManager
import android.app.ApplicationExitInfo
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ComponentCallbacks2
import android.content.ContentResolver
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.ImageDecoder
import android.media.MediaCodecList
import android.media.MediaFormat
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.os.ext.SdkExtensions
import android.provider.MediaStore
import android.provider.OpenableColumns
import androidx.heifwriter.HeifWriter
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.PluginRegistry
import java.io.File
import java.io.IOException
import java.io.RandomAccessFile
import java.nio.channels.FileChannel
import java.security.DigestInputStream
import java.security.MessageDigest
import java.util.UUID
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/**
 * Platform services over Pigeon (ADR-0005). No GMS (COMP-FDR-007); the only androidx library is
 * heifwriter (HEIC output, ADR-0003):
 * the system photo picker (ACTION_PICK_IMAGES) where available, else the document picker;
 * images shared to the app (ACTION_SEND/SEND_MULTIPLE, FR-SHARE-001); saving to a user-chosen
 * document.
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
  private var pending: CompletableDeferred<List<Uri>>? = null
  private var pendingCreate: CompletableDeferred<Uri?>? = null
  private var pendingOpen: CompletableDeferred<Uri?>? = null
  private var shared: List<Uri> = emptyList()
  private var pendingPermission: CompletableDeferred<Boolean>? = null
  private var events: RefocalPlatformEvents? = null

  override fun onAttachedToEngine(b: FlutterPlugin.FlutterPluginBinding) {
    context = b.applicationContext
    RefocalPlatformApi.setUp(b.binaryMessenger, this)
    events = RefocalPlatformEvents(b.binaryMessenger)
    instance = this
    context.getSystemService(PowerManager::class.java)?.addThermalStatusListener(context.mainExecutor, thermalListener)
    context.registerComponentCallbacks(memoryCallbacks)
  }

  override fun onDetachedFromEngine(b: FlutterPlugin.FlutterPluginBinding) {
    context.getSystemService(PowerManager::class.java)?.removeThermalStatusListener(thermalListener)
    context.unregisterComponentCallbacks(memoryCallbacks)
    RefocalPlatformApi.setUp(b.binaryMessenger, null)
    events = null
    if (instance === this) instance = null
  }

  override fun deviceInfo(): DeviceInfo {
    val mem = ActivityManager.MemoryInfo()
    context.getSystemService(ActivityManager::class.java)?.getMemoryInfo(mem)
    val soc = if (Build.VERSION.SDK_INT >= 31) Build.SOC_MODEL.takeUnless { it == Build.UNKNOWN } else null
    return DeviceInfo(totalRamBytes = mem.totalMem, osBuild = Build.FINGERPRINT, soc = soc ?: Build.HARDWARE)
  }

  override fun heicSupported(): Boolean =
      MediaCodecList(MediaCodecList.REGULAR_CODECS).codecInfos.any { info ->
        info.isEncoder && info.supportedTypes.any {
          it.equals(MediaFormat.MIMETYPE_IMAGE_ANDROID_HEIC, true) || it.equals(MediaFormat.MIMETYPE_VIDEO_HEVC, true)
        }
      }

  /**
   * FR-EXP-002: the core's raw RGBA (alpha 255) is mapped, not read into the Java heap, and copied
   * into one ARGB_8888 bitmap (<= 50 MP: 200 MB of native memory); HeifWriter tiles it into a grid.
   */
  override suspend fun encodeHeic(rgbaPath: String, width: Long, height: Long, quality: Long, dstPath: String) =
      withContext(Dispatchers.Default) {
        val w = width.toInt()
        val h = height.toInt()
        val bitmap =
            try {
              Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
            } catch (e: OutOfMemoryError) {
              throw FlutterError("heic", "Not enough memory for a ${w}x$h bitmap")
            }
        try {
          RandomAccessFile(rgbaPath, "r").use { f ->
            bitmap.copyPixelsFromBuffer(f.channel.map(FileChannel.MapMode.READ_ONLY, 0, w.toLong() * h * 4))
          }
          val writer =
              HeifWriter.Builder(dstPath, w, h, HeifWriter.INPUT_MODE_BITMAP)
                  .setQuality(quality.toInt().coerceIn(0, 100))
                  .setGridEnabled(true)
                  .setMaxImages(1)
                  .build()
          try {
            writer.start()
            writer.addBitmap(bitmap)
            writer.stop(0) // waits until the file is complete
          } finally {
            writer.close()
          }
        } catch (e: FlutterError) {
          throw e
        } catch (e: Exception) {
          File(dstPath).delete()
          throw FlutterError("heic", e.message ?: e.javaClass.simpleName)
        } finally {
          bitmap.recycle()
        }
      }

  override fun thermalLevel(): Long =
      levelOf(context.getSystemService(PowerManager::class.java)?.currentThermalStatus ?: PowerManager.THERMAL_STATUS_NONE)

  /** NFR-THERM-002: PowerManager's status as the core's level (enh.h enh_set_thermal). */
  private fun levelOf(status: Int): Long =
      when (status) {
        PowerManager.THERMAL_STATUS_NONE -> 0L
        PowerManager.THERMAL_STATUS_LIGHT -> 1L
        PowerManager.THERMAL_STATUS_MODERATE -> 2L
        PowerManager.THERMAL_STATUS_SEVERE -> 3L
        else -> 4L // CRITICAL, EMERGENCY, SHUTDOWN
      }

  private val thermalListener =
      PowerManager.OnThermalStatusChangedListener { status ->
        val level = levelOf(status)
        main.launch {
          try {
            events?.onThermalLevel(level)
          } catch (_: Exception) {
            // Dart side not ready: it reads thermalLevel() when it opens the core
          }
        }
      }

  /**
   * NFR-MEM-004: onTrimMemory as enh_set_memory_pressure levels. UI_HIDDEN says nothing about
   * memory; API 34+ sends only it and BACKGROUND, so BACKGROUND counts as moderate.
   */
  @Suppress("DEPRECATION") // the RUNNING_* and MODERATE/COMPLETE levels still come before API 34
  private fun memoryLevelOf(trim: Int): Long? =
      when {
        trim >= ComponentCallbacks2.TRIM_MEMORY_COMPLETE -> 3L
        trim >= ComponentCallbacks2.TRIM_MEMORY_MODERATE -> 2L
        trim >= ComponentCallbacks2.TRIM_MEMORY_BACKGROUND -> 1L
        trim == ComponentCallbacks2.TRIM_MEMORY_UI_HIDDEN -> null
        trim >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_CRITICAL -> 3L
        trim >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_LOW -> 2L
        trim >= ComponentCallbacks2.TRIM_MEMORY_RUNNING_MODERATE -> 1L
        else -> null
      }

  private fun sendMemoryPressure(level: Long) {
    main.launch {
      try {
        events?.onMemoryPressure(level)
      } catch (_: Exception) {
        // Dart side not ready: no job is running
      }
    }
  }

  private val memoryCallbacks =
      object : ComponentCallbacks2 {
        override fun onTrimMemory(level: Int) {
          memoryLevelOf(level)?.let(::sendMemoryPressure)
        }

        override fun onConfigurationChanged(newConfig: Configuration) {}

        @Deprecated("Deprecated in Java")
        override fun onLowMemory() = sendMemoryPressure(3L)
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
      AppDirs(
          support = context.noBackupFilesDir.absolutePath,
          // Backup rules (app/android/.../xml/backup_rules.xml) take only prefs.sqlite from here.
          backedUp = context.filesDir.absolutePath,
          cache = context.cacheDir.absolutePath)

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

  override suspend fun pickImages(inboxDir: String, maxCount: Long): PickedImages {
    val activity = binding?.activity ?: throw FlutterError("no_activity", "No foreground activity")
    if (pending != null) throw FlutterError("busy", "A picker is already open")
    val deferred = CompletableDeferred<List<Uri>>()
    pending = deferred
    activity.startActivityForResult(pickerIntent(maxCount.toInt()), REQUEST_PICK)
    val uris = deferred.await().take(maxCount.toInt())
    return withContext(Dispatchers.IO) { copyAllToInbox(uris, File(inboxDir)) }
  }

  override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
    when (requestCode) {
      REQUEST_PICK -> {
        val d = pending ?: return true
        pending = null
        d.complete(if (resultCode == Activity.RESULT_OK) selection(data) else emptyList())
      }
      REQUEST_CREATE -> {
        val d = pendingCreate ?: return true
        pendingCreate = null
        d.complete(if (resultCode == Activity.RESULT_OK) data?.data else null)
      }
      REQUEST_OPEN -> {
        val d = pendingOpen ?: return true
        pendingOpen = null
        d.complete(if (resultCode == Activity.RESULT_OK) data?.data else null)
      }
      else -> return false
    }
    return true
  }

  /** A multiple selection comes as ClipData, a single one as the data URI. */
  private fun selection(data: Intent?): List<Uri> {
    val clip = data?.clipData ?: return listOfNotNull(data?.data)
    return (0 until clip.itemCount).mapNotNull { clip.getItemAt(it).uri }
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

  /**
   * Remembers the images of ACTION_SEND / ACTION_SEND_MULTIPLE (added to those not taken yet);
   * the intent is consumed so a recreated activity does not repeat it.
   */
  /** FR-SHARE-001/002: ACTION_SEND(_MULTIPLE) streams, or the data of ACTION_EDIT. */
  private fun takeShare(intent: Intent?): Boolean {
    if (intent == null) return false
    val type = intent.type ?: intent.data?.let { context.contentResolver.getType(it) }
    if (type?.startsWith("image/") != true) return false
    val uris: List<Uri> =
        when (intent.action) {
          Intent.ACTION_EDIT -> listOfNotNull(intent.data)
          Intent.ACTION_SEND ->
              listOfNotNull(
                  if (Build.VERSION.SDK_INT >= 33) intent.getParcelableExtra(Intent.EXTRA_STREAM, Uri::class.java)
                  else @Suppress("DEPRECATION") intent.getParcelableExtra(Intent.EXTRA_STREAM))
          Intent.ACTION_SEND_MULTIPLE ->
              (if (Build.VERSION.SDK_INT >= 33) intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM, Uri::class.java)
              else @Suppress("DEPRECATION") intent.getParcelableArrayListExtra(Intent.EXTRA_STREAM))
                  .orEmpty()
          else -> return false
        }
    intent.action = null
    if (uris.isEmpty()) return false
    shared = shared + uris
    return true
  }

  override fun openUrl(url: String) {
    val uri = Uri.parse(url)
    if (uri.scheme != "https") throw FlutterError("bad_url", "https only")
    try {
      val intent = Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
      (binding?.activity ?: context).startActivity(intent)
    } catch (_: ActivityNotFoundException) {
      throw FlutterError("no_browser", "No app opens links")
    }
  }

  override fun shareFile(path: String, mimeType: String, chooserTitle: String) {
    val activity = binding?.activity ?: throw FlutterError("no_activity", "No foreground activity")
    val uri = ShareProvider.uriFor(context, File(path), mimeType)
    // The URI in ClipData too: the read grant then reaches the chooser itself, which shows a
    // preview of the file from its own process (else "Permission Denial ... not exported").
    val send =
        Intent(Intent.ACTION_SEND)
            .setType(mimeType)
            .putExtra(Intent.EXTRA_STREAM, uri)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    send.clipData = ClipData.newRawUri(null, uri)
    activity.startActivity(Intent.createChooser(send, chooserTitle))
  }

  override suspend fun takeSharedImages(inboxDir: String): PickedImages {
    val uris = shared
    shared = emptyList()
    return withContext(Dispatchers.IO) { copyAllToInbox(uris, File(inboxDir)) }
  }

  /** Each image on its own: one that cannot be copied does not lose the others. */
  private fun copyAllToInbox(uris: List<Uri>, inbox: File): PickedImages {
    val images = mutableListOf<PickedImage>()
    var failure: String? = null
    for (uri in uris) {
      try {
        images += copyToInbox(uri, inbox)
      } catch (e: FlutterError) {
        failure = failure ?: e.code
      } catch (e: IOException) {
        failure = failure ?: "io"
      } catch (e: SecurityException) {
        failure = failure ?: "io" // the URI grant was revoked
      }
    }
    return PickedImages(images = images, failed = (uris.size - images.size).toLong(), failure = failure)
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

  override suspend fun pickFile(dstDir: String, maxBytes: Long): String? {
    val activity = binding?.activity ?: throw FlutterError("no_activity", "No foreground activity")
    if (pendingOpen != null) throw FlutterError("busy", "A file picker is already open")
    val deferred = CompletableDeferred<Uri?>()
    pendingOpen = deferred
    // .rfpack has no registered MIME type: any file, the core decides what it is.
    activity.startActivityForResult(
        Intent(Intent.ACTION_OPEN_DOCUMENT).addCategory(Intent.CATEGORY_OPENABLE).setType("*/*"),
        REQUEST_OPEN)
    val uri = deferred.await() ?: return null
    return withContext(Dispatchers.IO) {
      val dir = File(dstDir)
      if (!dir.isDirectory && !dir.mkdirs()) throw IOException("cannot create $dstDir")
      val dst = File(dir, "import-${UUID.randomUUID()}.rfpack")
      try {
        (context.contentResolver.openInputStream(uri) ?: throw IOException("cannot open file")).use { input ->
          dst.outputStream().use { out ->
            val buf = ByteArray(1 shl 16)
            var total = 0L
            while (true) {
              val n = input.read(buf)
              if (n < 0) break
              total += n
              if (total > maxBytes) throw FlutterError("limit", "File is larger than $maxBytes bytes")
              out.write(buf, 0, n)
            }
          }
        }
        dst.absolutePath
      } catch (e: Exception) {
        dst.delete()
        throw e
      }
    }
  }

  private fun pickerIntent(maxCount: Int): Intent {
    val hasPhotoPicker =
        Build.VERSION.SDK_INT >= 33 ||
            (Build.VERSION.SDK_INT >= 30 && SdkExtensions.getExtensionVersion(Build.VERSION_CODES.R) >= 2)
    return if (hasPhotoPicker) {
      Intent(MediaStore.ACTION_PICK_IMAGES).setType("image/*").apply {
        // The extra must be > 1 and <= the system limit; without it the selection is single.
        if (maxCount > 1) putExtra(MediaStore.EXTRA_PICK_IMAGES_MAX, maxCount.coerceAtMost(MediaStore.getPickImagesMaxLimit()))
      }
    } else {
      Intent(Intent.ACTION_OPEN_DOCUMENT)
          .addCategory(Intent.CATEGORY_OPENABLE)
          .setType("image/*")
          .putExtra(Intent.EXTRA_ALLOW_MULTIPLE, maxCount > 1)
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
    checkForeignContent(uri)
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
    // FR-IMP-004: the copy is named by the SHA-256 of its bytes (hashed while copying), so the
    // same photo picked or shared again reuses its copy. The temporary name is random: several
    // copies run at once (multi-pick).
    val tmp = File(inbox, "in-${UUID.randomUUID()}.part")
    val dst: File
    try {
      val digest = MessageDigest.getInstance("SHA-256")
      (cr.openInputStream(uri) ?: throw IOException("cannot open selection")).use { input ->
        DigestInputStream(input, digest).use { hashed ->
          tmp.outputStream().use { out ->
            val buf = ByteArray(1 shl 16)
            var total = 0L
            while (true) {
              val n = hashed.read(buf)
              if (n < 0) break
              total += n
              // SEC-INP-002: the core refuses larger files anyway; don't fill the disk first.
              if (total > MAX_INPUT_BYTES) throw FlutterError("limit", "File is larger than 200 MB")
              out.write(buf, 0, n)
            }
          }
        }
      }
      val hex = digest.digest().joinToString("") { "%02x".format(it) }
      dst = File(inbox, "in-$hex.$ext")
      // An existing copy has the same bytes; renaming over it would also be correct, but keeping
      // it leaves the file a running job reads untouched.
      if (!dst.exists() && !tmp.renameTo(dst)) throw IOException("rename failed")
    } finally {
      tmp.delete() // no-op after the rename
    }
    if (Build.VERSION.SDK_INT < 30 && ext == "heic") return heicToPng(dst, name)
    return PickedImage(path = dst.absolutePath, sizeBytes = dst.length(), displayName = name, mimeType = mime)
  }

  /**
   * A shared or "edit with" URI comes from another app, which chooses it. Only content that app
   * can grant is taken: no file:// URIs and no URIs of Refocal's own providers, which this app
   * could read with its own rights (private files, other images in cache/share).
   */
  private fun checkForeignContent(uri: Uri) {
    if (uri.scheme != ContentResolver.SCHEME_CONTENT) throw FlutterError("denied", "Not a content URI")
    val authority = uri.authority ?: throw FlutterError("denied", "No authority")
    // Package visibility may hide another app's provider (null); Refocal's own always resolve.
    val owner = context.packageManager.resolveContentProvider(authority, 0)?.packageName
    if (owner == context.packageName) throw FlutterError("denied", "Refocal's own content")
  }

  /**
   * Android 10 has no AImageDecoder for the core (ADR-0003): decode HEIC here and hand the core a
   * lossless PNG. The size limits of the core (SEC-INP-002) are checked on the header, before the
   * pixels are allocated; colors are converted to sRGB as the core's platform decoder does.
   * EXIF is not carried. Neither the HEIC copy nor a partial PNG is left behind on failure.
   */
  private fun heicToPng(src: File, name: String?): PickedImage {
    val png = File(src.parentFile, src.nameWithoutExtension + ".png")
    if (png.exists()) { // the same photo was converted before (the name is its SHA-256)
      src.delete()
      return PickedImage(path = png.absolutePath, sizeBytes = png.length(), displayName = name, mimeType = "image/png")
    }
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
    private const val REQUEST_OPEN = 0x5EF3
    // SEC-INP-002, as in the core (native/core/src/image/decode.hpp: kMaxSide, kMaxPixels).
    private const val MAX_SIDE = 30000L
    private const val MAX_PIXELS = 200_000_000L
    private const val MAX_INPUT_BYTES = 200L shl 20 // kMaxFileBytes
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
