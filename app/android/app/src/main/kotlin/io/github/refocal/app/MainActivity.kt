package io.github.refocal.app

import android.content.Context
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * The FlutterEngine outlives the activity (ADR-0019): when the user swipes the app away while
 * a photo is processed in the foreground service, the Dart isolate that receives the job's
 * events keeps running, and reopening the app shows the same screen.
 */
class MainActivity : FlutterActivity() {
  override fun provideFlutterEngine(context: Context): FlutterEngine =
      FlutterEngineCache.getInstance().get(ENGINE_ID)
          ?: FlutterEngine(context.applicationContext).also {
            it.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint.createDefault())
            FlutterEngineCache.getInstance().put(ENGINE_ID, it)
          }

  override fun shouldDestroyEngineWithHost(): Boolean = false

  private companion object {
    const val ENGINE_ID = "main"
  }
}
