// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Activity;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;
import android.widget.Toast;

/**
 * Unified XT-Debug Suite (`os.xt.debug`) — merges all XT-OS utilities into a
 * single privileged app:
 *   Tab 0: ANR & Smoothness Guard (Vivaldi ANR Eliminator, GPU Blur Guard, Anim Scale)
 *   Tab 1: VoLTE & 4G LTE Lab (Force 4G LTE Only, SIM-less VoLTE Trigger, *#*#4636#*#*, Live Cell Info)
 *   Tab 2: Kernel & Memory Monitor (Live /proc/meminfo, ZRAM, PSI stalls, CPU freqs, Top RSS)
 *   Tab 3: Themes & Provisioning (Stock Infinity-X Reset, RRO Theme Switcher, SetupWizard Bypass)
 */
public final class DebugActivity extends Activity {

    private static final long REFRESH_MS = 2000L;
    private final Handler handler = new Handler(Looper.getMainLooper());

    private int activeTab = 0;
    private final Button[] tabButtons = new Button[4];
    private final View[] tabPages = new View[4];

    // Tab 0 widgets
    private Switch swBrowserFix;
    private Switch swVivaldiShield;
    private Switch swSmoothness;
    private TextView tvStatusBadge;
    private TextView tvAnrReport;

    // Tab 1 widgets
    private TextView tvRadioReport;

    // Tab 2 widgets
    private TextView tvKernelReport;

    // Tab 3 widgets
    private TextView tvThemeStatus;

    private final Runnable liveTicker = new Runnable() {
        @Override
        public void run() {
            if (activeTab == 1 && tvRadioReport != null) {
                tvRadioReport.setText(AnrGuardEngine.buildRadioAndImsReport(DebugActivity.this));
            } else if (activeTab == 2 && tvKernelReport != null) {
                tvKernelReport.setText(AnrGuardEngine.buildKernelAndMemoryReport());
            }
            handler.postDelayed(this, REFRESH_MS);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        if (!AnrGuardEngine.isBrowserAnrFixActive(this)) {
            AnrGuardEngine.applyAllDefaults(this);
        }

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.parseColor("#0E1318"));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(18);
        root.setPadding(pad, dp(24), pad, pad);

        // XT-Series Edition Hero Banner Card
        LinearLayout heroCard = new LinearLayout(this);
        heroCard.setOrientation(LinearLayout.VERTICAL);
        heroCard.setPadding(dp(16), dp(14), dp(16), dp(14));
        GradientDrawable heroBg = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                new int[] { Color.parseColor("#172554"), Color.parseColor("#0F172A") });
        heroBg.setCornerRadius(dp(14));
        heroBg.setStroke(dp(1), Color.parseColor("#3B82F6"));
        heroCard.setBackground(heroBg);

