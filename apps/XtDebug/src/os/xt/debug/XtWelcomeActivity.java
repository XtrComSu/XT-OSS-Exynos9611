// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Activity;
import android.content.Intent;
import android.graphics.Color;
import android.graphics.Typeface;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.os.Bundle;
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
 * Full-screen interactive XT-Series First-Boot Experience Wizard.
 *
 * <p>Greets the user on first boot (and can be re-opened any time from XT-Debug)
 * with a 3-stage interactive onboarding flow:
 * <ol>
 *   <li>Stage 0: XT-Series OS Identity, KernelSU-Next v3.4.2 + SuSFS v2.4.0 & Hardware Summary</li>
 *   <li>Stage 1: ZRAM + Swap Memory, Vivaldi ANR Guard, GPU Smoothness & VoLTE/LTE Tuning</li>
 *   <li>Stage 2: Visual Theme Selection (Stock Infinity-X Default, Monet, Nothing Dark/Light) & Launch</li>
 * </ol>
 */
public final class XtWelcomeActivity extends Activity {

    public static final String KEY_FIRST_BOOT_DONE = "xt_first_boot_completed";

    private int step = 0;
    private final View[] stepViews = new View[3];
    private final View[] stepDots = new View[3];
    private Button btnBack;
    private Button btnNext;

    private boolean optZramSwap = true;
    private boolean optAnrGuard = true;
    private boolean optSmoothness = true;
    private boolean optVolteLte = true;
    private String selectedThemePkg = null; // null = Stock Infinity-X default
    private TextView tvSelectedTheme;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(Color.parseColor("#070B10"));

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(22);
        root.setPadding(pad, dp(36), pad, dp(24));

        // Top step indicator dots
        LinearLayout dotsRow = new LinearLayout(this);
        dotsRow.setOrientation(LinearLayout.HORIZONTAL);
        dotsRow.setGravity(Gravity.CENTER_HORIZONTAL);
        for (int i = 0; i < 3; i++) {
            View dot = new View(this);
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(dp(28), dp(6));
            if (i < 2) lp.setMarginEnd(dp(8));
            dotsRow.addView(dot, lp);
            stepDots[i] = dot;
        }
        root.addView(dotsRow);
        addSpacer(root, 22);

        // Build 3 stage views
        stepViews[0] = buildStage0Hero();
        stepViews[1] = buildStage1Tuning();
        stepViews[2] = buildStage2ThemeAndFinish();

