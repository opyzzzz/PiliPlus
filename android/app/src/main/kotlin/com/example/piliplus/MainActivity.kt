package com.example.piliplus

import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var mediaKeyChannel: MethodChannel? = null
    @Volatile private var mediaKeyShortcutsEnabled = false
    @Volatile private var capturedMediaKeyCodes: Set<Int> = emptySet()
    @Volatile private var capturingMediaKey = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        mediaKeyChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "piliplus/media_key_shortcuts",
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "setEnabled" -> {
                        mediaKeyShortcutsEnabled = call.argument<Boolean>("enabled") == true
                        capturedMediaKeyCodes = if (mediaKeyShortcutsEnabled) {
                            (call.argument<List<Int>>("keyCodes") ?: emptyList()).toSet()
                        } else {
                            emptySet()
                        }
                        result.success(null)
                    }
                    "setCapturing" -> {
                        capturingMediaKey = call.argument<Boolean>("capturing") == true
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent): Boolean {
        val supported = when (event.keyCode) {
            KeyEvent.KEYCODE_VOLUME_UP,
            KeyEvent.KEYCODE_VOLUME_DOWN,
            KeyEvent.KEYCODE_VOLUME_MUTE,
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE,
            KeyEvent.KEYCODE_MEDIA_NEXT,
            KeyEvent.KEYCODE_MEDIA_PREVIOUS -> true
            else -> false
        }
        if (supported && (capturingMediaKey ||
            (mediaKeyShortcutsEnabled && event.keyCode in capturedMediaKeyCodes))
        ) {
            val action = when (event.action) {
                KeyEvent.ACTION_UP -> "up"
                KeyEvent.ACTION_DOWN -> if (event.repeatCount > 0) "repeat" else "down"
                else -> null
            }
            if (action != null) {
                mediaKeyChannel?.invokeMethod(
                    "keyEvent",
                    mapOf(
                        "keyCode" to event.keyCode,
                        "action" to action,
                        "repeatCount" to event.repeatCount,
                    ),
                )
                // Only consume these keys after explicit opt-in; otherwise Android
                // retains normal volume and media-session behavior.
                if (mediaKeyChannel != null) return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        if (AndroidHelper.isFoldable) {
            AndroidHelper.ToDart.onConfigurationChanged?.run()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            window.attributes.layoutInDisplayCutoutMode =
                LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
        }
    }

    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        AndroidHelper.ToDart.onUserLeaveHint?.run()
    }

    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration?) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        AndroidHelper.isPipMode = isInPictureInPictureMode
    }
}
