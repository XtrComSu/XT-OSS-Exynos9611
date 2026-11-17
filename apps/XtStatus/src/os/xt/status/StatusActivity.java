// SPDX-License-Identifier: Apache-2.0
package os.xt.status;

import android.app.Activity;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.util.Log;
import android.widget.ScrollView;
import android.widget.TextView;

import java.io.BufferedReader;
import java.io.FileReader;
import java.io.IOException;

/**
 * Reads real kernel and ART state and shows it.
 *
 * <p>The point of this screen is to make the ROM's efficiency claims falsifiable.
 * It reports {@code MemAvailable} rather than {@code free}, because on Linux
 * "free" memory is mostly cache and is not memory the device can use — the number
 * that matters is how much is available without swapping. Showing "free" would
 * make any device look starved.
 *
 * <p>Nothing here runs in the background: values are sampled while the activity is
 * visible and the handler is removed in {@link #onPause}.
 */
public class StatusActivity extends Activity {

    private static final String TAG = "XtStatus";
    private static final long REFRESH_MS = 2000L;

    private final Handler handler = new Handler(Looper.getMainLooper());
    private TextView readout;

    private final Runnable tick = new Runnable() {
        @Override
        public void run() {
            readout.setText(sample());
            handler.postDelayed(this, REFRESH_MS);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        readout = new TextView(this);
        int pad = (int) (16 * getResources().getDisplayMetrics().density);
        readout.setPadding(pad, pad, pad, pad);
        readout.setTextSize(12);
        readout.setTypeface(android.graphics.Typeface.MONOSPACE);
        scroll.addView(readout);

        setContentView(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        handler.post(tick);
    }

    @Override
    protected void onPause() {
        super.onPause();
        // Removing the callback is the whole cost model of this app: closed means
        // no wakeups at all.
        handler.removeCallbacks(tick);
    }

    /** Builds the whole readout as one string. */
    private String sample() {
        StringBuilder sb = new StringBuilder();

        sb.append("=== MEMORY (kB) ===\n");
        long avail = 0, total = 0;
        for (String line : lines("/proc/meminfo")) {
            if (line.startsWith("MemTotal:")) {
                total = kb(line);
                sb.append("  ").append(line.trim()).append('\n');
            } else if (line.startsWith("MemAvailable:")) {
                avail = kb(line);
                sb.append("  ").append(line.trim()).append('\n');
            } else if (line.startsWith("SwapTotal:") || line.startsWith("SwapFree:")
                    || line.startsWith("Cached:") || line.startsWith("Dirty:")) {
                sb.append("  ").append(line.trim()).append('\n');
            }
        }

        if (total > 0) {
            // MemAvailable is the honest headline: this is what the plan targets
            // when it asks for 3-4 GB usable on a 6 GB device.
            sb.append(String.format("\n  available = %.0f%% of total (%.2f GB free-ish)\n",
                    avail * 100.0 / total, avail / 1024.0 / 1024.0));
            sb.append("  NOTE: 'free' would show far less; cache is reclaimable.\n");
        }

        sb.append("\n=== ZRAM ===\n");
        boolean sawZram = false;
        for (String line : lines("/proc/swaps")) {
            if (line.contains("zram")) {
                sb.append("  ").append(line.trim()).append('\n');
                sawZram = true;
            }
        }
        if (!sawZram) {
            sb.append("  (no zram swap active)\n");
        }

        sb.append("\n=== PRESSURE (PSI) ===\n");
        for (String res : new String[] { "cpu", "memory", "io" }) {
            for (String line : lines("/proc/pressure/" + res)) {
                sb.append("  ").append(line.trim()).append('\n');
            }
        }

        sb.append("\n=== LOAD ===\n");
        for (String line : lines("/proc/loadavg")) {
            sb.append("  ").append(line.trim()).append('\n');
        }

        sb.append("\n=== TOP PROCESSES (rss kB) ===\n");
        sb.append(readTopProcesses());

        sb.append("\n=== BUILD ===\n");
        sb.append("  ").append(android.os.Build.DISPLAY).append('\n');
        sb.append("  ").append(android.os.Build.FINGERPRINT).append('\n');

        return sb.toString();
    }

    /** Sums RSS per process from /proc and lists the ten largest. */
    private String readTopProcesses() {
        java.io.File proc = new java.io.File("/proc");
        String[] pids = proc.list();
        if (pids == null) {
            return "  (unreadable)\n";
        }

        java.util.List<long[]> sizes = new java.util.ArrayList<>();
        java.util.List<String> names = new java.util.ArrayList<>();

        for (String pid : pids) {
            if (pid.isEmpty() || !Character.isDigit(pid.charAt(0))) {
                continue;
            }
            long rssPages = 0;
            String name = pid;
            boolean ok = false;
            for (String line : lines("/proc/" + pid + "/status")) {
                if (line.startsWith("Name:")) {
                    name = line.substring(5).trim();
                } else if (line.startsWith("VmRSS:")) {
                    rssPages = kb(line);
                    ok = true;
                }
            }
            if (ok) {
                sizes.add(new long[] { rssPages, sizes.size() });
                names.add(name);
            }
        }

        // Sort descending by RSS without a comparator allocation per comparison.
        Integer[] order = new Integer[sizes.size()];
        for (int i = 0; i < order.length; i++) {
            order[i] = i;
        }
        java.util.Arrays.sort(order, (a, b) ->
                Long.compare(sizes.get(b)[0], sizes.get(a)[0]));

        StringBuilder sb = new StringBuilder();
        int shown = 0;
        for (int idx : order) {
            if (shown++ >= 10) {
                break;
            }
            sb.append(String.format("  %8d kB  %s%n", sizes.get(idx)[0], names.get(idx)));
        }
        return sb.toString();
    }

    private static long kb(String line) {
        // "MemAvailable:   3145728 kB" -> 3145728
        String[] parts = line.trim().split("\\s+");
        for (String p : parts) {
            try {
                return Long.parseLong(p);
            } catch (NumberFormatException ignored) {
                // not the number, keep looking
            }
        }
        return 0;
    }

    private static java.util.List<String> lines(String path) {
        java.util.List<String> out = new java.util.ArrayList<>();
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            String line;
            while ((line = r.readLine()) != null) {
                out.add(line);
            }
        } catch (IOException e) {
            Log.d(TAG, "cannot read " + path + ": " + e.getMessage());
        }
        return out;
    }
}
