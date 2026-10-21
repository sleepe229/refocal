package io.github.refocal.app

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.github.refocal.refocal_platform.AppUpdateApi

/** The `github` flavor registers the self-updater (ADR-0027). */
object FlavorSetup {
  fun register(engine: FlutterEngine, context: Context) =
      AppUpdateApi.setUp(engine.dartExecutor.binaryMessenger, AppUpdater(context))
}
