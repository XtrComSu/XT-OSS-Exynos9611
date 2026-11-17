// SPDX-License-Identifier: Apache-2.0
package os.xt.widgets;

import android.appwidget.AppWidgetManager;
import android.app.AlarmManager;
import android.app.PendingIntent;
import android.appwidget.AppWidgetProvider;
import android.content.ComponentName;
import android.content.Context;
import android.content.Intent;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.os.Bundle;
import android.text.format.DateFormat;
import android.widget.RemoteViews;

import java.util.Calendar;
import java.util.Locale;

/**
 * Dot-matrix clock widget.
 *
 * <p>Draws the time as a grid of dots — the signature Nothing visual — using
 * nothing but {@link Canvas} and {@link Paint}. No fonts, no bitmaps, no external
 * assets: the glyphs are defined below as bit patterns, so there is no font
 * licensing question and the widget renders identically at any density.
 *
 * <p><b>Why RemoteViews with a bitmap rather than a canvas-backed view:</b> a
 * home-screen widget lives in the launcher's process. It cannot host a custom
 * {@code View} class, so it must be described as RemoteViews. RemoteViews cannot
 * draw arbitrary graphics, so the dot grid is rendered to a Bitmap here and
 * handed over as an ImageView source. That is the standard approach for any
 * graphics-heavy widget.
 *
 * <p><b>Update cadence:</b> widgets cannot tick every second without waking the
 * device constantly, which is exactly the kind of idle cost this ROM exists to
 * avoid. The widget therefore updates once a minute while visible, driven by the
 * launcher's updatePeriodMillis. Minutes are the finest granularity it shows.
 */
public class DotClockProvider extends AppWidgetProvider {

    /** 3x5 dot-matrix glyphs. Each string is a row; '#' is a lit dot. */
    private static final String[][] GLYPHS = {
        // 0
        { "###", "#.#", "#.#", "#.#", "###" },
        // 1
        { "..#", "..#", "..#", "..#", "..#" },
        // 2
        { "###", "..#", "###", "#..", "###" },
        // 3
        { "###", "..#", "###", "..#", "###" },
        // 4
        { "#.#", "#.#", "###", "..#", "..#" },
        // 5
        { "###", "#..", "###", "..#", "###" },
        // 6
        { "###", "#..", "###", "#.#", "###" },
        // 7
        { "###", "..#", "..#", "..#", "..#" },
        // 8
        { "###", "#.#", "###", "#.#", "###" },
        // 9
        { "###", "#.#", "###", "..#", "###" },
    };

    /** Colon between hours and minutes: two dots, vertically centred. */
    private static final String[] COLON = { ".", "#", ".", "#", "." };

    private static final int ROWS = 5;

    @Override
    public void onUpdate(Context context, AppWidgetManager mgr, int[] ids) {
        for (int id : ids) {
            mgr.updateAppWidget(id, buildViews(context, id));
        }
        // updatePeriodMillis in the widget info is the launcher's own minimum
        // (30 min). That is far too coarse for a clock, so we drive a precise
        // once-a-minute update ourselves and let the alarm repeat.
        scheduleTick(context);
    }

    @Override
    public void onEnabled(Context context) {
        super.onEnabled(context);
        scheduleTick(context);
    }

    @Override
    public void onDisabled(Context context) {
        super.onDisabled(context);
        AlarmManager am = context.getSystemService(AlarmManager.class);
        if (am != null) {
            am.cancel(tickIntent(context));
        }
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        // A broadcast from our own alarm: redraw, then schedule the next minute.
        if (ACTION_TICK.equals(intent.getAction())) {
            AppWidgetManager mgr = AppWidgetManager.getInstance(context);
            int[] ids = mgr.getAppWidgetIds(
                    new ComponentName(context, DotClockProvider.class));
            for (int id : ids) {
                mgr.updateAppWidget(id, buildViews(context, id));
            }
            scheduleTick(context);
            return;
        }
        super.onReceive(context, intent);
    }

    private static final String ACTION_TICK = "os.xt.widgets.CLOCK_TICK";

    private PendingIntent tickIntent(Context context) {
        Intent i = new Intent(context, DotClockProvider.class);
        i.setAction(ACTION_TICK);
        return PendingIntent.getBroadcast(context, 0, i,
                PendingIntent.FLAG_UPDATE_CURRENT | PendingIntent.FLAG_IMMUTABLE);
    }

