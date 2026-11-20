// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.util.TypedValue;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.Switch;
import android.widget.TextView;

/**
 * First-launch XT-Series Welcome screen for XT Debug.
 *
 * <p>Uses the black-and-red utility visual system ({@code #101010} background,
 * {@code #181818} surface, {@code #F2F2F2} primary text, {@code #A5A5A5} secondary text,
 * {@code #F04444} red accent) and lets the user pick between 2 GB / 4 GB / 6 GB ZRAM swap,
 * 4G LTE network mode, and VoLTE provisioning right on first boot before tapping
 * {@code "Get started"}.
 */
public final class XtWelcomeActivity extends Activity {

    public static final String KEY_FIRST_BOOT_DONE = "xt_first_boot_completed";
    public static final String EXTRA_FROM_SETTINGS = "from_settings";

    private int selectedZramGb = 4;
    private boolean forceLteOnly = false;
    private boolean enableVolte = true;

    private final Button[] zramButtons = new Button[3];
    private final Button[] ratButtons = new Button[2];

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        XtDesign.configureSystemBars(this);

        selectedZramGb = AnrGuardEngine.getSelectedZramGb(this);
        forceLteOnly = (AnrGuardEngine.getAllowedNetworkBitmask(this) == AnrGuardEngine.RAF_LTE_ONLY);
        enableVolte = AnrGuardEngine.isAutoVolteEnabled(this);

        ScrollView scroll = new ScrollView(this);
        scroll.setFillViewport(true);
        scroll.setBackgroundColor(XtDesign.COLOR_BG);

        LinearLayout root = new LinearLayout(this);
        root.setOrientation(LinearLayout.VERTICAL);
        int margin = XtDesign.dp(this, 24);
        XtDesign.applySafeInsetsPadding(root, margin, margin, margin, margin);

