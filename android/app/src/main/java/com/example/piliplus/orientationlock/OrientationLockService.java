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
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        final String mode = intent.getStringExtra(EXTRA_MODE);
        final int orientation = toScreenOrientation(mode);
        if (orientation == ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED) {
            removeOrientationLayout();
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
                !Settings.canDrawOverlays(this)) {
            removeOrientationLayout();
            stopSelf(startId);
            return START_NOT_STICKY;
        }

        setSystemOrientation(orientation);
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

    private void setSystemOrientation(int orientation) {
        if (holderView == null) {
            final int type = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O
                    ? WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
                    : WindowManager.LayoutParams.TYPE_PHONE;
            layoutParams = new WindowManager.LayoutParams(
                    0,
                    0,
                    type,
                    WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL |
                            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE,
                    PixelFormat.RGBA_8888
            );
            layoutParams.gravity = Gravity.TOP | Gravity.START;
            holderView = new Space(this);
            try {
                windowManager.addView(holderView, layoutParams);
            } catch (RuntimeException exception) {
                holderView = null;
                layoutParams = null;
                stopSelf();
                return;
            }
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            layoutParams.screenOrientation = orientation;
            try {
                windowManager.updateViewLayout(holderView, layoutParams);
            } catch (RuntimeException exception) {
                removeOrientationLayout();
                stopSelf();
            }
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