    /**
     * Schedules the next redraw at the top of the next minute.
     *
     * <p>Aligned to the minute boundary rather than "60 seconds from now", so the
     * clock never drifts behind the system clock. {@code setExact} would be more
     * precise but needs SCHEDULE_EXACT_ALARM and wakes the device even in Doze;
     * {@code setAndAllowWhileIdle} is the right trade here — a clock widget being
     * up to a minute stale in deep idle is acceptable, being woken exactly is not.
     */
    private void scheduleTick(Context context) {
        AlarmManager am = context.getSystemService(AlarmManager.class);
        if (am == null) {
            return;
        }

        long now = System.currentTimeMillis();
        long nextMinute = now + (60_000L - (now % 60_000L)) + 250L;

        try {
            am.setAndAllowWhileIdle(AlarmManager.RTC, nextMinute, tickIntent(context));
        } catch (SecurityException e) {
            // Some builds restrict even inexact alarms; a stale clock is a far
            // better outcome than a crash in onUpdate.
            android.util.Log.w("XtWidgets", "could not schedule clock tick", e);
        }
    }

    @Override
    public void onAppWidgetOptionsChanged(Context context, AppWidgetManager mgr,
                                         int id, Bundle newOptions) {
        // Re-render at the new size rather than letting the bitmap stretch.
        mgr.updateAppWidget(id, buildViews(context, id));
    }

    private RemoteViews buildViews(Context context, int widgetId) {
        RemoteViews views = new RemoteViews(context.getPackageName(), R.layout.widget_dot_clock);

        Calendar now = Calendar.getInstance();
        int hour = now.get(Calendar.HOUR_OF_DAY);
        int minute = now.get(Calendar.MINUTE);

        // Respect the user's 12/24-hour preference; the format character is all we
        // need, and it avoids duplicating the system's locale handling.
        boolean is24 = DateFormat.is24HourFormat(context);
        int displayHour = hour;
        String suffix = "";
        if (!is24) {
            suffix = hour < 12 ? "AM" : "PM";
            displayHour = hour % 12;
            if (displayHour == 0) {
                displayHour = 12;
            }
        }

        String digits = String.format(Locale.US, "%02d:%02d", displayHour, minute);
        views.setImageViewBitmap(R.id.dot_clock_image,
                render(digits, context.getResources().getDisplayMetrics().density, suffix));
        views.setTextViewText(R.id.dot_clock_suffix, suffix);

        // Tapping the clock opens the system clock app.
        Intent launch = new Intent(Intent.ACTION_MAIN);
        launch.setClassName("com.android.deskclock", "com.android.deskclock.DeskClock");
        launch.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        views.setOnClickPendingIntent(R.id.dot_clock_root,
                android.app.PendingIntent.getActivity(context, 0, launch,
                        android.app.PendingIntent.FLAG_IMMUTABLE));

        return views;
    }

    /** Draws "HH:MM" as a dot grid into a bitmap. */
    private android.graphics.Bitmap render(String text, float density, String suffix) {
        int dot = Math.max(3, Math.round(4 * density));
        int gap = Math.max(2, Math.round(2 * density));
        int cell = dot + gap;

        // Width: every glyph is 3 dots, plus 1 dot of letterspacing between them,
        // plus the colon which is 1 dot wide.
        int glyphW = 3;
        int advance = glyphW + 1;

        int totalCells = 0;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            if (c == ':') {
                totalCells += 1 + 1;
            } else {
                totalCells += advance;
            }
        }
        totalCells = Math.max(1, totalCells - 1);

        int w = totalCells * cell + gap;
        int h = ROWS * cell + gap;

        android.graphics.Bitmap bmp = android.graphics.Bitmap.createBitmap(
                Math.max(w, 1), Math.max(h, 1), android.graphics.Bitmap.Config.ARGB_8888);
        Canvas canvas = new Canvas(bmp);
        canvas.drawColor(Color.TRANSPARENT);

        Paint p = new Paint(Paint.ANTI_ALIAS_FLAG);
        p.setColor(Color.WHITE); // tinted by the ImageView's tint, so theme-aware
        p.setStyle(Paint.Style.FILL);

        int x = gap;
        for (int i = 0; i < text.length(); i++) {
            char c = text.charAt(i);
            String[] glyph;
            int gw;
            if (c == ':') {
                glyph = COLON;
                gw = 1;
            } else {
                int d = c - '0';
                if (d < 0 || d >= GLYPHS.length) {
                    x += advance * cell;
                    continue;
                }
                glyph = GLYPHS[d];
                gw = glyphW;
            }

            for (int r = 0; r < ROWS; r++) {
                String row = glyph[r];
                for (int col = 0; col < gw; col++) {
                    if (col < row.length() && row.charAt(col) == '#') {
                        float cx = x + col * cell;
                        float cy = gap + r * cell;
                        canvas.drawCircle(cx + dot / 2f, cy + dot / 2f, dot / 2f, p);
                    }
                }
            }
            x += (gw + 1) * cell;
        }

        return bmp;
    }
}
