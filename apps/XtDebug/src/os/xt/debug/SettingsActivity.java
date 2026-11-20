// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.Intent;
import android.content.res.ColorStateList;
import android.os.Bundle;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.ImageButton;
import android.widget.ImageView;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

import java.util.Locale;

/**
 * Flat settings list for XT Debug:
 * <ul>
 *   <li>Back button + {@code "Settings"} title ({@code 24sp}, semibold)</li>
 *   <li>One row per preference ({@code 48dp+} minimum height, grows with text scale)</li>
 *   <li>Native {@link Switch} for immediate on/off preferences</li>
 *   <li>Trailing value for multi-choice preferences</li>
 *   <li>Trailing chevron for rows that open another screen</li>
 * </ul>
 */
public final class SettingsActivity extends Activity {

    private TextView tvZramValue;
    private Switch swBrowserAnr;
    private Switch swModalShield;
    private Switch swBlurGuard;
    private TextView tvAnimValue;

    private TextView tvNetworkModeValue;
    private Switch swAutoVolte;

    private TextView tvThemeValue;
    private TextView tvFontValue;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        XtDesign.configureSystemBars(this);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(XtDesign.COLOR_BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = XtDesign.dp(this, 24);
        XtDesign.applySafeInsetsPadding(root, margin, XtDesign.dp(this, 16), margin, margin);

        // Header: Back Button + "Settings" Title
        LinearLayout header = new LinearLayout(this);
        header.setOrientation(LinearLayout.HORIZONTAL);
        header.setGravity(Gravity.CENTER_VERTICAL);

        ImageButton btnBack = XtDesign.makeIconButton(
                this, XtDesign.makeBackArrowIcon(this), "Navigate up");
        LinearLayout.LayoutParams lpBack = (LinearLayout.LayoutParams) btnBack.getLayoutParams();
        lpBack.setMarginStart(-XtDesign.dp(this, 12));
        lpBack.setMarginEnd(XtDesign.dp(this, 8));
        btnBack.setLayoutParams(lpBack);
        btnBack.setOnClickListener(v -> finishSettings());
        header.addView(btnBack);

        TextView tvTitle = XtDesign.makeScreenTitle(this, "Settings");
        header.addView(tvTitle);

        root.addView(header);
        root.addView(XtDesign.makeSpacer(this, 24));

        // =====================================================================
        // Section 1: Memory & Performance
        // =====================================================================
        root.addView(XtDesign.makeSectionHeading(this, "MEMORY & PERFORMANCE"));
        root.addView(XtDesign.makeSpacer(this, 8));
        root.addView(XtDesign.makeDivider(this));

        tvZramValue = addChoiceRow(
                root,
                "ZRAM swap size",
                "Compressed RAM swap allocation",
                "",
                this::showZramDialog);

        swBrowserAnr = addSwitchRow(
                root,
                "Browser ANR protection",
                "Disable cached apps freezer and allow 128 phantom processes",
                AnrGuardEngine.isBrowserAnrFixActive(this),
                enabled -> AnrGuardEngine.runAsync(
                        () -> AnrGuardEngine.applyBrowserAnrFix(getApplicationContext(), enabled),
                        ok -> {}));

        swModalShield = addSwitchRow(
                root,
                "Suppress background ANR dialogs",
                "Hide modal 'App isn't responding' popups during heavy loads",
                AnrGuardEngine.isVivaldiDialogShieldActive(this),
                enabled -> AnrGuardEngine.runAsync(
                        () -> AnrGuardEngine.setVivaldiDialogShield(getApplicationContext(), enabled),
                        ok -> {}));

        swBlurGuard = addSwitchRow(
                root,
                "Disable window blurs",
                "Turn off SurfaceFlinger blurs for steady 60 Hz frame delivery",
                AnrGuardEngine.isSmoothnessFixActive(this),
                enabled -> AnrGuardEngine.runAsync(
                        () -> AnrGuardEngine.applySmoothnessFix(getApplicationContext(), enabled),
                        ok -> {}));

        tvAnimValue = addChoiceRow(
                root,
                "Animation speed",
                null,
                "",
                this::showAnimationSpeedDialog);

        addActionRow(
                root,
                "Stop runaway background processes",
                "Terminate known CPU hog processes",
                () -> AnrGuardEngine.runAsync(
                        () -> AnrGuardEngine.killRunawayHogs(getApplicationContext()),
                        count -> Toast.makeText(
                                this, "Stopped runaway background tasks", Toast.LENGTH_SHORT).show()));

        root.addView(XtDesign.makeSpacer(this, 28));

        // =====================================================================
        // Section 2: Cellular & VoLTE
        // =====================================================================
        root.addView(XtDesign.makeSectionHeading(this, "CELLULAR & VOLTE"));
        root.addView(XtDesign.makeSpacer(this, 8));
        root.addView(XtDesign.makeDivider(this));

        tvNetworkModeValue = addChoiceRow(
                root,
                "Preferred network mode",
                null,
                "",
                this::showNetworkModeDialog);

        swAutoVolte = addSwitchRow(
                root,
                "Auto-register VoLTE on boot",
                "Provision MMTEL VoLTE, ViLTE, and UT at startup",
                AnrGuardEngine.isAutoVolteEnabled(this),
                enabled -> AnrGuardEngine.runAsync(() -> {
                    AnrGuardEngine.setAutoVolteEnabled(getApplicationContext(), enabled);
                    return Boolean.TRUE;
                }, ok -> {}));

        addNavigationRow(
                root,
                "Radio information",
                "Open *#*#4636#*#* phone testing screen",
                () -> {
                    if (!AnrGuardEngine.openRadioInfo(this)) {
                        Toast.makeText(this, "Could not open RadioInfo", Toast.LENGTH_SHORT).show();
                    }
                });

        addNavigationRow(
                root,
                "IMS engineering settings",
                "Open Samsung Exynos ImsStack configuration",
                () -> {
                    if (!AnrGuardEngine.openImsStackConfig(this)) {
                        Toast.makeText(this, "Could not open IMS settings", Toast.LENGTH_SHORT).show();
                    }
                });

        root.addView(XtDesign.makeSpacer(this, 28));

        // =====================================================================
        // Section 3: Appearance & System
        // =====================================================================
        root.addView(XtDesign.makeSectionHeading(this, "APPEARANCE & SYSTEM"));
        root.addView(XtDesign.makeSpacer(this, 8));
        root.addView(XtDesign.makeDivider(this));

        tvThemeValue = addChoiceRow(
                root,
                "System theme",
                null,
                "",
                this::showThemeDialog);

        tvFontValue = addChoiceRow(
                root,
                "System font",
                null,
                "",
                this::showFontDialog);

        addNavigationRow(
                root,
                "Dolby Atmos audio",
                null,
                () -> {
                    if (!AnrGuardEngine.openDolbyAtmos(this)) {
                        Toast.makeText(this, "Dolby Atmos unavailable", Toast.LENGTH_SHORT).show();
                    }
                });

        addNavigationRow(
                root,
                "Ambient display",
                null,
                () -> {
                    if (!AnrGuardEngine.openSamsungDoze(this)) {
                        Toast.makeText(this, "Ambient display settings unavailable", Toast.LENGTH_SHORT).show();
                    }
                });

        addNavigationRow(
                root,
                "Welcome screen",
                "Open the first-launch introduction screen",
                () -> {
                    Intent i = new Intent(this, XtWelcomeActivity.class);
                    i.putExtra(XtWelcomeActivity.EXTRA_FROM_SETTINGS, true);
                    startActivity(i);
                    if (XtDesign.isReducedMotionEnabled(this)) {
                        overridePendingTransition(0, 0);
                    }
                });

        scroll.addView(root);
        setContentView(scroll);
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshValues();
    }

