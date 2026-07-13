package me.noam.multi_screen_presentation

import android.app.Presentation
import android.content.Context
import android.hardware.display.DisplayManager
import android.os.Bundle
import android.view.Display
import android.view.ViewGroup
import androidx.annotation.NonNull
import io.flutter.FlutterInjector
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.renderer.FlutterUiDisplayListener
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.embedding.engine.plugins.FlutterPlugin

/**
 * Sur Android, l'ouverture d'une fenêtre sur un écran externe passe par
 * l'API `Presentation`, qui est TOUJOURS plein cadre sur l'écran cible :
 * il n'existe pas de notion de "fenêtre flottante déplaçable" entre deux
 * displays physiques comme sur desktop. Le double-clic pour basculer
 * floating <-> fullscreen est donc traité comme un simple événement
 * applicatif ignoré côté natif (ou mappé sur une notion de zoom / letterbox
 * si besoin), mais la présentation reste toujours en plein écran sur son
 * Display Android.
 */
class MultiScreenPresentationPlugin : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {

  private lateinit var channel: MethodChannel
  private lateinit var eventChannel: EventChannel
  private var eventSink: EventChannel.EventSink? = null
  private lateinit var appContext: Context
  private lateinit var displayManager: DisplayManager

  private val presentations = mutableMapOf<String, PresentationHolder>()
  private var idCounter = 0

  inner class PresentationHolder(
    val id: String,
    val presentation: AppPresentation,
    val engine: FlutterEngine?,
    val windowChannel: MethodChannel?,
  )

  override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    appContext = binding.applicationContext
    displayManager = appContext.getSystemService(Context.DISPLAY_SERVICE) as DisplayManager

    channel = MethodChannel(binding.binaryMessenger, "multi_screen_presentation")
    channel.setMethodCallHandler(this)

    eventChannel = EventChannel(binding.binaryMessenger, "multi_screen_presentation/events")
    eventChannel.setStreamHandler(this)

    displayManager.registerDisplayListener(object : DisplayManager.DisplayListener {
      override fun onDisplayAdded(displayId: Int) = emitScreensChanged()
      override fun onDisplayRemoved(displayId: Int) = emitScreensChanged()
      override fun onDisplayChanged(displayId: Int) = emitScreensChanged()
    }, null)
  }

  private fun emitScreensChanged() {
    eventSink?.success(mapOf("type" to "screensChanged"))
  }

  override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
    channel.setMethodCallHandler(null)
    eventChannel.setStreamHandler(null)
  }

  override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
    eventSink = events
  }

  override fun onCancel(arguments: Any?) {
    eventSink = null
  }

  override fun onMethodCall(call: MethodCall, result: Result) {
    when (call.method) {
      "getScreens" -> result.success(getScreens())
      "openWindow" -> {
        try {
          val id = openWindow(call.arguments as Map<String, Any?>)
          result.success(id)
        } catch (e: Exception) {
          result.error("open_failed", e.message, null)
        }
      }
      "closeWindow" -> {
        val id = (call.arguments as Map<*, *>)["windowId"] as String
        closeWindow(id)
        result.success(null)
      }
      "toggleWindowMode", "setWindowMode", "setWindowTitle", "setWindowPosition", "setWindowSize", "setWindowOpacity", "setWindowAlwaysOnTop", "setWindowResizable", "setWindowVisible" -> {
        // Pas de mode floating sur écran externe Android : no-op documenté.
        result.success(null)
      }
      "sendData" -> {
        val args = call.arguments as Map<*, *>
        val id = args["windowId"] as String
        @Suppress("UNCHECKED_CAST")
        val data = args["data"] as Map<String, Any?>
        presentations[id]?.windowChannel?.invokeMethod("onData", data)
        result.success(null)
      }
      else -> result.notImplemented()
    }
  }

  private fun getScreens(): List<Map<String, Any?>> {
    val displays = displayManager.displays
    return displays.map { d ->
      val metrics = android.util.DisplayMetrics()
      @Suppress("DEPRECATION")
      d.getRealMetrics(metrics)
      mapOf(
        "id" to "display_${d.displayId}",
        "name" to d.name,
        "x" to 0.0,
        "y" to 0.0,
        "width" to metrics.widthPixels.toDouble(),
        "height" to metrics.heightPixels.toDouble(),
        "scaleFactor" to metrics.density.toDouble(),
        "isPrimary" to (d.displayId == Display.DEFAULT_DISPLAY),
      )
    }
  }

  private fun findDisplay(screenId: String): Display? {
    return displayManager.displays.firstOrNull { "display_${it.displayId}" == screenId }
  }

  private fun openWindow(args: Map<String, Any?>): String {
    val screenId = args["screenId"] as String
    val display = findDisplay(screenId)
      ?: throw IllegalArgumentException("Écran introuvable: $screenId")
    val useLiveEngine = (args["contentMode"] as? String ?: "liveFlutterEngine") == "liveFlutterEngine"
    val entrypoint = args["entrypoint"] as? String ?: "presentationMain"

    val id = "android_win_${++idCounter}"

    var engine: FlutterEngine? = null
    var windowChannel: MethodChannel? = null

    val presentation = AppPresentation(appContext, display)
    presentation.setOnDismissListener {
      presentations.remove(id)
      eventSink?.success(mapOf("type" to "closed", "windowId" to id))
    }

    if (useLiveEngine) {
      val flEngine = FlutterEngine(appContext)
      val loader = FlutterInjector.instance().flutterLoader()
      val entry = DartExecutor.DartEntrypoint(
        loader.findAppBundlePath(),
        entrypoint,
      )
      flEngine.dartExecutor.executeDartEntrypoint(entry)
      engine = flEngine

      val flutterView = FlutterView(appContext)
      flutterView.attachToFlutterEngine(flEngine)
      presentation.setContentViewGroup(flutterView)

      windowChannel = MethodChannel(flEngine.dartExecutor.binaryMessenger, "multi_screen_presentation/window")
      windowChannel.setMethodCallHandler { call, res ->
        if (call.method == "sendToMain") {
          @Suppress("UNCHECKED_CAST")
          val data = call.arguments as? Map<String, Any?> ?: emptyMap<String, Any?>()
          eventSink?.success(mapOf("type" to "data", "windowId" to id, "data" to data))
        }
        res.success(null)
      }
    } else {
      val plain = android.view.View(appContext)
      plain.setBackgroundColor(android.graphics.Color.BLACK)
      presentation.setContentViewGroup(plain)
    }

    presentation.show()
    presentations[id] = PresentationHolder(id, presentation, engine, windowChannel)
    return id
  }

  private fun closeWindow(id: String) {
    presentations[id]?.let {
      it.presentation.dismiss()
      it.engine?.destroy()
      presentations.remove(id)
    }
  }
}

/**
 * Presentation minimaliste acceptant n'importe quelle View/ViewGroup comme
 * contenu (Flutter ou natif).
 */
class AppPresentation(context: Context, display: Display) : Presentation(context, display) {
  fun setContentViewGroup(view: android.view.View) {
    val container = android.widget.FrameLayout(context)
    container.addView(
      view,
      ViewGroup.LayoutParams(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
    )
    setContentView(container)
  }
}