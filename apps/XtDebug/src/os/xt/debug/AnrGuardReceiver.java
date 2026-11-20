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
 * First-boot provisioner & automatic ANR Guard + VoLTE initializer for XT-Series OS.
 *
 * <p>Replaces XtThemes' BootReceiver and ensures that after a clean wipe:
 * <ol>
 *   <li>{@code device_provisioned=1} and {@code user_setup_complete=1} are set
 *       so home navigation, recents, and Quick Settings work immediately
 *       without Google's crashing Pixel SetupWizard.</li>
 *   <li>All Vivaldi / Browser ANR Guard & Exynos 9611 smoothness defaults are
 *       applied automatically at boot.</li>
 *   <li>VoLTE / 4G LTE IMS registration is triggered automatically.</li>
 *   <li>A custom XT-Series First-Boot Welcome notification greets the user on
 *       first boot.</li>
 * </ol>
 */
public final class AnrGuardReceiver extends BroadcastReceiver {
    private static final String TAG = "XtDebugBoot";
    private static final String CHANNEL_ID = "xt_series_welcome";
    private static final String KEY_WELCOME_SHOWN = "xt_series_welcome_shown";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (intent == null || intent.getAction() == null) return;
        Log.i(TAG, "Boot broadcast received (" + intent.getAction() + ") — provisioning & applying XT-Series defaults");
        ensureDeviceProvisioned(context);
        AnrGuardEngine.applyAllDefaults(context);
        AnrGuardEngine.triggerSimlessVoLteRegistration(context);
        if (Intent.ACTION_BOOT_COMPLETED.equals(intent.getAction())) {
            maybeShowFirstBootWelcome(context);
        }
    }

    public static void ensureDeviceProvisioned(Context context) {
        try {
            ContentResolver cr = context.getContentResolver();
            if (Settings.Global.getInt(cr, Settings.Global.DEVICE_PROVISIONED, 0) == 0) {
                Settings.Global.putInt(cr, Settings.Global.DEVICE_PROVISIONED, 1);
                Log.i(TAG, "Marked device_provisioned=1");
            }
            if (Settings.Secure.getInt(cr, "user_setup_complete", 0) == 0) {
                Settings.Secure.putInt(cr, "user_setup_complete", 1);
                Log.i(TAG, "Marked user_setup_complete=1");
            }
        } catch (Throwable t) {
            Log.w(TAG, "Could not set provisioning flags", t);
        }
    }

    private static void maybeShowFirstBootWelcome(Context context) {
        try {
            ContentResolver cr = context.getContentResolver();
            if (Settings.Global.getInt(cr, KEY_WELCOME_SHOWN, 0) == 1) {
                return;
            }
            NotificationManager nm = context.getSystemService(NotificationManager.class);
            if (nm == null) return;

            NotificationChannel ch = new NotificationChannel(
                    CHANNEL_ID,
                    "XT-Series System Status",
                    NotificationManager.IMPORTANCE_HIGH);
            ch.setDescription("XT-Series OS first-boot and system readiness alerts");
            nm.createNotificationChannel(ch);

            Intent launch = new Intent(context, DebugActivity.class);
            launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK | Intent.FLAG_ACTIVITY_CLEAR_TOP);
            PendingIntent pi = PendingIntent.getActivity(
                    context, 0, launch,
                    PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);

            Notification n = new Notification.Builder(context, CHANNEL_ID)
                    .setSmallIcon(android.R.drawable.ic_dialog_info)
                    .setContentTitle("Welcome to XT-Series OS • Infinity-X 4.2")
                    .setContentText("KernelSU-Next v3.4.2 • SuSFS v2.4.0 • VoLTE & Vivaldi ANR Guard Active")
                    .setStyle(new Notification.BigTextStyle().bigText(
                            "XT-Series First-Boot Tuning Complete:\n"
                            + "• KernelSU-Next v3.4.2 + SuSFS v2.4.0 Active\n"
                            + "• VoLTE & 4G LTE Radio Stack Initialized\n"
                            + "• Vivaldi False-ANR & Exynos 9611 GPU Guard Enabled\n"
                            + "Tap to open XT-Debug System Suite."))
                    .setContentIntent(pi)
                    .setAutoCancel(true)
                    .build();

            nm.notify(9611, n);
            Settings.Global.putInt(cr, KEY_WELCOME_SHOWN, 1);
        } catch (Throwable t) {
            Log.w(TAG, "Failed to post XT-Series welcome notification", t);
        }
    }
}