    @Override
    public void onBackPressed() {
        finishSettings();
    }

    private void finishSettings() {
        finish();
        if (XtDesign.isReducedMotionEnabled(this)) {
            overridePendingTransition(0, 0);
        }
    }

    private void refreshValues() {
        int zramGb = AnrGuardEngine.getSelectedZramGb(this);
        tvZramValue.setText(zramGb + " GB");

        swBrowserAnr.setChecked(AnrGuardEngine.isBrowserAnrFixActive(this));
        swModalShield.setChecked(AnrGuardEngine.isVivaldiDialogShieldActive(this));
        swBlurGuard.setChecked(AnrGuardEngine.isSmoothnessFixActive(this));

        float anim = AnrGuardEngine.getAnimationScale(this);
        tvAnimValue.setText(String.format(Locale.US, "%.2fx", anim));

        boolean lteOnly = AnrGuardEngine.getAllowedNetworkBitmask(this) == AnrGuardEngine.RAF_LTE_ONLY;
        tvNetworkModeValue.setText(lteOnly ? "4G LTE only" : "LTE / 3G / 2G auto");

        swAutoVolte.setChecked(AnrGuardEngine.isAutoVolteEnabled(this));
        tvThemeValue.setText(AnrGuardEngine.getActiveThemeSummary(this));
        tvFontValue.setText(AnrGuardEngine.getActiveFontSummary(this));
    }

