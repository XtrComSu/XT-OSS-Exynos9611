// SPDX-License-Identifier: Apache-2.0
package os.xt.themes;

import android.app.Activity;
import android.content.om.OverlayInfo;
import android.content.om.OverlayManager;
import android.os.Bundle;
import android.os.UserHandle;
import android.util.Log;
import android.view.View;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.TextView;
import android.widget.Toast;

import java.util.List;

/**
 * Theme switcher for XT-OS.
 *
 * <p>Switches between the four RRO overlays via {@link OverlayManager}. There is no
 * theme code here on purpose — if this activity fails, whatever overlay is currently
 * enabled stays enabled and the device is unaffected.
 *
 * <p><b>Why OverlayManager and not {@code Runtime.exec("cmd overlay ...")}:</b> an
 * app cannot usefully exec {@code cmd} — {@code cmd} runs as the shell user and the
 * app's SELinux domain cannot transition to it, so the call fails with a permission
 * error on a real device even though it looks fine in tests that run as root. Since
 * this app is platform-signed with {@code platform_apis} and
 * {@code CHANGE_OVERLAY_PACKAGES} is a signature permission, the API path is both
 * correct and available. Using the API also means the change is atomic from the
 * system's point of view and is reflected in {@link OverlayManager#getOverlayInfosForTarget}.
 */
public class ThemeActivity extends Activity {

    private static final String TAG = "XtThemes";

    /**
     * Shipping default first. Each entry is {overlay package, human label}.
     *
     * <p>Package names must match the {@code package=} attribute in each overlay's
     * AndroidManifest.xml. build/gen-assets.sh cross-checks the two so a rename
     * cannot silently break the switcher.
     */
    private static final String[][] THEMES = {
        { "os.theme.nothing",      "Nothing (default)" },
        { "os.theme.nothinglight", "Nothing Light" },
        { "os.theme.monet",        "Monet / dynamic" },
        { "os.theme.stock",        "Stock AOSP" },
    };

    private OverlayManager om;
    private TextView status;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        om = getSystemService(OverlayManager.class);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = (int) (24 * getResources().getDisplayMetrics().density);
        root.setPadding(pad, pad, pad, pad);

        TextView title = new TextView(this);
        title.setText("Theme");
        title.setTextSize(22);
        root.addView(title);

        status = new TextView(this);
        status.setTextSize(14);
        status.setPadding(0, pad / 2, 0, pad);
        root.addView(status);

        for (final String[] theme : THEMES) {
            Button b = new Button(this);
            b.setText(theme[1]);
            b.setOnClickListener(new View.OnClickListener() {
                @Override
                public void onClick(View v) {
                    applyTheme(theme[0], theme[1]);
                }
            });
            root.addView(b);
        }

        setContentView(root);
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshStatus();
    }

    /**
     * Make the chosen overlay the single enabled one.
     *
     * <p>{@code setEnabledExclusiveInCategory} is exactly the operation wanted: it
     * enables the target and disables the others in its category as one transaction.
     * Doing it as N separate {@code setEnabled} calls would leave a window in which
     * two overlays of the same category are enabled, which the system resolves
     * unpredictably.
     */
    private void applyTheme(String pkg, String label) {
        if (om == null) {
            toast("Overlay service unavailable");
            Log.w(TAG, "OverlayManager is null — is this a non-privileged install?");
            return;
        }

        try {
            om.setEnabledExclusiveInCategory(pkg, UserHandle.SYSTEM);
            toast(label + " applied");
        } catch (SecurityException e) {
            // Expected if the app was installed without the platform signature —
            // worth surfacing precisely, because the generic message would send
            // someone looking at the overlays instead of the signing config.
            Log.w(TAG, "not permitted to change overlays", e);
            toast("Not permitted — is XtThemes platform-signed?");
        } catch (IllegalArgumentException e) {
            Log.w(TAG, "no such overlay package: " + pkg, e);
            toast("Overlay " + pkg + " not installed");
        } catch (Exception e) {
            Log.w(TAG, "failed to enable " + pkg, e);
            toast("Failed to apply " + label);
        }

        refreshStatus();
    }

    /** Reads which of our overlays are currently enabled and shows them. */
    private void refreshStatus() {
        if (om == null) {
            status.setText("Overlay service unavailable.");
            return;
        }

        StringBuilder enabled = new StringBuilder();
        try {
            List<OverlayInfo> infos = om.getOverlayInfosForTarget("android", UserHandle.SYSTEM);
            for (OverlayInfo info : infos) {
                if (!info.isEnabled()) {
                    continue;
                }
                for (String[] theme : THEMES) {
                    if (theme[0].equals(info.getPackageName())) {
                        if (enabled.length() > 0) {
                            enabled.append(", ");
                        }
                        enabled.append(theme[1]);
                    }
                }
            }
        } catch (Exception e) {
            Log.w(TAG, "could not list overlays", e);
            status.setText("Could not read overlay state.");
            return;
        }

        status.setText(enabled.length() == 0
                ? "No XT theme active — using system defaults."
                : "Active: " + enabled);
    }

    private void toast(String msg) {
        Toast.makeText(this, msg, Toast.LENGTH_SHORT).show();
    }
}
