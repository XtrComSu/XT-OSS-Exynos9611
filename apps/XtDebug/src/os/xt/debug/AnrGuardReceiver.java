// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.ActivityOptions;
import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.os.Build;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.Log;

/**
 * Boot receiver for XT Debug:
 * <ul>
 *   <li>Ensures {@code device_provisioned=1} and {@code user_setup_complete=1}</li>
 *   <li>Applies saved ZRAM swap, VoLTE, and browser ANR guard preferences</li>
 *   <li>Automatically launches {@link XtWelcomeActivity} into the foreground on first boot</li>
 * </ul>
 */
public final class AnrGuardReceiver extends BroadcastReceiver {
    private static final String TAG = "XtDebugBoot";
    private static final String CHANNEL_ID = "xt_debug_status";
    private static final String KEY_WELCOME_SHOWN = "xt_series_welcome_shown";
    private static final Handler MAIN_HANDLER = new Handler(Looper.getMainLooper());

    @Override
    public void onReceive(final Context context, final Intent intent) {
        if (intent == null || intent.getAction() == null) return;
        final String action = intent.getAction();
        Log.i(TAG, "Boot broadcast received (" + action + ")");
        final PendingResult pending = goAsync();
        final Context appCtx = context.getApplicationContext();

        AnrGuardEngine.runAsync(() -> {
            ensureDeviceProvisioned(appCtx);
            AnrGuardEngine.applyAllDefaults(appCtx);
            if (Intent.ACTION_BOOT_COMPLETED.equals(action)
                    || Intent.ACTION_LOCKED_BOOT_COMPLETED.equals(action)) {
                maybeShowFirstBootNotification(appCtx);
                scheduleFirstBootWelcomeLaunch(appCtx);
            }
            return Boolean.TRUE;
        }, res -> pending.finish());
    }

    private static void scheduleFirstBootWelcomeLaunch(final Context context) {
        if (AnrGuardEngine.isOnboardingCompleted(context)) {
            return;
        }
        MAIN_HANDLER.post(() -> tryLaunchWelcome(context));
        MAIN_HANDLER.postDelayed(() -> tryLaunchWelcome(context), 2500L);
        MAIN_HANDLER.postDelayed(() -> tryLaunchWelcome(context), 5500L);
    }

    private static void tryLaunchWelcome(Context context) {
        try {
            if (AnrGuardEngine.isOnboardingCompleted(context) || XtWelcomeActivity.sIsVisible) {
                return;
            }
            Intent wiz = new Intent(context, XtWelcomeActivity.class);
            wiz.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK
                    | Intent.FLAG_ACTIVITY_CLEAR_TOP
                    | Intent.FLAG_ACTIVITY_SINGLE_TOP
                    | Intent.FLAG_ACTIVITY_REORDER_TO_FRONT);
            if (Build.VERSION.SDK_INT >= 34) {
                ActivityOptions opts = ActivityOptions.makeBasic();
                opts.setPendingIntentBackgroundActivityStartMode(
                        ActivityOptions.MODE_BACKGROUND_ACTIVITY_START_ALLOWED);
                context.startActivity(wiz, opts.toBundle());
            } else {
                context.startActivity(wiz);
            }
            Log.i(TAG, "Launched XtWelcomeActivity on first boot");
        } catch (Throwable t) {
            Log.w(TAG, "Could not auto-launch XtWelcomeActivity", t);
        }
    }

    public static void ensureDeviceProvisioned(Context context) {
        try {
            ContentResolver cr = context.getContentResolver();
            if (Settings.Global.getInt(cr, Settings.Global.DEVICE_PROVISIONED, 0) == 0) {
                Settings.Global.putInt(cr, Settings.Global.DEVICE_PROVISIONED, 1);
            }
            if (Settings.Secure.getInt(cr, "user_setup_complete", 0) == 0) {
                Settings.Secure.putInt(cr, "user_setup_complete", 1);
            }
        } catch (Throwable t) {
            Log.w(TAG, "Could not set provisioning flags", t);
        }
    }

    private static void maybeShowFirstBootNotification(Context context) {
        try {
            ContentResolver cr = context.getContentResolver();
            if (Settings.Global.getInt(cr, KEY_WELCOME_SHOWN, 0) == 1) {
                return;
            }
            NotificationManager nm = context.getSystemService(NotificationManager.class);
            if (nm == null) return;

            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID,
                    "XT Debug Status",
                    NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("System optimization and first-boot setup alerts");
            nm.createNotificationChannel(ch);

            boolean done = AnrGuardEngine.isOnboardingCompleted(context);
            Intent launch = new Intent(context, done ? DebugActivity.class : XtWelcomeActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

            Notification n = new Notification.Builder(context, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle("Welcome to XT-Series OS")
                    .setContentText("Tap to configure ZRAM swap (2/4/6 GB), 4G VoLTE, and ANR protection.")
                    .setFullScreenIntent(pi, true)
                    .setContentIntent(pi)
                    .setAutoCancel(true)
                    .build();

            nm.notify(9611, n);
            Settings.Global.putInt(cr, KEY_WELCOME_SHOWN, 1);
        } catch (Throwable t) {
            Log.w(TAG, "Failed to post notification", t);
        }
    }
}
