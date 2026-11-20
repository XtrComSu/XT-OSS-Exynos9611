// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.Activity;
import android.content.Context;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.ColorFilter;
import android.graphics.Paint;
import android.graphics.Path;
import android.graphics.PixelFormat;
import android.graphics.Typeface;
import android.graphics.drawable.Drawable;
import android.graphics.drawable.GradientDrawable;
import android.os.Build;
import android.provider.Settings;
import android.util.TypedValue;
import android.view.Gravity;
import android.view.View;
import android.view.ViewGroup;
import android.view.Window;
import android.widget.Button;
import android.widget.ImageButton;
import android.widget.LinearLayout;
import android.widget.TextView;

/**
 * Shared visual system for XT Debug:
 * <ul>
 *   <li>Background: {@code #101010}</li>
 *   <li>Raised surface: {@code #181818}</li>
 *   <li>Primary text: {@code #F2F2F2}</li>
 *   <li>Secondary text: {@code #A5A5A5}</li>
 *   <li>Dividers: {@code #2C2C2C}</li>
 *   <li>Accent red: {@code #F04444}</li>
 *   <li>Text on solid red: {@code #101010}</li>
 * </ul>
 */
public final class XtDesign {

    public static final int COLOR_BG = Color.parseColor("#101010");
    public static final int COLOR_SURFACE = Color.parseColor("#181818");
    public static final int COLOR_TEXT_PRIMARY = Color.parseColor("#F2F2F2");
    public static final int COLOR_TEXT_SECONDARY = Color.parseColor("#A5A5A5");
    public static final int COLOR_DIVIDER = Color.parseColor("#2C2C2C");
    public static final int COLOR_ACCENT_RED = Color.parseColor("#F04444");
    public static final int COLOR_TEXT_ON_RED = Color.parseColor("#101010");

    // Single font family across the app (Roboto system font on Android)
    public static final Typeface FONT_SEMIBOLD =
            Typeface.create("sans-serif", Typeface.BOLD);
    public static final Typeface FONT_MEDIUM =
            Typeface.create("sans-serif-medium", Typeface.NORMAL);
    public static final Typeface FONT_REGULAR =
            Typeface.create("sans-serif", Typeface.NORMAL);

    private XtDesign() {}

    public static int dp(Context ctx, float val) {
        return Math.round(TypedValue.applyDimension(
                TypedValue.COMPLEX_UNIT_DIP, val, ctx.getResources().getDisplayMetrics()));
    }

    public static boolean isReducedMotionEnabled(Context ctx) {
        try {
            float scale = Settings.Global.getFloat(
                    ctx.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 1.0f);
            return scale == 0.0f;
        } catch (Throwable ignored) {
            return false;
        }
    }

    public static void configureSystemBars(Activity activity) {
        try {
            Window w = activity.getWindow();
            if (w == null) return;
            w.setStatusBarColor(COLOR_BG);
            w.setNavigationBarColor(COLOR_BG);
            if (Build.VERSION.SDK_INT >= 35) {
                w.setDecorFitsSystemWindows(true);
            }
        } catch (Throwable ignored) {}
    }

    public static void applySafeInsetsPadding(final View target, final int basePadLeft,
            final int basePadTop, final int basePadRight, final int basePadBottom) {
        target.setPadding(basePadLeft, basePadTop, basePadRight, basePadBottom);
        target.setOnApplyWindowInsetsListener((v, insets) -> {
            int top = insets.getSystemWindowInsetTop();
            int bottom = insets.getSystemWindowInsetBottom();
            int left = insets.getSystemWindowInsetLeft();
            int right = insets.getSystemWindowInsetRight();
            v.setPadding(
                    basePadLeft + left,
                    basePadTop + top,
                    basePadRight + right,
                    basePadBottom + bottom);
            return insets;
        });
    }

    // =========================================================================
    // Typography Builders (Scalable SP units, left-aligned)
    // =========================================================================