        // Top flexible space to position header around upper third
        View topSpace = new View(this);
        root.addView(topSpace, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 0.7f));

        // Left-aligned title + single factual sentence
        TextView tvAppName = XtDesign.makeIntroTitle(this, getString(R.string.app_name));
        root.addView(tvAppName);

        root.addView(XtDesign.makeSpacer(this, 10));

        TextView tvSentence = XtDesign.makeBody(
                this,
                "Configure ZRAM swap, 4G VoLTE, and browser ANR protection for your device.",
                false);
        tvSentence.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        root.addView(tvSentence);

        root.addView(XtDesign.makeSpacer(this, 28));

        // First-boot 2 GB / 4 GB / 6 GB ZRAM Swap selector
        root.addView(XtDesign.makeSectionHeading(this, "ZRAM SWAP MEMORY"));
        root.addView(XtDesign.makeSpacer(this, 10));

        LinearLayout zramRow = new LinearLayout(this);
        zramRow.setOrientation(LinearLayout.HORIZONTAL);
        final int[] sizes = { 2, 4, 6 };
        String[] labels = { "2 GB", "4 GB", "6 GB" };
        for (int i = 0; i < 3; i++) {
            final int gb = sizes[i];
            Button b = XtDesign.makeSecondaryButton(this, labels[i]);
            b.setOnClickListener(v -> {
                selectedZramGb = gb;
                refreshChoices();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
            if (i < 2) lp.setMarginEnd(XtDesign.dp(this, 8));
            zramRow.addView(b, lp);
            zramButtons[i] = b;
        }
        root.addView(zramRow);

        root.addView(XtDesign.makeSpacer(this, 24));

        // First-boot 4G LTE & VoLTE selector
        root.addView(XtDesign.makeSectionHeading(this, "CELLULAR & VOLTE"));
        root.addView(XtDesign.makeSpacer(this, 10));

        LinearLayout ratRow = new LinearLayout(this);
        ratRow.setOrientation(LinearLayout.HORIZONTAL);
        String[] ratLabels = { "LTE / 3G / 2G auto", "4G LTE only" };
        for (int i = 0; i < 2; i++) {
            final boolean lteOnly = (i == 1);
            Button b = XtDesign.makeSecondaryButton(this, ratLabels[i]);
            b.setOnClickListener(v -> {
                forceLteOnly = lteOnly;
                refreshChoices();
            });
            LinearLayout.LayoutParams lp = new LinearLayout.LayoutParams(
                    0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f);
            if (i == 0) lp.setMarginEnd(XtDesign.dp(this, 8));
            ratRow.addView(b, lp);
            ratButtons[i] = b;
        }
        root.addView(ratRow);

        root.addView(XtDesign.makeSpacer(this, 14));

        // VoLTE toggle row
        LinearLayout volteRow = new LinearLayout(this);
        volteRow.setOrientation(LinearLayout.HORIZONTAL);
        volteRow.setGravity(android.view.Gravity.CENTER_VERTICAL);
        volteRow.setMinimumHeight(XtDesign.dp(this, 48));

        TextView tvVolte = XtDesign.makeLabel(this, "Enable 4G VoLTE & IMS");
        volteRow.addView(tvVolte, new LinearLayout.LayoutParams(
                0, ViewGroup.LayoutParams.WRAP_CONTENT, 1.0f));

        final Switch swVolte = new Switch(this);
        swVolte.setChecked(enableVolte);
        swVolte.setOnCheckedChangeListener((btn, checked) -> enableVolte = checked);
        volteRow.setOnClickListener(v -> swVolte.setChecked(!swVolte.isChecked()));
        volteRow.addView(swVolte);
        root.addView(volteRow);

        refreshChoices();

        // Flexible middle space before bottom button
        View middleSpace = new View(this);
        root.addView(middleSpace, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1.3f));

        root.addView(XtDesign.makeSpacer(this, 24));

        // Full-width red "Get started" button anchored near the bottom
        Button btnGetStarted = XtDesign.makePrimaryRedButton(this, "Get started");
        btnGetStarted.setOnClickListener(v -> completeIntro());
        root.addView(btnGetStarted, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        scroll.addView(root);
        setContentView(scroll);
    }

    private void refreshChoices() {
        int[] sizes = { 2, 4, 6 };
        for (int i = 0; i < 3; i++) {
            if (zramButtons[i] != null) {
                XtDesign.styleChoiceButton(this, zramButtons[i], sizes[i] == selectedZramGb);
            }
        }
        if (ratButtons[0] != null && ratButtons[1] != null) {
            XtDesign.styleChoiceButton(this, ratButtons[0], !forceLteOnly);
            XtDesign.styleChoiceButton(this, ratButtons[1], forceLteOnly);
        }
    }

    private void completeIntro() {
        final int zramGb = selectedZramGb;
        final long raf = forceLteOnly ? AnrGuardEngine.RAF_LTE_ONLY : AnrGuardEngine.RAF_LTE_WCDMA_GSM;
        final boolean volte = enableVolte;

        AnrGuardEngine.markOnboardingCompleted(this, true);
        AnrGuardEngine.runAsync(() -> {
            AnrGuardReceiver.ensureDeviceProvisioned(getApplicationContext());
            AnrGuardEngine.setZramSizeGb(getApplicationContext(), zramGb);
            AnrGuardEngine.setPreferredNetworkBitmask(getApplicationContext(), raf);
            AnrGuardEngine.setAutoVolteEnabled(getApplicationContext(), volte);
            AnrGuardEngine.applyBrowserAnrFix(getApplicationContext(), true);
            AnrGuardEngine.setVivaldiDialogShield(getApplicationContext(), true);
            AnrGuardEngine.applySmoothnessFix(getApplicationContext(), true);
            AnrGuardEngine.killRunawayHogs(getApplicationContext());
            return Boolean.TRUE;
        }, ignored -> {});

        boolean fromSettings = getIntent() != null
                && getIntent().getBooleanExtra(EXTRA_FROM_SETTINGS, false);
        if (!fromSettings) {
            Intent main = new Intent(this, DebugActivity.class);
            main.addFlags(Intent.FLAG_ACTIVITY_CLEAR_TOP | Intent.FLAG_ACTIVITY_SINGLE_TOP);
            startActivity(main);
        }
        finish();
        if (XtDesign.isReducedMotionEnabled(this)) {
            overridePendingTransition(0, 0);
        }
    }
}
