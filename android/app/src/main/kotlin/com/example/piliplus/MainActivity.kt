package com.example.piliplus

import android.content.Intent
import android.content.res.Configuration
import android.net.Uri
import android.provider.Settings
import android.os.Build
import android.os.Bundle
import android.view.WindowManager.LayoutParams
import com.ryanheise.audioservice.AudioServiceActivity
import com.example.piliplus.orientationlock.OrientationLockService
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.example.piliplus/orientation_lock")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestOverlayPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !Settings.canDrawOverlays(this)
                        ) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.success(false)
                        } else {
                            result.success(true)
                        }
                    }
                    "setOrientation" -> {
                        val mode = call.argument<String>("mode") ?: "default"
                        val service = Intent(this, OrientationLockService::class.java)
                            .putExtra(OrientationLockService.EXTRA_MODE, mode)
                        if (mode == "default") {
                            OrientationLockService.clearResultCallback()
                            stopService(service)
                            result.success(true)
                        } else if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                            result.error(
                                "unsupported_android_version",
                                "悬浮方向锁定需要 Android 8.0 或更高版本",
                                null
                            )
                        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                            !Settings.canDrawOverlays(this)
                        ) {
                            startActivity(
                                Intent(
                                    Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                            )
                            result.error(
                                "overlay_permission",
                                "请先授予悬浮窗权限，然后重新选择方向",
                                null
                            )
                        } else {
                            OrientationLockService.setResultCallback { success, code, message ->
                                if (success) {
                                    result.success(true)
                                } else {
                                    result.error(code, message, null)
                                }
                            }
                            try {
                                startForegroundService(service)
                            } catch (exception: RuntimeException) {
                                OrientationLockService.notifyResult(
                                    false,
                                    "orientation_service",
                                    exception.message ?: "启动方向锁定服务失败"
                                )
                            }
                        }
                    }
                    else -> result.notImplemented()
                }
            }
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
