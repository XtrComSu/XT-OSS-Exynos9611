// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Activity;
import android.content.Intent;
import android.os.Bundle;
import android.view.View;
import android.view.ViewGroup;
import android.widget.Button;
import android.widget.LinearLayout;
import android.widget.ScrollView;
import android.widget.TextView;

/**
 * Single-screen first-launch intro for XT Debug.
 *
 * <p>Follows the strict utility design system:
 * <ul>
 *   <li>Plain near-black background ({@code #101010})</li>
 *   <li>App name ({@code 34sp}, semibold, {@code #F2F2F2}) and a single factual sentence
 *       ({@code 16sp}, regular, {@code #A5A5A5}) grouped left-aligned near the upper third</li>
 *   <li>Empty middle space with no carousels, badges, or decorative cards</li>
 *   <li>Full-width red {@code "Get started"} button ({@code #F04444}, {@code #101010} text,
 *       {@code 52dp} minimum height) anchored near the bottom above system navigation</li>
 * </ul>
 */
public final class XtWelcomeActivity extends Activity {

    public static final String KEY_FIRST_BOOT_DONE = "xt_first_boot_completed";
    public static final String EXTRA_FROM_SETTINGS = "from_settings";

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
        XtDesign.applySafeInsetsPadding(root, margin, margin, margin, margin);

        // Top flexible spacer (~1 part) to place title + sentence around the upper third
        View topSpace = new View(this);
        root.addView(topSpace, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 1.0f));

        // Upper-third left-aligned title + single factual sentence
        TextView tvAppName = XtDesign.makeIntroTitle(this, getString(R.string.app_name));
        root.addView(tvAppName);

        root.addView(XtDesign.makeSpacer(this, 10));

        TextView tvSentence = XtDesign.makeBody(
                this,
                "Configure ZRAM swap, 4G VoLTE, and browser ANR protection for your device.",
                false);
        tvSentence.setTextSize(android.util.TypedValue.COMPLEX_UNIT_SP, 16);
        root.addView(tvSentence);

        // Empty space between title block and bottom button (~2.2 parts)
        View middleSpace = new View(this);
        root.addView(middleSpace, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, 0, 2.2f));

        root.addView(XtDesign.makeSpacer(this, 24));

        // Full-width red "Get started" button anchored near the bottom
        Button btnGetStarted = XtDesign.makePrimaryRedButton(this, "Get started");
        btnGetStarted.setOnClickListener(v -> completeIntro());
        root.addView(btnGetStarted, new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.WRAP_CONTENT));

        scroll.addView(root);
        setContentView(scroll);
    }

    private void completeIntro() {
        AnrGuardEngine.markOnboardingCompleted(this, true);
        AnrGuardEngine.runAsync(() -> {
            AnrGuardEngine.applyAllDefaults(getApplicationContext());
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