        TextView badge = new TextView(this);
        badge.setText("XT-SERIES OS  •  INFINITY-X 4.2  •  ANDROID 17");
        badge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11f);
        badge.setTypeface(Typeface.DEFAULT_BOLD);
        badge.setTextColor(Color.parseColor("#38BDF8"));
        heroCard.addView(badge);

        TextView title = new TextView(this);
        title.setText("XT-Debug System Suite");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 22);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(Color.WHITE);
        title.setPadding(0, dp(2), 0, dp(2));
        heroCard.addView(title);

        TextView subtitle = new TextView(this);
        subtitle.setText("Exynos 9611 • KernelSU-Next v3.4.2 + SuSFS v2.4.0 • VoLTE & 4G LTE • Vivaldi ANR Guard");
        subtitle.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        subtitle.setTextColor(Color.parseColor("#CBD5E1"));
        heroCard.addView(subtitle);

        root.addView(heroCard);
        addSpacer(root, 14);

        // 4-Tab Bar
        LinearLayout tabBar = new LinearLayout(this);
        tabBar.setOrientation(LinearLayout.HORIZONTAL);
        String[] tabNames = { "ANR Guard", "VoLTE & LTE", "Kernel & RAM", "Themes" };
        for (int i = 0; i < 4; i++) {
            final int idx = i;
            Button b = new Button(this);
            b.setText(tabNames[i]);
            b.setAllCaps(false);
            b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
            b.setTypeface(Typeface.DEFAULT_BOLD);
            b.setPadding(dp(6), dp(8), dp(6), dp(8));
            b.setOnClickListener(v -> selectTab(idx));
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
            if (i < 3) lp.setMarginEnd(dp(6));
            tabBar.addView(b, lp);
            tabButtons[i] = b;
        }
        root.addView(tabBar);
        addSpacer(root, 14);

        // Build all 4 tab pages
        tabPages[0] = buildAnrGuardPage();
        tabPages[1] = buildRadioLabPage();
        tabPages[2] = buildKernelRamPage();
        tabPages[3] = buildThemesPage();

        for (View page : tabPages) {
            root.addView(page);
        }

        scroll.addView(root);
        setContentView(scroll);

        selectTab(0);
    }

    @Override
    protected void onResume() {
        super.onResume();
        refreshAllTabs();
        handler.post(liveTicker);
    }

    @Override
    protected void onPause() {
        super.onPause();
        handler.removeCallbacks(liveTicker);
    }

    private void selectTab(int index) {
        activeTab = index;
        for (int i = 0; i < 4; i++) {
            tabPages[i].setVisibility(i == index ? View.VISIBLE : View.GONE);
            GradientDrawable bg = new GradientDrawable();
            bg.setCornerRadius(dp(10));
            if (i == index) {
                bg.setColor(Color.parseColor("#2563EB"));
                tabButtons[i].setTextColor(Color.WHITE);
            } else {
                bg.setColor(Color.parseColor("#1E293B"));
                tabButtons[i].setTextColor(Color.parseColor("#94A3B8"));
            }
            tabButtons[i].setBackground(bg);
        }
        refreshAllTabs();
    }

    private View buildAnrGuardPage() {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);

        tvStatusBadge = new TextView(this);
        tvStatusBadge.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        tvStatusBadge.setTypeface(Typeface.DEFAULT_BOLD);
        tvStatusBadge.setPadding(dp(14), dp(10), dp(14), dp(10));
        page.addView(tvStatusBadge);
        addSpacer(page, 12);

        LinearLayout card1 = makeCard();
        swBrowserFix = addToggleRow(
                card1,
                "Vivaldi & Browser False-ANR Fix",
                "Disables Android 17 Cached Apps Freezer (prevents freezing multi-process Vivaldi/Chromium renderers) + sets Phantom Process limit to 128.",
                AnrGuardEngine.isBrowserAnrFixActive(this),
                (b, c) -> {
                    AnrGuardEngine.applyBrowserAnrFix(this, c);
                    refreshAllTabs();
                });
        page.addView(card1);
        addSpacer(page, 10);

        LinearLayout card2 = makeCard();
        swVivaldiShield = addToggleRow(
                card2,
                "Suppress False ANR Popups (Vivaldi Shield)",
                "Suppresses modal 'App isn't responding' dialogs when heavy browsers briefly exceed the 5s input dispatch window.",
                AnrGuardEngine.isVivaldiDialogShieldActive(this),
                (b, c) -> {
                    AnrGuardEngine.setVivaldiDialogShield(this, c);
                    refreshAllTabs();
                });
        page.addView(card2);
        addSpacer(page, 10);

        LinearLayout card3 = makeCard();
        swSmoothness = addToggleRow(
                card3,
                "Exynos 9611 Smoothness & GPU Guard",
                "Disables heavy SurfaceFlinger window blurs on Mali-G72 MP3 and tunes animation scales to 0.85x.",
                AnrGuardEngine.isSmoothnessFixActive(this),
                (b, c) -> {
                    AnrGuardEngine.applySmoothnessFix(this, c);
                    refreshAllTabs();
                });
        page.addView(card3);
        addSpacer(page, 12);

        // Animation scale quick selector
        LinearLayout animRow = new LinearLayout(this);
        animRow.setOrientation(LinearLayout.HORIZONTAL);
        float[] scales = { 0.5f, 0.85f, 1.0f };
        String[] labels = { "Anim 0.5x (Fast)", "Anim 0.85x (Smooth)", "Anim 1.0x (Stock)" };
        for (int i = 0; i < 3; i++) {
            final float sc = scales[i];
            Button b = makeButton(labels[i], "#1E293B", "#E2E8F0");
            b.setOnClickListener(v -> {
                AnrGuardEngine.setAnimationScale(this, sc);
                Toast.makeText(this, "Animation scale set to " + sc + "x", Toast.LENGTH_SHORT).show();
                refreshAllTabs();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
            if (i < 2) lp.setMarginEnd(dp(6));
            animRow.addView(b, lp);
        }
        page.addView(animRow);
        addSpacer(page, 10);

        LinearLayout btnRow = new LinearLayout(this);
        btnRow.setOrientation(LinearLayout.HORIZONTAL);
        Button btnApplyAll = makeButton("Apply All ANR Fixes", "#00C853", "#000000");
        btnApplyAll.setOnClickListener(v -> {
            AnrGuardEngine.applyAllDefaults(this);
            AnrGuardEngine.setVivaldiDialogShield(this, true);
            Toast.makeText(this, "All Vivaldi & System ANR fixes applied", Toast.LENGTH_SHORT).show();
            refreshAllTabs();
        });
        LinearLayout.LayoutParams lp1 = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        lp1.setMarginEnd(dp(8));
        btnRow.addView(btnApplyAll, lp1);

        Button btnCleanBg = makeButton("Purge CPU Hogs", "#1E293B", "#E2E8F0");
        btnCleanBg.setOnClickListener(v -> {
            AnrGuardEngine.killRunawayHogs(this);
            Toast.makeText(this, "Background runaway tasks purged", Toast.LENGTH_SHORT).show();
            refreshAllTabs();
        });
        LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        btnRow.addView(btnCleanBg, lp2);
        page.addView(btnRow);
        addSpacer(page, 14);

        LinearLayout reportCard = makeCard();
        tvAnrReport = makeMonoTextView();
        reportCard.addView(tvAnrReport);
        page.addView(reportCard);

        return page;
    }

    private View buildRadioLabPage() {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);

        LinearLayout ctrlCard = makeCard();
        TextView hdr = new TextView(this);
        hdr.setText("4G LTE & VoLTE / IMS Controls (SIM & SIM-less)");
        hdr.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        hdr.setTypeface(Typeface.DEFAULT_BOLD);
        hdr.setTextColor(Color.WHITE);
        ctrlCard.addView(hdr);
        addSpacer(ctrlCard, 10);

        LinearLayout row1 = new LinearLayout(this);
        row1.setOrientation(LinearLayout.HORIZONTAL);
        Button btnLteOnly = makeButton("Force 4G LTE Only", "#2563EB", "#FFFFFF");
        btnLteOnly.setOnClickListener(v -> {
            boolean ok = AnrGuardEngine.setPreferredNetworkBitmask(this, AnrGuardEngine.RAF_LTE_ONLY);
            Toast.makeText(this, ok ? "Locked RIL to 4G LTE Only (RAF=4096)" : "Failed to set LTE Only",
                    Toast.LENGTH_SHORT).show();
            refreshAllTabs();
        });
        LinearLayout.LayoutParams lp1 = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        lp1.setMarginEnd(dp(8));
        row1.addView(btnLteOnly, lp1);

        Button btnAutoRat = makeButton("LTE / 3G / 2G Auto", "#1E293B", "#E2E8F0");
        btnAutoRat.setOnClickListener(v -> {
            boolean ok = AnrGuardEngine.setPreferredNetworkBitmask(this, AnrGuardEngine.RAF_LTE_WCDMA_GSM);
            Toast.makeText(this, ok ? "Set RIL to LTE/WCDMA/GSM Auto" : "Failed to set Auto RAT",
                    Toast.LENGTH_SHORT).show();
            refreshAllTabs();
        });
        LinearLayout.LayoutParams lp2 = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        row1.addView(btnAutoRat, lp2);
        ctrlCard.addView(row1);
        addSpacer(ctrlCard, 8);

        LinearLayout row2 = new LinearLayout(this);
        row2.setOrientation(LinearLayout.HORIZONTAL);
        Button btnVolte = makeButton("Trigger VoLTE / IMS Reg", "#00C853", "#000000");
        btnVolte.setOnClickListener(v -> {
            AnrGuardEngine.triggerSimlessVoLteRegistration(this);
            Toast.makeText(this, "Triggered VoLTE/ViLTE/UT IMS Registration", Toast.LENGTH_SHORT).show();
            handler.postDelayed(this::refreshAllTabs, 500);
        });
        row2.addView(btnVolte, lp1);

        Button btnRadioInfo = makeButton("Open *#*#4636#*#* Info", "#1E293B", "#E2E8F0");
        btnRadioInfo.setOnClickListener(v -> AnrGuardEngine.openRadioInfo(this));
        row2.addView(btnRadioInfo, lp2);
        ctrlCard.addView(row2);
        addSpacer(ctrlCard, 8);

        Button btnImsDebug = makeButton("Open Samsung Exynos ImsStack Engineering Menu", "#1E293B", "#93C5FD");
        btnImsDebug.setOnClickListener(v -> AnrGuardEngine.openImsStackConfig(this));
        ctrlCard.addView(btnImsDebug);

        page.addView(ctrlCard);
        addSpacer(page, 12);

        LinearLayout reportCard = makeCard();
        tvRadioReport = makeMonoTextView();
        reportCard.addView(tvRadioReport);
        page.addView(reportCard);

        return page;
    }

    private View buildKernelRamPage() {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);

        LinearLayout reportCard = makeCard();
        tvKernelReport = makeMonoTextView();
        reportCard.addView(tvKernelReport);
        page.addView(reportCard);

        return page;
    }

    private View buildThemesPage() {
        LinearLayout page = new LinearLayout(this);
        page.setOrientation(LinearLayout.VERTICAL);

        LinearLayout card = makeCard();
        TextView hdr = new TextView(this);
        hdr.setText("System Theme & RRO Overlays");
        hdr.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        hdr.setTypeface(Typeface.DEFAULT_BOLD);
        hdr.setTextColor(Color.WHITE);
        card.addView(hdr);

        tvThemeStatus = new TextView(this);
        tvThemeStatus.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tvThemeStatus.setTextColor(Color.parseColor("#4ADE80"));
        tvThemeStatus.setPadding(0, dp(6), 0, dp(12));
        card.addView(tvThemeStatus);

        Button resetBtn = makeButton("Reset to Stock Infinity-X Design (Default)", "#00C853", "#000000");
        resetBtn.setOnClickListener(v -> {
            AnrGuardEngine.resetToStockTheme(this);
            Toast.makeText(this, "Reverted to Stock Infinity-X Design", Toast.LENGTH_SHORT).show();
            refreshAllTabs();
        });
        card.addView(resetBtn);
        addSpacer(card, 10);

        for (final String[] theme : AnrGuardEngine.THEMES) {
            Button b = makeButton(theme[1], "#1E293B", "#E2E8F0");
            b.setOnClickListener(v -> {
                AnrGuardEngine.applyThemeOverlay(this, theme[0]);
                Toast.makeText(this, "Applied " + theme[1], Toast.LENGTH_SHORT).show();
                refreshAllTabs();
            });
            card.addView(b);
            addSpacer(card, 8);
        }

        page.addView(card);
        return page;
    }

    private void refreshAllTabs() {
        boolean browserFix = AnrGuardEngine.isBrowserAnrFixActive(this);
        boolean shield = AnrGuardEngine.isVivaldiDialogShieldActive(this);
        boolean smooth = AnrGuardEngine.isSmoothnessFixActive(this);

        if (swBrowserFix != null) {
            swBrowserFix.setOnCheckedChangeListener(null);
            swVivaldiShield.setOnCheckedChangeListener(null);
            swSmoothness.setOnCheckedChangeListener(null);

            swBrowserFix.setChecked(browserFix);
            swVivaldiShield.setChecked(shield);
            swSmoothness.setChecked(smooth);

            swBrowserFix.setOnCheckedChangeListener((b, c) -> {
                AnrGuardEngine.applyBrowserAnrFix(this, c);
                refreshAllTabs();
            });
            swVivaldiShield.setOnCheckedChangeListener((b, c) -> {
                AnrGuardEngine.setVivaldiDialogShield(this, c);
                refreshAllTabs();
            });
            swSmoothness.setOnCheckedChangeListener((b, c) -> {
                AnrGuardEngine.applySmoothnessFix(this, c);
                refreshAllTabs();
            });
        }

        if (tvStatusBadge != null) {
            GradientDrawable badgeBg = new GradientDrawable();
            badgeBg.setCornerRadius(dp(10));
            if (browserFix) {
                badgeBg.setColor(Color.parseColor("#0D3B26"));
                tvStatusBadge.setTextColor(Color.parseColor("#4ADE80"));
                tvStatusBadge.setText("ACTIVE • Cached App Freezer Disabled & Vivaldi Protected");
            } else {
                badgeBg.setColor(Color.parseColor("#3B1D1D"));
                tvStatusBadge.setTextColor(Color.parseColor("#F87171"));
                tvStatusBadge.setText("WARNING • Cached App Freezer Active (May cause Browser ANRs)");
            }
            tvStatusBadge.setBackground(badgeBg);
        }

        if (tvAnrReport != null) {
            tvAnrReport.setText(AnrGuardEngine.buildLiveReport(this));
        }
        if (tvRadioReport != null) {
            tvRadioReport.setText(AnrGuardEngine.buildRadioAndImsReport(this));
        }
        if (tvKernelReport != null) {
            tvKernelReport.setText(AnrGuardEngine.buildKernelAndMemoryReport());
        }
        if (tvThemeStatus != null) {
            int prov = Settings.Global.getInt(getContentResolver(), Settings.Global.DEVICE_PROVISIONED, 0);
            tvThemeStatus.setText("Active Theme: " + AnrGuardEngine.getActiveThemeSummary(this)
                    + "\nFirst-Boot Provisioned: " + (prov == 1 ? "YES (SetupWizard Bypassed)" : "NO"));
        }
    }

    private LinearLayout makeCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        int p = dp(14);
        card.setPadding(p, p, p, p);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor("#161F29"));
        bg.setCornerRadius(dp(12));
        bg.setStroke(dp(1), Color.parseColor("#243242"));
        card.setBackground(bg);
        return card;
    }

    private TextView makeMonoTextView() {
        TextView tv = new TextView(this);
        tv.setTypeface(Typeface.MONOSPACE);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        tv.setTextColor(Color.parseColor("#CBD5E1"));
        return tv;
    }

    private Switch addToggleRow(
            LinearLayout parent,
            String titleText,
            String descText,
            boolean checked,
            Switch.OnCheckedChangeListener listener) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout textCol = new LinearLayout(this);
        textCol.setOrientation(LinearLayout.VERTICAL);

        TextView t = new TextView(this);
        t.setText(titleText);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14.5f);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(Color.WHITE);
        textCol.addView(t);

        TextView d = new TextView(this);
        d.setText(descText);
        d.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        d.setTextColor(Color.parseColor("#94A3B8"));
        d.setPadding(0, dp(3), dp(10), 0);
        textCol.addView(d);

        LinearLayout.LayoutParams lpText = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        row.addView(textCol, lpText);

        Switch sw = new Switch(this);
        sw.setChecked(checked);
        sw.setOnCheckedChangeListener(listener);
        row.addView(sw);

        parent.addView(row);
        return sw;
    }

    private Button makeButton(String label, String bgColor, String fgColor) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setTextColor(Color.parseColor(fgColor));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor(bgColor));
        bg.setCornerRadius(dp(10));
        b.setBackground(bg);
        b.setPadding(dp(10), dp(9), dp(10), dp(9));
        return b;
    }

    private void addSpacer(LinearLayout parent, int dpHeight) {
        View v = new View(this);
        parent.addView(v, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(dpHeight)));
    }

    private int dp(int val) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, val, getResources().getDisplayMetrics()));
    }
}
