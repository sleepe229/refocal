// SPDX-License-Identifier: Apache-2.0
package io.github.refocal.refocal_platform

import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.database.Cursor
import android.database.MatrixCursor
import android.net.Uri
import android.os.ParcelFileDescriptor
import android.provider.OpenableColumns
import java.io.File
import java.io.FileNotFoundException

/**
 * Read-only access for the share sheet to files the app put into `cache/share/` (a bug-report
 * log, later exported photos). Our own minimal provider: androidx FileProvider would add a
 * dependency (COMP-FDR-007). Other apps get access only through the URI grant of a share
 * intent; the provider is not exported.
 */
class ShareProvider : ContentProvider() {
  override fun onCreate(): Boolean = true

  private fun fileFor(uri: Uri): File {
    val ctx = context ?: throw FileNotFoundException("no context")
    val name = uri.lastPathSegment ?: throw FileNotFoundException("no file")
    val dir = shareDir(ctx).canonicalFile
    val f = File(dir, name).canonicalFile
    if (f.parentFile != dir || !f.isFile) throw FileNotFoundException("not shared")
    return f
  }

  override fun openFile(uri: Uri, mode: String): ParcelFileDescriptor {
    if (mode != "r") throw SecurityException("read-only")
    return ParcelFileDescriptor.open(fileFor(uri), ParcelFileDescriptor.MODE_READ_ONLY)
  }

  override fun query(uri: Uri, projection: Array<out String>?, selection: String?,
                     selectionArgs: Array<out String>?, sortOrder: String?): Cursor {
    val f = fileFor(uri)
    val cols = projection ?: arrayOf(OpenableColumns.DISPLAY_NAME, OpenableColumns.SIZE)
    val row = cols.map {
      when (it) {
        OpenableColumns.DISPLAY_NAME -> f.name
        OpenableColumns.SIZE -> f.length()
        else -> null
      }
    }
    return MatrixCursor(cols, 1).apply { addRow(row) }
  }

  override fun getType(uri: Uri): String? = uri.getQueryParameter(MIME)

  override fun insert(uri: Uri, values: ContentValues?): Uri? = throw UnsupportedOperationException()
  override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int =
      throw UnsupportedOperationException()
  override fun update(uri: Uri, values: ContentValues?, selection: String?,
                      selectionArgs: Array<out String>?): Int = throw UnsupportedOperationException()

  companion object {
    private const val MIME = "mime"

    fun shareDir(context: Context) = File(context.cacheDir, "share")

    fun uriFor(context: Context, file: File, mimeType: String): Uri {
      val dir = shareDir(context).canonicalFile
      require(file.canonicalFile.parentFile == dir) { "only files in cache/share can be shared" }
      return Uri.Builder()
          .scheme("content")
          .authority("${context.packageName}.refocal.share")
          .appendPath(file.name)
          .appendQueryParameter(MIME, mimeType)
          .build()
    }
  }
}
