package com.example.piliplus.orientationlock;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.Service;
import android.content.Context;
import android.content.Intent;
import android.content.pm.ActivityInfo;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.IBinder;
import android.provider.Settings;
import android.view.Gravity;
import android.view.WindowManager;
import android.widget.Space;

public final class OrientationLockService extends Service {
    public static final String EXTRA_MODE = "mode";
    private static final String CHANNEL_ID = "orientation_lock";
    private static final int NOTIFICATION_ID = 7241;

    public interface OrientationResultCallback {
        void onResult(boolean success, String code, String message);
    }

    private static OrientationResultCallback pendingResultCallback;

    public static synchronized void setResultCallback(OrientationResultCallback callback) {
        pendingResultCallback = callback;
    }

    public static synchronized void clearResultCallback() {
        pendingResultCallback = null;
    }

    public static void notifyResult(boolean success, String code, String message) {
        final OrientationResultCallback callback;
        synchronized (OrientationLockService.class) {
            callback = pendingResultCallback;
            pendingResultCallback = null;
        }
        if (callback != null) {
            callback.onResult(success, code, message);
        }
    }

    private WindowManager windowManager;
    private Space holderView;
    private WindowManager.LayoutParams layoutParams;

    @Override
    public void onCreate() {
        super.onCreate();
        windowManager = (WindowManager) getSystemService(Context.WINDOW_SERVICE);
        createNotificationChannel();
        startForeground(NOTIFICATION_ID, buildNotification());
    }

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        if (intent == null) {
            notifyResult(false, "orientation_service", "方向锁定服务未收到模式");
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        final String mode = intent.getStringExtra(EXTRA_MODE);
        final int orientation = toScreenOrientation(mode);
        if (orientation == ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED) {
            removeOrientationLayout();
            notifyResult(true, null, null);
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            removeOrientationLayout();
            notifyResult(false, "unsupported_android_version",
                    "悬浮方向锁定需要 Android 8.0 或更高版本");
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !Settings.canDrawOverlays(this)) {
            removeOrientationLayout();
            notifyResult(false, "overlay_permission", "悬浮窗权限已关闭，请重新授权");
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        if (setSystemOrientation(orientation)) {
            notifyResult(true, null, null);
        } else {
            notifyResult(false, "orientation_apply_failed", "系统未能应用所选屏幕方向");
            stopSelf(startId);
        }
        return START_NOT_STICKY;
    }

    private int toScreenOrientation(String mode) {
        if ("portrait".equals(mode)) {
            return ActivityInfo.SCREEN_ORIENTATION_PORTRAIT;
        }
        if ("landscape".equals(mode)) {
            return ActivityInfo.SCREEN_ORIENTATION_LANDSCAPE;
        }
        if ("reverseLandscape".equals(mode)) {
            return ActivityInfo.SCREEN_ORIENTATION_REVERSE_LANDSCAPE;
        }
        return ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
    }

    private boolean setSystemOrientation(int orientation) {
        final int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                : WindowManager.LayoutParams.TYPE_PHONE;
        layoutParams = new WindowManager.LayoutParams(
                WindowManager.LayoutParams.WRAP_CONTENT,
                WindowManager.LayoutParams.WRAP_CONTENT,
                type,
                WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL |
                        WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                PixelFormat.RGBA_8888
        );
        layoutParams.gravity = Gravity.TOP | Gravity.START;

        if (holderView == null) {
            holderView = new Space(this);
            holderView.setClickable(false);
            holderView.setFocusable(false);
            holderView.setFocusableInTouchMode(false);
            holderView.setLongClickable(false);
            try {
                windowManager.addView(holderView, layoutParams);
                holderView.setVisibility(android.view.View.GONE);
            } catch (RuntimeException exception) {
                holderView = null;
                layoutParams = null;
                return false;
            }
        }

        layoutParams.screenOrientation = orientation;
        try {
            windowManager.updateViewLayout(holderView, layoutParams);
            // Match the upstream OrientationLock implementation: a zero-size,
            // permanently invisible overlay may not request an orientation on
            // some Android builds. Keep the holder non-interactive but visible.
            holderView.setVisibility(android.view.View.VISIBLE);
            return true;
        } catch (RuntimeException exception) {
            removeOrientationLayout();
            return false;
        }
    }

    private void removeOrientationLayout() {
        if (holderView != null && windowManager != null) {
            try {
                windowManager.removeViewImmediate(holderView);
            } catch (RuntimeException ignored) {
            }
            holderView = null;
            layoutParams = null;
        }
    }

    private void createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel channel = new NotificationChannel(
                    CHANNEL_ID,
                    "方向锁定",
                    NotificationManager.IMPORTANCE_MIN
            );
            channel.setDescription("保持用户选择的屏幕方向");
            NotificationManager manager = getSystemService(NotificationManager.class);
            if (manager != null) {
                manager.createNotificationChannel(channel);
            }
        }
    }

    private Notification buildNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            return new Notification.Builder(this, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_menu_rotate)
                    .setContentTitle("方向锁定已启用")
                    .setContentText("正在应用所选屏幕方向")
                    .setOngoing(true)
                    .build();
        }
        return new Notification.Builder(this)
                .setSmallIcon(android.R.drawable.ic_menu_rotate)
                .setContentTitle("方向锁定已启用")
                .setContentText("正在应用所选屏幕方向")
                .setOngoing(true)
                .build();
    }

    @Override
    public void onDestroy() {
        removeOrientationLayout();
        super.onDestroy();
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