        for (View v : stepViews) {
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    ViewGroup.LayoutParams.MATCH_PARENT, 0, 1.0f);
            root.addView(v, lp);
        }

        addSpacer(root, 18);

        // Bottom Navigation Row
        LinearLayout navRow = new LinearLayout(this);
        navRow.setOrientation(LinearLayout.HORIZONTAL);

        btnBack = makeButton("Back", "#1E293B", "#94A3B8");
        btnBack.setOnClickListener(v -> {
            if (step > 0) showStep(step - 1);
        });
        LinearLayout.LayoutParams lpBack = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
        lpBack.setMarginEnd(dp(10));
        navRow.addView(btnBack, lpBack);

        btnNext = makeButton("Configure XT-Series →", "#2563EB", "#FFFFFF");
        btnNext.setOnClickListener(v -> {
            if (step < 2) {
                showStep(step + 1);
            } else {
                completeFirstBootSetup(false);
            }
        });
        LinearLayout.LayoutParams lpNext = new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.8f);
        navRow.addView(btnNext, lpNext);

        root.addView(navRow);
        scroll.addView(root);
        setContentView(scroll);

        showStep(0);
    }

    private View buildStage0Hero() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);
        box.setGravity(Gravity.CENTER_HORIZONTAL);

        // Glowing XT Emblem Circle
        TextView emblem = new TextView(this);
        emblem.setText("XT");
        emblem.setTextSize(TypedValue.COMPLEX_UNIT_SP, 44);
        emblem.setTypeface(Typeface.DEFAULT_BOLD);
        emblem.setTextColor(Color.WHITE);
        emblem.setGravity(Gravity.CENTER);
        GradientDrawable circle = new GradientDrawable(
                GradientDrawable.Orientation.TL_BR,
                new int[] { Color.parseColor("#2563EB"), Color.parseColor("#0EA5E9") });
        circle.setShape(GradientDrawable.OVAL);
        circle.setStroke(dp(3), Color.parseColor("#38BDF8"));
        emblem.setBackground(circle);
        LinearLayout.LayoutParams lpEmblem = new LinearLayout.LayoutParams(dp(108), dp(108));
        box.addView(emblem, lpEmblem);
        addSpacer(box, 18);

        TextView pill = new TextView(this);
        pill.setText("FIRST-BOOT EXPERIENCE  •  ANDROID 17");
        pill.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        pill.setTypeface(Typeface.DEFAULT_BOLD);
        pill.setTextColor(Color.parseColor("#38BDF8"));
        box.addView(pill);
        addSpacer(box, 6);

        TextView title = new TextView(this);
        title.setText("Welcome to XT-Series OS");
        title.setTextSize(TypedValue.COMPLEX_UNIT_SP, 27);
        title.setTypeface(Typeface.DEFAULT_BOLD);
        title.setTextColor(Color.WHITE);
        title.setGravity(Gravity.CENTER);
        box.addView(title);

        TextView sub = new TextView(this);
        sub.setText("Project Infinity-X 4.2 • Engineered for Samsung Exynos 9611");
        sub.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        sub.setTextColor(Color.parseColor("#94A3B8"));
        sub.setGravity(Gravity.CENTER);
        sub.setPadding(0, dp(4), 0, dp(18));
        box.addView(sub);

        LinearLayout specCard = makeCard();
        addFeatureBullet(specCard, "KernelSU-Next v3.4.2 + SuSFS v2.4.0",
                "Cold-boot global mount namespace (NS_DEFAULT) + kernel-level root & SuSFS v2.4.0 stealth.");
        addSpacer(specCard, 10);
        addFeatureBullet(specCard, "4 GB LZ4 ZRAM + Swap Memory Booster",
                "High-speed compressed RAM swap with page-cluster=0 and swappiness=100 for heavy multitasking.");
        addSpacer(specCard, 10);
        addFeatureBullet(specCard, "4G LTE + VoLTE / ViLTE / UT Stack",
                "Full RIL & ImsStack integration supporting both physical 4G SIM cards and SIM-less testing.");
        addSpacer(specCard, 10);
        addFeatureBullet(specCard, "Vivaldi ANR Eliminator & Mali-G72 Guard",
                "Disables Android 17 Cached Apps Freezer to eliminate multi-process browser false ANRs.");
        addSpacer(specCard, 10);
        addFeatureBullet(specCard, "System Build",
                Build.MODEL + " • " + System.getProperty("os.version", "4.14.357-XT-Line-AOSP"));
        box.addView(specCard);

        return box;
    }

    private View buildStage1Tuning() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);

        TextView hdr = new TextView(this);
        hdr.setText("Step 2 • XT-Series System & ZRAM Tuning");
        hdr.setTextSize(TypedValue.COMPLEX_UNIT_SP, 21);
        hdr.setTypeface(Typeface.DEFAULT_BOLD);
        hdr.setTextColor(Color.WHITE);
        box.addView(hdr);

        TextView desc = new TextView(this);
        desc.setText("All recommended Exynos 9611 optimizations are pre-selected for instant smoothness:");
        desc.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        desc.setTextColor(Color.parseColor("#94A3B8"));
        desc.setPadding(0, dp(4), 0, dp(14));
        box.addView(desc);

        LinearLayout c1 = makeCard();
        addSwitchRow(c1, "4 GB ZRAM + Swap Memory Booster",
                "Enables 4 GB LZ4 ZRAM swap (/dev/block/zram0), vm.swappiness=100, and page-cluster=0.",
                optZramSwap, (b, c) -> optZramSwap = c);
        box.addView(c1);
        addSpacer(box, 10);

        LinearLayout c2 = makeCard();
        addSwitchRow(c2, "Vivaldi & Browser False-ANR Eliminator",
                "Disables Android 17 Cached Apps Freezer, sets max_phantom_processes=128, and suppresses false ANR popups.",
                optAnrGuard, (b, c) -> optAnrGuard = c);
        box.addView(c2);
        addSpacer(box, 10);

        LinearLayout c3 = makeCard();
        addSwitchRow(c3, "Exynos 9611 Mali-G72 Smoothness Guard",
                "Disables heavy SurfaceFlinger window blurs and sets system animation scales to 0.85x.",
                optSmoothness, (b, c) -> optSmoothness = c);
        box.addView(c3);
        addSpacer(box, 10);

        LinearLayout c4 = makeCard();
        addSwitchRow(c4, "VoLTE / 4G LTE Radio Auto-Provisioning",
                "Activates VoLTE/ViLTE/UT IMS registration and enables 4G LTE mode switching (with & without SIM).",
                optVolteLte, (b, c) -> optVolteLte = c);
        box.addView(c4);

        return box;
    }

    private View buildStage2ThemeAndFinish() {
        LinearLayout box = new LinearLayout(this);
        box.setOrientation(LinearLayout.VERTICAL);

        TextView hdr = new TextView(this);
        hdr.setText("Step 3 • Visual Signature & Ready");
        hdr.setTextSize(TypedValue.COMPLEX_UNIT_SP, 21);
        hdr.setTypeface(Typeface.DEFAULT_BOLD);
        hdr.setTextColor(Color.WHITE);
        box.addView(hdr);

        TextView desc = new TextView(this);
        desc.setText("Select your system UI style (Stock Infinity-X 4.2 is active by default):");
        desc.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13f);
        desc.setTextColor(Color.parseColor("#94A3B8"));
        desc.setPadding(0, dp(4), 0, dp(12));
        box.addView(desc);

        LinearLayout themeCard = makeCard();
        tvSelectedTheme = new TextView(this);
        tvSelectedTheme.setText("Selected: Stock Infinity-X 4.2 Design (Default)");
        tvSelectedTheme.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        tvSelectedTheme.setTypeface(Typeface.DEFAULT_BOLD);
        tvSelectedTheme.setTextColor(Color.parseColor("#4ADE80"));
        tvSelectedTheme.setPadding(0, 0, 0, dp(10));
        themeCard.addView(tvSelectedTheme);

        Button btnStock = makeButton("Stock Infinity-X 4.2 Design (Recommended)", "#00C853", "#000000");
        btnStock.setOnClickListener(v -> {
            selectedThemePkg = null;
            tvSelectedTheme.setText("Selected: Stock Infinity-X 4.2 Design (Default)");
        });
        themeCard.addView(btnStock);
        addSpacer(themeCard, 8);

        for (final String[] t : AnrGuardEngine.THEMES) {
            Button b = makeButton(t[1], "#1E293B", "#E2E8F0");
            b.setOnClickListener(v -> {
                selectedThemePkg = t[0];
                tvSelectedTheme.setText("Selected: " + t[1]);
            });
            themeCard.addView(b);
            addSpacer(themeCard, 8);
        }
        box.addView(themeCard);
        addSpacer(box, 12);

        Button btnOpenSuite = makeButton("Finish & Open XT-Debug System Suite", "#1E293B", "#38BDF8");
        btnOpenSuite.setOnClickListener(v -> completeFirstBootSetup(true));
        box.addView(btnOpenSuite);

        return box;
    }

    private void showStep(int newStep) {
        step = newStep;
        for (int i = 0; i < 3; i++) {
            stepViews[i].setVisibility(i == step ? View.VISIBLE : View.GONE);
            GradientDrawable dotBg = new GradientDrawable();
            dotBg.setCornerRadius(dp(4));
            dotBg.setColor(Color.parseColor(i == step ? "#38BDF8" : (i < step ? "#2563EB" : "#1E293B")));
            stepDots[i].setBackground(dotBg);
        }
        btnBack.setVisibility(step == 0 ? View.INVISIBLE : View.VISIBLE);
        if (step == 0) {
            btnNext.setText("Configure XT-Series →");
        } else if (step == 1) {
            btnNext.setText("Choose Style →");
        } else {
            btnNext.setText("Complete Setup & Start XT-OS ✓");
        }
    }

    private void completeFirstBootSetup(boolean openDebugSuite) {
        AnrGuardReceiver.ensureDeviceProvisioned(this);
        if (optAnrGuard) {
            AnrGuardEngine.applyBrowserAnrFix(this, true);
            AnrGuardEngine.setVivaldiDialogShield(this, true);
        }
        if (optSmoothness) {
            AnrGuardEngine.applySmoothnessFix(this, true);
        }
        if (optZramSwap) {
            AnrGuardEngine.applyZramAndSwapTuning(this, true);
        }
        if (optVolteLte) {
            AnrGuardEngine.triggerSimlessVoLteRegistration(this);
        }
        if (selectedThemePkg == null) {
            AnrGuardEngine.resetToStockTheme(this);
        } else {
            AnrGuardEngine.applyThemeOverlay(this, selectedThemePkg);
        }
        AnrGuardEngine.killRunawayHogs(this);

        try {
            Settings.Global.putInt(getContentResolver(), KEY_FIRST_BOOT_DONE, 1);
        } catch (Throwable ignored) {}

        Toast.makeText(this, "XT-Series OS configured & ready!", Toast.LENGTH_SHORT).show();

        if (openDebugSuite) {
            Intent i = new Intent(this, DebugActivity.class);
            startActivity(i);
        }
        finish();
    }

    private void addFeatureBullet(LinearLayout parent, String title, String body) {
        TextView t = new TextView(this);
        t.setText("✦  " + title);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(Color.parseColor("#E2E8F0"));
        parent.addView(t);

        TextView b = new TextView(this);
        b.setText(body);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 12f);
        b.setTextColor(Color.parseColor("#94A3B8"));
        b.setPadding(dp(18), dp(2), 0, 0);
        parent.addView(b);
    }

    private void addSwitchRow(
            LinearLayout parent,
            String title,
            String desc,
            boolean checked,
            Switch.OnCheckedChangeListener listener) {
        LinearLayout row = new LinearLayout(this);
        row.setOrientation(LinearLayout.HORIZONTAL);
        row.setGravity(Gravity.CENTER_VERTICAL);

        LinearLayout col = new LinearLayout(this);
        col.setOrientation(LinearLayout.VERTICAL);

        TextView t = new TextView(this);
        t.setText(title);
        t.setTextSize(TypedValue.COMPLEX_UNIT_SP, 14f);
        t.setTypeface(Typeface.DEFAULT_BOLD);
        t.setTextColor(Color.WHITE);
        col.addView(t);

        TextView d = new TextView(this);
        d.setText(desc);
        d.setTextSize(TypedValue.COMPLEX_UNIT_SP, 11.5f);
        d.setTextColor(Color.parseColor("#94A3B8"));
        d.setPadding(0, dp(3), dp(10), 0);
        col.addView(d);

        row.addView(col, new LinearLayout.LayoutParams(0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        Switch sw = new Switch(this);
        sw.setChecked(checked);
        sw.setOnCheckedChangeListener(listener);
        row.addView(sw);

        parent.addView(row);
    }

    private LinearLayout makeCard() {
        LinearLayout card = new LinearLayout(this);
        card.setOrientation(LinearLayout.VERTICAL);
        int p = dp(14);
        card.setPadding(p, p, p, p);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor("#111923"));
        bg.setCornerRadius(dp(12));
        bg.setStroke(dp(1), Color.parseColor("#1E2D3D"));
        card.setBackground(bg);
        return card;
    }

    private Button makeButton(String label, String bgColor, String fgColor) {
        Button b = new Button(this);
        b.setText(label);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13.5f);
        b.setTypeface(Typeface.DEFAULT_BOLD);
        b.setTextColor(Color.parseColor(fgColor));
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(Color.parseColor(bgColor));
        bg.setCornerRadius(dp(10));
        b.setBackground(bg);
        b.setPadding(dp(12), dp(10), dp(12), dp(10));
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
