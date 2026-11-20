// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;
import android.widget.Toast;

import java.util.Locale;

/**
 * Direct main screen for XT Debug.
 *
 * <ul>
 *   <li>Plain header with left-aligned {@code "XT Debug"} title ({@code 24sp} semibold)
 *       and an accessible Settings icon button</li>
 *   <li>Core action and live status given primary space (VRAM/ZRAM Swap 2/4/6 GB selector,
 *       4G LTE & VoLTE status with contextual actions, and one-tap optimization apply)</li>
 *   <li>All disk/{@code /proc} reads run off the UI thread for locked 60 Hz frame delivery</li>
 * </ul>
 */
public final class DebugActivity extends Activity {

    private static final long REFRESH_MS = 3000L;
    private final Handler handler = new Handler(Looper.getMainLooper());

    private TextView tvStatusSummary;
    private TextView tvStatusMeta;
    private TextView tvErrorBanner;
    private Button btnApplyMain;

    private final Button[] zramButtons = new Button[3];
    private TextView tvMemoryDetail;

    private final Button[] ratButtons = new Button[2];
    private TextView tvRadioDetail;

    private TextView tvAnrDetail;
    private TextView tvProcessesDetail;

    private boolean isRefreshing = false;

    private final Runnable periodicRefresh = new Runnable() {
        @Override
        public void run() {
            refreshDiagnosticsAsync(false);
            handler.postDelayed(this, REFRESH_MS);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Route first-time users to the single-screen intro; returning users stay here.
        if (!AnrGuardEngine.isOnboardingCompleted(this)) {
            Intent intro = new Intent(this, XtWelcomeActivity.class);
            startActivity(intro);
            finish();
            if (XtDesign.isReducedMotionEnabled(this)) {
                overridePendingTransition(0, 0);
            }
            return;
        }

        XtDesign.configureSystemBars(this);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(XtDesign.COLOR_BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = XtDesign.dp(this, 24);
        XtDesign.applySafeInsetsPadding(root, margin, XtDesign.dp(this, 16), margin, margin);

        // 1. Plain Header: Title ("XT Debug") + Settings Icon Button
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        TextView tvTitle = XtDesign.makeScreenTitle(this, getString(R.string.app_name));
        header.addView(tvTitle, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        ImageButton btnSettings = XtDesign.makeIconButton(
                this, XtDesign.makeSettingsIcon(this), "Settings");
        btnSettings.setOnClickListener(v -> {
            Intent i = new Intent(this, SettingsActivity.class);
            startActivity(i);
            if (XtDesign.isReducedMotionEnabled(this)) {
                overridePendingTransition(0, 0);
            }
        });
        header.addView(btnSettings);

        root.addView(header);
        root.addView(XtDesign.makeSpacer(this, 20));

        // Optional Error State Banner (shown only when an error applies)
        tvErrorBanner = XtDesign.makeBody(this, "", true);
        tvErrorBanner.setTextColor(XtDesign.COLOR_ACCENT_RED);
        tvErrorBanner.setVisibility(View.GONE);
        root.addView(tvErrorBanner);

        // 2. Primary Action & System Readiness Surface (Core workflow given most space)
        LinearLayout primarySurface = XtDesign.makeRaisedSurface(this);

        tvStatusSummary = XtDesign.makeLabel(this, "Loading system status…");
        primarySurface.addView(tvStatusSummary);

        primarySurface.addView(XtDesign.makeSpacer(this, 8));

        tvStatusMeta = XtDesign.makeBody(
                this,
                "Checking ZRAM swap, 4G VoLTE registration, and browser ANR guard.",
                false);
        primarySurface.addView(tvStatusMeta);

        primarySurface.addView(XtDesign.makeSpacer(this, 16));

        btnApplyMain = XtDesign.makePrimaryRedButton(this, "Apply optimizations");
        btnApplyMain.setOnClickListener(v -> applyAllOptimizationsAsync());
        primarySurface.addView(btnApplyMain, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        root.addView(primarySurface);
        root.addView(XtDesign.makeSpacer(this, 28));

        // 3. VRAM / ZRAM Swap Allocation Section (2 GB / 4 GB / 6 GB)
        root.addView(XtDesign.makeSectionHeading(this, "ZRAM SWAP MEMORY"));
        root.addView(XtDesign.makeSpacer(this, 8));

        tvMemoryDetail = XtDesign.makeBody(this, "Reading memory allocation…", true);
        root.addView(tvMemoryDetail);
        root.addView(XtDesign.makeSpacer(this, 12));

        LinearLayout zramRow = new LinearLayout(this);
        zramRow.setOrientation(LinearLayout.HORIZONTAL);
        final int[] zramSizes = { 2, 4, 6 };
        String[] zramLabels = { "2 GB", "4 GB", "6 GB" };
        for (int i = 0; i < 3; i++) {
            final int gb = zramSizes[i];
            Button b = XtDesign.makeSecondaryButton(this, zramLabels[i]);
            b.setOnClickListener(v -> selectZramSize(gb));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
            if (i < 2) lp.setMarginEnd(XtDesign.dp(this, 8));
            zramRow.addView(b, lp);
            zramButtons[i] = b;
        }
        root.addView(zramRow);
        updateZramSelectionButtons(AnrGuardEngine.getSelectedZramGb(this));

        root.addView(XtDesign.makeSpacer(this, 24));
        root.addView(XtDesign.makeDivider(this));
        root.addView(XtDesign.makeSpacer(this, 24));

        // 4. 4G LTE & VoLTE Section (with contextual actions next to the content they affect)
        root.addView(XtDesign.makeSectionHeading(this, "CELLULAR & VOLTE"));
        root.addView(XtDesign.makeSpacer(this, 8));

        tvRadioDetail = XtDesign.makeBody(this, "Reading radio and IMS state…", true);
        root.addView(tvRadioDetail);
        root.addView(XtDesign.makeSpacer(this, 12));

        LinearLayout ratRow = new LinearLayout(this);
        ratRow.setOrientation(LinearLayout.HORIZONTAL);
        String[] ratLabels = { "LTE / 3G / 2G auto", "4G LTE only" };
        final long[] rafMasks = { AnrGuardEngine.RAF_LTE_WCDMA_GSM, AnrGuardEngine.RAF_LTE_ONLY };
        for (int i = 0; i < 2; i++) {
            final int idx = i;
            Button b = XtDesign.makeSecondaryButton(this, ratLabels[i]);
            b.setOnClickListener(v -> selectNetworkMode(rafMasks[idx]));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
            if (i == 0) lp.setMarginEnd(XtDesign.dp(this, 8));
            ratRow.addView(b, lp);
            ratButtons[i] = b;
        }
        root.addView(ratRow);
        updateRatSelectionButtons(
                AnrGuardEngine.getAllowedNetworkBitmask(this) == AnrGuardEngine.RAF_LTE_ONLY);

        root.addView(XtDesign.makeSpacer(this, 10));

        LinearLayout radioActionRow = new LinearLayout(this);
        radioActionRow.setOrientation(LinearLayout.HORIZONTAL);

        Button btnRegisterVolte = XtDesign.makeSecondaryButton(this, "Register VoLTE");
        btnRegisterVolte.setOnClickListener(v -> {
            AnrGuardEngine.runAsync(() -> {
                AnrGuardEngine.triggerSimlessVoLteRegistration(getApplicationContext());
                return Boolean.TRUE;
            }, ok -> {
                Toast.makeText(this, "VoLTE registration requested", Toast.LENGTH_SHORT).show();
                refreshDiagnosticsAsync(true);
            });
        });
        LinearLayout.LayoutParams lpReg = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        lpReg.setMarginEnd(XtDesign.dp(this, 8));
        radioActionRow.addView(btnRegisterVolte, lpReg);

        Button btnOpenRadio = XtDesign.makeSecondaryButton(this, "Open radio info");
        btnOpenRadio.setOnClickListener(v -> {
            if (!AnrGuardEngine.openRadioInfo(this)) {
                Toast.makeText(this, "Could not open RadioInfo screen", Toast.LENGTH_SHORT).show();
            }
        });
        LinearLayout.LayoutParams lpRad = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        radioActionRow.addView(btnOpenRadio, lpRad);

        root.addView(radioActionRow);

        root.addView(XtDesign.makeSpacer(this, 24));
        root.addView(XtDesign.makeDivider(this));
        root.addView(XtDesign.makeSpacer(this, 24));

        // 5. Recent ANR Events & Active Processes (with empty state when zero ANRs)
        root.addView(XtDesign.makeSectionHeading(this, "ANR MONITOR (LAST 24 HOURS)"));
        root.addView(XtDesign.makeSpacer(this, 8));

        tvAnrDetail = XtDesign.makeBody(this, "Checking DropBox ANR log…", false);
        root.addView(tvAnrDetail);

        root.addView(XtDesign.makeSpacer(this, 24));
        root.addView(XtDesign.makeDivider(this));
        root.addView(XtDesign.makeSpacer(this, 24));

        LinearLayout procHeaderRow = new LinearLayout(this);
        procHeaderRow.setOrientation(LinearLayout.HORIZONTAL);
        procHeaderRow.setGravity(Gravity.CENTER_VERTICAL);

        TextView tvProcHdr = XtDesign.makeSectionHeading(this, "TOP MEMORY PROCESSES");
        procHeaderRow.addView(tvProcHdr, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        Button btnRefresh = XtDesign.makeSecondaryButton(this, "Refresh");
        btnRefresh.setOnClickListener(v -> refreshDiagnosticsAsync(true));
        procHeaderRow.addView(btnRefresh);

        root.addView(procHeaderRow);
        root.addView(XtDesign.makeSpacer(this, 8));

        tvProcessesDetail = XtDesign.makeMetadata(this, "Loading process list…");
        root.addView(tvProcessesDetail);

        scroll.addView(root);
        setContentView(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        updateZramSelectionButtons(AnrGuardEngine.getSelectedZramGb(this));
        updateRatSelectionButtons(
                AnrGuardEngine.getAllowedNetworkBitmask(this) == AnrGuardEngine.RAF_LTE_ONLY);
        handler.removeCallbacks(periodicRefresh);
        handler.post(periodicRefresh);
    }

    @Override
    protected void onPause() {
        super.onPause();
        handler.removeCallbacks(periodicRefresh);
    }

    private void selectZramSize(final int gb) {
        updateZramSelectionButtons(gb);
        AnrGuardEngine.runAsync(() -> AnrGuardEngine.setZramSizeGb(getApplicationContext(), gb), ok -> {
            if (Boolean.TRUE.equals(ok)) {
                Toast.makeText(this, "ZRAM swap set to " + gb + " GB", Toast.LENGTH_SHORT).show();
            } else {
                showError("Could not update ZRAM swap size property.");
            }
            refreshDiagnosticsAsync(true);
        });
    }

    private void selectNetworkMode(final long rafMask) {
        final boolean lteOnly = (rafMask == AnrGuardEngine.RAF_LTE_ONLY);
        updateRatSelectionButtons(lteOnly);
        AnrGuardEngine.runAsync(
                () -> AnrGuardEngine.setPreferredNetworkBitmask(getApplicationContext(), rafMask),
                ok -> {
                    if (Boolean.TRUE.equals(ok)) {
                        Toast.makeText(
                                this,
                                lteOnly ? "Locked to 4G LTE only" : "Set to LTE / 3G / 2G auto",
                                Toast.LENGTH_SHORT).show();
                    } else {
                        showError("Could not change preferred network mode.");
                    }
                    refreshDiagnosticsAsync(true);
                });
    }

    private void applyAllOptimizationsAsync() {
        btnApplyMain.setEnabled(false);
        btnApplyMain.setText("Applying…");
        AnrGuardEngine.runAsync(() -> {
            AnrGuardEngine.applyAllDefaults(getApplicationContext());
            AnrGuardEngine.triggerSimlessVoLteRegistration(getApplicationContext());
            return AnrGuardEngine.collectDiagnosticsSync(getApplicationContext());
        }, diag -> {
            btnApplyMain.setEnabled(true);
            btnApplyMain.setText("Apply optimizations");
            Toast.makeText(this, "Optimizations applied", Toast.LENGTH_SHORT).show();
            if (diag != null) {
                bindDiagnostics(diag);
            }
        });
    }

    private void refreshDiagnosticsAsync(boolean force) {
        if (isRefreshing && !force) return;
        isRefreshing = true;
        AnrGuardEngine.runAsync(
                () -> AnrGuardEngine.collectDiagnosticsSync(getApplicationContext()),
                diag -> {
                    isRefreshing = false;
                    if (diag != null) {
                        bindDiagnostics(diag);
                    }
                });
    }

    private void bindDiagnostics(AnrGuardEngine.SystemDiagnostics d) {
        if (d.errorMessage != null && !d.errorMessage.isEmpty()) {
            showError(d.errorMessage);
        } else {
            tvErrorBanner.setVisibility(View.GONE);
        }

        boolean allProtected = d.browserFixActive && d.blurGuardActive;
        tvStatusSummary.setText(allProtected
                ? "System optimizations active"
                : "Optimizations partially disabled");

        tvStatusMeta.setText(String.format(Locale.US,
                "%d GB ZRAM target • %s • Animation %.2fx • Theme: %s",
                d.configuredZramGb,
                d.imsRegistered ? "VoLTE registered" : "VoLTE standby",
                d.animScale,
                AnrGuardEngine.getActiveThemeSummary(this)));

        updateZramSelectionButtons(d.configuredZramGb);
        tvMemoryDetail.setText(String.format(Locale.US,
                "%.1f GB available of %.1f GB RAM  •  %.1f GB ZRAM swap active (%.1f GB used)\n"
                + "CPU: %s (LITTLE) / %s (BIG)  •  Load: %s",
                d.physAvailGb, d.physTotalGb, d.swapTotalGb, d.swapUsedGb,
                d.cpuLittleFreq, d.cpuBigFreq, d.loadAvg));

        updateRatSelectionButtons(d.lteOnlyLocked);
        tvRadioDetail.setText(String.format(Locale.US,
                "IMS: %s  •  SIM: %s\n"
                + "Service: %s  •  RAT: %s",
                d.imsRegistered ? "Registered (VoLTE + ViLTE + UT)" : "Standby",
                d.simState,
                d.serviceState,
                d.radioRat));

        if (d.recentAnrCount == 0) {
            tvAnrDetail.setText(
                    "No application not responding (ANR) events recorded in the last 24 hours. "
                    + "Cached apps freezer is " + (d.browserFixActive ? "disabled." : "enabled."));
        } else {
            tvAnrDetail.setText(d.recentAnrCount + " ANR event(s) in the last 24 hours:\n" + d.recentAnrSummary);
        }

        if (d.topProcessSummary == null || d.topProcessSummary.isEmpty()) {
            tvProcessesDetail.setText("No process memory entries available.");
        } else {
            tvProcessesDetail.setText(d.topProcessSummary);
        }
    }

    private void updateZramSelectionButtons(int selectedGb) {
        int[] sizes = { 2, 4, 6 };
        for (int i = 0; i < 3; i++) {
            if (zramButtons[i] != null) {
                XtDesign.styleChoiceButton(this, zramButtons[i], sizes[i] == selectedGb);
            }
        }
    }

    private void updateRatSelectionButtons(boolean lteOnly) {
        if (ratButtons[0] != null && ratButtons[1] != null) {
            XtDesign.styleChoiceButton(this, ratButtons[0], !lteOnly);
            XtDesign.styleChoiceButton(this, ratButtons[1], lteOnly);
        }
    }

    private void showError(String msg) {
        tvErrorBanner.setText(msg);
        tvErrorBanner.setPadding(0, 0, 0, XtDesign.dp(this, 12));
        tvErrorBanner.setVisibility(View.VISIBLE);
    }
}
