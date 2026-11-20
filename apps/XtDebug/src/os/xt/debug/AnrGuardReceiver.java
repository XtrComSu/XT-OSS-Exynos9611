// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Notification;
import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.app.PendingIntent;
import android.content.BroadcastReceiver;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.provider.Settings;
import android.util.Log;

/**
 * Boot receiver for XT Debug:
 * <ul>
 *   <li>Ensures {@code device_provisioned=1} and {@code user_setup_complete=1}</li>
 *   <li>Applies saved ZRAM swap, VoLTE, and browser ANR guard preferences</li>
 *   <li>Launches {@link XtWelcomeActivity} on first boot if onboarding has not been completed</li>
 * </ul>
 */
public final class AnrGuardReceiver extends BroadcastReceiver {
    private static final String TAG = "XtDebugBoot";
    private static final String CHANNEL_ID = "xt_debug_status";
    private static final String KEY_WELCOME_SHOWN = "xt_series_welcome_shown";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) return;
        Log.i(TAG, "Boot broadcast received (" + intent.getAction() + ")");
        final PendingResult pending = goAsync();
        AnrGuardEngine.runAsync(() -> {
            ensureDeviceProvisioned(context);
            AnrGuardEngine.applyAllDefaults(context);
            if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
                maybeShowFirstBootNotification(context);
                maybeLaunchFirstBootIntro(context);
            }
            return Boolean.TRUE;
        }, res -> pending.finish());
    }

    private static void maybeLaunchFirstBootIntro(Context context) {
        try {
            if (AnrGuardEngine.isOnboardingCompleted(context)) {
                return;
            }
            Intent wiz = new Intent(context, XtWelcomeActivity.class);
            wiz.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            context.startActivity(wiz);
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
                    NotificationManager.IMPORTANCE_DEFAULT);
            ch.setDescription("System optimization status notifications");
            nm.createNotificationChannel(ch);

            Intent launch = new Intent(context, DebugActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

            Notification n = new Notification.Builder(context, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle("XT Debug active")
                    .setContentText("ZRAM swap, 4G VoLTE, and browser ANR guard configured.")
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