    // =========================================================================
    // Dialog Pickers (Preserving preference values across restarts)
    // =========================================================================

    private void showZramDialog() {
        final String[] labels = { "2 GB", "4 GB", "6 GB" };
        final int[] values = { 2, 4, 6 };
        int current = AnrGuardEngine.getSelectedZramGb(this);
        int checked = current == 2 ? 0 : (current == 6 ? 2 : 1);

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("ZRAM swap size")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    final int gb = values[which];
                    dialog.dismiss();
                    AnrGuardEngine.runAsync(
                            () -> AnrGuardEngine.setZramSizeGb(getApplicationContext(), gb),
                            ok -> refreshValues());
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showAnimationSpeedDialog() {
        final String[] labels = { "0.5x (Fast)", "0.85x (Recommended)", "1.0x (Standard)" };
        final float[] values = { 0.5f, 0.85f, 1.0f };
        float cur = AnrGuardEngine.getAnimationScale(this);
        int checked = Math.abs(cur - 0.5f) < 0.08f ? 0 : (Math.abs(cur - 0.85f) < 0.08f ? 1 : 2);

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Animation speed")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    final float sc = values[which];
                    dialog.dismiss();
                    AnrGuardEngine.runAsync(
                            () -> AnrGuardEngine.setAnimationScale(getApplicationContext(), sc),
                            ok -> refreshValues());
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showNetworkModeDialog() {
        final String[] labels = { "LTE / 3G / 2G auto", "4G LTE only" };
        final long[] values = { AnrGuardEngine.RAF_LTE_WCDMA_GSM, AnrGuardEngine.RAF_LTE_ONLY };
        boolean lteOnly = AnrGuardEngine.getAllowedNetworkBitmask(this) == AnrGuardEngine.RAF_LTE_ONLY;

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("Preferred network mode")
                .setSingleChoiceItems(labels, lteOnly ? 1 : 0, (dialog, which) -> {
                    final long mask = values[which];
                    dialog.dismiss();
                    AnrGuardEngine.runAsync(
                            () -> AnrGuardEngine.setPreferredNetworkBitmask(getApplicationContext(), mask),
                            ok -> refreshValues());
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showThemeDialog() {
        final int n = AnrGuardEngine.THEMES.length;
        final String[] labels = new String[n];
        String activePkg = AnrGuardEngine.getActiveThemePkg(this);
        int checked = 0;
        for (int i = 0; i < n; i++) {
            labels[i] = AnrGuardEngine.THEMES[i][1];
            if (AnrGuardEngine.THEMES[i][0].equals(activePkg)) checked = i;
        }

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("System theme")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    final String pkg = AnrGuardEngine.THEMES[which][0];
                    dialog.dismiss();
                    AnrGuardEngine.runAsync(
                            () -> AnrGuardEngine.applyThemeOverlay(getApplicationContext(), pkg),
                            ok -> refreshValues());
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    private void showFontDialog() {
        final int n = AnrGuardEngine.FONTS.length;
        final String[] labels = new String[n];
        String activePkg = AnrGuardEngine.getActiveFontPkg(this);
        int checked = 0;
        for (int i = 0; i < n; i++) {
            labels[i] = AnrGuardEngine.FONTS[i][1];
            String fPkg = AnrGuardEngine.FONTS[i][0];
            if ((activePkg == null && fPkg == null) || (activePkg != null && activePkg.equals(fPkg))) {
                checked = i;
            }
        }

        new AlertDialog.Builder(this, android.R.style.Theme_DeviceDefault_Dialog_Alert)
                .setTitle("System font")
                .setSingleChoiceItems(labels, checked, (dialog, which) -> {
                    final String pkg = AnrGuardEngine.FONTS[which][0];
                    dialog.dismiss();
                    AnrGuardEngine.runAsync(
                            () -> AnrGuardEngine.applyFontOverlay(getApplicationContext(), pkg),
                            ok -> refreshValues());
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    // =========================================================================
    // Flat List Row Builders (48dp+ minHeight, thin #2C2C2C dividers)
    // =========================================================================

    private interface ToggleCallback {
        void onChanged(boolean enabled);
    }

    private Switch addSwitchRow(
            LinearLayout parent,
            String label,
            String description,
            boolean initialChecked,
            final ToggleCallback callback) {
        LinearLayout row = makeBaseRow();
        LinearLayout textCol = makeTextColumn(label, description);
        row.addView(textCol, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        final Switch sw = new Switch(this);
        sw.setChecked(initialChecked);
        styleNativeSwitch(sw);
        sw.setOnCheckedChangeListener((buttonView, isChecked) -> callback.onChanged(isChecked));
        row.setOnClickListener(v -> sw.setChecked(!sw.isChecked()));
        row.addView(sw);

        parent.addView(row);
        parent.addView(XtDesign.makeDivider(this));
        return sw;
    }

    private TextView addChoiceRow(
            LinearLayout parent,
            String label,
            String description,
            String initialValue,
            final Runnable onClick) {
        LinearLayout row = makeBaseRow();
        LinearLayout textCol = makeTextColumn(label, description);
        row.addView(textCol, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        TextView tvValue = XtDesign.makeBody(this, initialValue, false);
        tvValue.setPadding(XtDesign.dp(this, 12), 0, 0, 0);
        row.addView(tvValue);

        row.setOnClickListener(v -> onClick.run());
        parent.addView(row);
        parent.addView(XtDesign.makeDivider(this));
        return tvValue;
    }

    private void addNavigationRow(
            LinearLayout parent,
            String label,
            String description,
            final Runnable onClick) {
        LinearLayout row = makeBaseRow();
        LinearLayout textCol = makeTextColumn(label, description);
        row.addView(textCol, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        ImageView chevron = new ImageView(this);
        chevron.setImageDrawable(XtDesign.makeChevronRightIcon(this));
        chevron.setImportantForAccessibility(View.IMPORTANT_FOR_ACCESSIBILITY_NO);
        LinearLayout.LayoutParams lpChev = new LinearLayout.LayoutParams(
                XtDesign.dp(this, 18), XtDesign.dp(this, 18));
        lpChev.setMarginStart(XtDesign.dp(this, 12));
        row.addView(chevron, lpChev);

        row.setOnClickListener(v -> onClick.run());
        parent.addView(row);
        parent.addView(XtDesign.makeDivider(this));
    }

    private void addActionRow(
            LinearLayout parent,
            String label,
            String description,
            final Runnable onClick) {
        LinearLayout row = makeBaseRow();
        LinearLayout textCol = makeTextColumn(label, description);
        row.addView(textCol, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        row.setOnClickListener(v -> onClick.run());
        parent.addView(row);
        parent.addView(XtDesign.makeDivider(this));
    }

    private LinearLayout makeBaseRow() {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);
        row.setMinimumHeight(XtDesign.dp(this, 52));
        int vPad = XtDesign.dp(this, 12);
        row.setPadding(0, vPad, 0, vPad);
        row.setClickable(true);
        row.setFocusable(true);
        return row;
    }

    private LinearLayout makeTextColumn(String label, String description) {
        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);

        TextView tvLabel = XtDesign.makeLabel(this, label);
        col.addView(tvLabel);

        if (description != null && !description.isEmpty()) {
            TextView tvDesc = XtDesign.makeMetadata(this, description);
            tvDesc.setPadding(0, XtDesign.dp(this, 4), XtDesign.dp(this, 12), 0);
            col.addView(tvDesc);
        }
        return col;
    }

    private void styleNativeSwitch(Switch sw) {
        try {
            int[][] states = new int[][] {
                new int[] { android.R.attr.state_checked },
                new int[] { -android.R.attr.state_checked }
            };
            int[] thumbColors = new int[] {
                XtDesign.COLOR_ACCENT_RED,
                XtDesign.COLOR_TEXT_SECONDARY
            };
            int[] trackColors = new int[] {
                0x66F04444,
                XtDesign.COLOR_DIVIDER
            };
            sw.setThumbTintList(new ColorStateList(states, thumbColors));
            sw.setTrackTintList(new ColorStateList(states, trackColors));
        } catch (Throwable ignored) {}
    }
}
