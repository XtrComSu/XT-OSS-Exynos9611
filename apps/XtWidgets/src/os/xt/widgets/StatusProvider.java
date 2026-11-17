// SPDX-License-Identifier: Apache-2.0
package os.xt.widgets;

import android.appwidget.AppWidgetManager;
import android.appwidget.AppWidgetProvider;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.os.BatteryManager;
import android.widget.RemoteViews;

/**
 * Compact status widget: battery percentage and charging state.
 *
 * <p>Kept intentionally tiny. It reads the battery via a sticky
 * {@link Intent#ACTION_BATTERY_CHANGED} broadcast, which costs nothing — the value
 * is already cached by the system, so this does not register a listener or hold a
 * wake lock.
 *
 * <p>Charging state is shown because on this device charging is the one moment the
 * numbers matter; a static percentage alone tells the user very little.
 */
public class StatusProvider extends AppWidgetProvider {

    @Override
    public void onUpdate(Context context, AppWidgetManager mgr, int[] ids) {
        for (int id : ids) {
            mgr.updateAppWidget(id, buildViews(context));
        }
    }

    private RemoteViews buildViews(Context context) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_status);

        // Sticky broadcast: reading it does not register a receiver, so there is no
        // ongoing cost and nothing to unregister.
        Intent battery = context.registerReceiver(null, new IntentFilter(Intent.ACTION_BATTERY_CHANGED));

        int level = 0;
        int status = BatteryManager.BATTERY_STATUS_UNKNOWN;
        if (battery != null) {
            int scale = battery.getIntExtra(BatteryManager.EXTRA_SCALE, 100);
            int raw = battery.getIntExtra(BatteryManager.EXTRA_LEVEL, 0);
            level = scale > 0 ? Math.round(raw * 100f / scale) : raw;
            status = battery.getIntExtra(BatteryManager.EXTRA_STATUS,
                    BatteryManager.BATTERY_STATUS_UNKNOWN);
        }

        boolean charging = status == BatteryManager.BATTERY_STATUS_CHARGING
                || status == BatteryManager.BATTERY_STATUS_FULL;

        views.setTextViewText(R.id.status_battery, level + "%");
        views.setTextViewText(R.id.status_state, charging ? "charging" : "");
        views.setProgressBar(R.id.status_bar, 100, level, false);

        return views;
    }
}