    /** App name on intro: 34sp, semibold, #F2F2F2. */
    public static TextView makeIntroTitle(Context ctx, String text) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 34);
        tv.setTypeface(FONT_SEMIBOLD);
        tv.setTextColor(COLOR_TEXT_PRIMARY);
        tv.setGravity(Gravity.START);
        return tv;
    }

    /** Screen titles: 24sp, semibold, #F2F2F2. */
    public static TextView makeScreenTitle(Context ctx, String text) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 24);
        tv.setTypeface(FONT_SEMIBOLD);
        tv.setTextColor(COLOR_TEXT_PRIMARY);
        tv.setGravity(Gravity.START | Gravity.CENTER_VERTICAL);
        return tv;
    }

    /** Section heading: 13sp, medium, #A5A5A5. */
    public static TextView makeSectionHeading(Context ctx, String text) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tv.setTypeface(FONT_MEDIUM);
        tv.setTextColor(COLOR_TEXT_SECONDARY);
        tv.setGravity(Gravity.START);
        return tv;
    }

    /** Setting labels and button text: 16sp, medium, #F2F2F2. */
    public static TextView makeLabel(Context ctx, String text) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        tv.setTypeface(FONT_MEDIUM);
        tv.setTextColor(COLOR_TEXT_PRIMARY);
        tv.setGravity(Gravity.START);
        return tv;
    }

    /** Body and supporting descriptions: 15sp, regular, #A5A5A5 (or #F2F2F2). */
    public static TextView makeBody(Context ctx, String text, boolean primaryColor) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 15);
        tv.setTypeface(FONT_REGULAR);
        tv.setTextColor(primaryColor ? COLOR_TEXT_PRIMARY : COLOR_TEXT_SECONDARY);
        tv.setGravity(Gravity.START);
        tv.setLineSpacing(dp(ctx, 2), 1.0f);
        return tv;
    }

    /** Secondary metadata: 13sp, regular, #A5A5A5. */
    public static TextView makeMetadata(Context ctx, String text) {
        TextView tv = new TextView(ctx);
        tv.setText(text);
        tv.setTextSize(TypedValue.COMPLEX_UNIT_SP, 13);
        tv.setTypeface(FONT_REGULAR);
        tv.setTextColor(COLOR_TEXT_SECONDARY);
        tv.setGravity(Gravity.START);
        tv.setLineSpacing(dp(ctx, 2), 1.0f);
        return tv;
    }

    // =========================================================================
    // Surfaces, Dividers & Buttons (10-12dp radius, flat surfaces)
    // =========================================================================

    public static View makeDivider(Context ctx) {
        View v = new View(ctx);
        v.setBackgroundColor(COLOR_DIVIDER);
        v.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, Math.max(1, dp(ctx, 1))));
        return v;
    }

    public static View makeSpacer(Context ctx, int dpHeight) {
        View v = new View(ctx);
        v.setLayoutParams(new LinearLayout.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT, dp(ctx, dpHeight)));
        return v;
    }

    public static LinearLayout makeRaisedSurface(Context ctx) {
        LinearLayout box = new LinearLayout(ctx);
        box.setOrientation(LinearLayout.VERTICAL);
        int pad = dp(ctx, 16);
        box.setPadding(pad, pad, pad, pad);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(COLOR_SURFACE);
        bg.setCornerRadius(dp(ctx, 10));
        bg.setStroke(Math.max(1, dp(ctx, 1)), COLOR_DIVIDER);
        box.setBackground(bg);
        return box;
    }

    /** Primary red button (#F04444 background, #101010 text, 52dp min height, 10dp radius). */
    public static Button makePrimaryRedButton(Context ctx, String text) {
        Button b = new Button(ctx);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setTypeface(FONT_MEDIUM);
        b.setTextColor(COLOR_TEXT_ON_RED);
        b.setMinHeight(dp(ctx, 52));
        b.setMinimumHeight(dp(ctx, 52));
        b.setPadding(dp(ctx, 20), dp(ctx, 14), dp(ctx, 20), dp(ctx, 14));
        b.setStateListAnimator(null);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(COLOR_ACCENT_RED);
        bg.setCornerRadius(dp(ctx, 10));
        b.setBackground(bg);
        return b;
    }

    /** Secondary surface button (#181818 background, #F2F2F2 text, 48dp min height, 10dp radius). */
    public static Button makeSecondaryButton(Context ctx, String text) {
        Button b = new Button(ctx);
        b.setText(text);
        b.setAllCaps(false);
        b.setTextSize(TypedValue.COMPLEX_UNIT_SP, 16);
        b.setTypeface(FONT_MEDIUM);
        b.setTextColor(COLOR_TEXT_PRIMARY);
        b.setMinHeight(dp(ctx, 48));
        b.setMinimumHeight(dp(ctx, 48));
        b.setPadding(dp(ctx, 16), dp(ctx, 12), dp(ctx, 16), dp(ctx, 12));
        b.setStateListAnimator(null);
        GradientDrawable bg = new GradientDrawable();
        bg.setColor(COLOR_SURFACE);
        bg.setCornerRadius(dp(ctx, 10));
        bg.setStroke(Math.max(1, dp(ctx, 1)), COLOR_DIVIDER);
        b.setBackground(bg);
        return b;
    }

    /** Style a segmented choice button as selected (#F04444 / #101010) or unselected (#181818 / #F2F2F2). */
    public static void styleChoiceButton(Context ctx, Button b, boolean selected) {
        GradientDrawable bg = new GradientDrawable();
        bg.setCornerRadius(dp(ctx, 10));
        if (selected) {
            bg.setColor(COLOR_ACCENT_RED);
            b.setTextColor(COLOR_TEXT_ON_RED);
        } else {
            bg.setColor(COLOR_SURFACE);
            bg.setStroke(Math.max(1, dp(ctx, 1)), COLOR_DIVIDER);
            b.setTextColor(COLOR_TEXT_PRIMARY);
        }
        b.setBackground(bg);
    }

    // =========================================================================
    // Consistent Vector Icons (24dp, 2dp stroke, accessible labels)
    // =========================================================================

    public static ImageButton makeIconButton(Context ctx, Drawable icon, String contentDesc) {
        ImageButton btn = new ImageButton(ctx);
        btn.setImageDrawable(icon);
        btn.setContentDescription(contentDesc);
        btn.setBackgroundColor(Color.TRANSPARENT);
        int size = dp(ctx, 48);
        int pad = dp(ctx, 12);
        btn.setPadding(pad, pad, pad, pad);
        btn.setLayoutParams(new LinearLayout.LayoutParams(size, size));
        return btn;
    }

    public static Drawable makeBackArrowIcon(final Context ctx) {
        return new VectorStrokeDrawable(ctx) {
            @Override
            protected void drawVector(Canvas c, Paint p, float w, float h) {
                Path path = new Path();
                path.moveTo(w * 0.78f, h * 0.50f);
                path.lineTo(w * 0.22f, h * 0.50f);
                path.moveTo(w * 0.46f, h * 0.24f);
                path.lineTo(w * 0.20f, h * 0.50f);
                path.lineTo(w * 0.46f, h * 0.76f);
                c.drawPath(path, p);
            }
        };
    }

    public static Drawable makeSettingsIcon(final Context ctx) {
        return new VectorStrokeDrawable(ctx) {
            @Override
            protected void drawVector(Canvas c, Paint p, float w, float h) {
                float cx = w * 0.5f;
                float cy = h * 0.5f;
                c.drawCircle(cx, cy, w * 0.16f, p);
                float rIn = w * 0.28f;
                float rOut = w * 0.40f;
                for (int i = 0; i < 8; i++) {
                    double a = Math.toRadians(i * 45.0);
                    float x1 = cx + (float) Math.cos(a) * rIn;
                    float y1 = cy + (float) Math.sin(a) * rIn;
                    float x2 = cx + (float) Math.cos(a) * rOut;
                    float y2 = cy + (float) Math.sin(a) * rOut;
                    c.drawLine(x1, y1, x2, y2, p);
                }
                c.drawCircle(cx, cy, rIn, p);
            }
        };
    }

    public static Drawable makeChevronRightIcon(final Context ctx) {
        return new VectorStrokeDrawable(ctx, COLOR_TEXT_SECONDARY, 18) {
            @Override
            protected void drawVector(Canvas c, Paint p, float w, float h) {
                Path path = new Path();
                path.moveTo(w * 0.36f, h * 0.24f);
                path.lineTo(w * 0.64f, h * 0.50f);
                path.lineTo(w * 0.36f, h * 0.76f);
                c.drawPath(path, p);
            }
        };
    }

    private abstract static class VectorStrokeDrawable extends Drawable {
        private final Paint paint = new Paint(Paint.ANTI_ALIAS_FLAG);
        private final int sizePx;

        VectorStrokeDrawable(Context ctx) {
            this(ctx, COLOR_TEXT_PRIMARY, 24);
        }

        VectorStrokeDrawable(Context ctx, int color, int sizeDp) {
            this.sizePx = dp(ctx, sizeDp);
            paint.setColor(color);
            paint.setStyle(Paint.Style.STROKE);
            paint.setStrokeWidth(dp(ctx, 2));
            paint.setStrokeCap(Paint.Cap.ROUND);
            paint.setStrokeJoin(Paint.Join.ROUND);
        }

        protected abstract void drawVector(Canvas c, Paint p, float w, float h);

        @Override
        public void draw(Canvas canvas) {
            drawVector(canvas, paint, getBounds().width(), getBounds().height());
        }

        @Override
        public int getIntrinsicWidth() {
            return sizePx;
        }

        @Override
        public int getIntrinsicHeight() {
            return sizePx;
        }

        @Override
        public void setAlpha(int alpha) {
            paint.setAlpha(alpha);
        }

        @Override
        public void setColorFilter(ColorFilter colorFilter) {
            paint.setColorFilter(colorFilter);
        }

        @Override
        public int getOpacity() {
            return PixelFormat.TRANSLUCENT;
        }
    }
}
