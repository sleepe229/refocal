package io.github.refocal.app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

/** No self-update in this flavor (ADR-0027): AppUpdateApi stays unregistered. */
object FlavorSetup {
  @Suppress("UNUSED_PARAMETER")
  fun register(engine: FlutterEngine, context: Context) = Unit
}
