// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.om.OverlayInfo;
import android.content.om.OverlayManager;
import android.os.DropBoxManager;
import android.os.Handler;
import android.os.Looper;
import android.os.UserHandle;
import android.provider.Settings;
import android.telephony.ServiceState;
import android.telephony.TelephonyManager;
import android.util.Log;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileReader;
import java.lang.reflect.Method;
import java.text.SimpleDateFormat;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;
import java.util.Locale;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

/**
 * Backend system engine for XT Debug.
 *
 * <p>All disk, {@code /proc}, {@code DropBoxManager}, and binder-heavy queries are
 * executed off the UI thread via {@link #runAsync} to guarantee locked 60 Hz frame pacing.
 */
public final class AnrGuardEngine {
    private static final String TAG = "XtDebug";
    public static final String PREFS_NAME = "xt_debug_prefs";

    public static final String KEY_CACHED_FREEZER = "cached_apps_freezer";
    public static final String KEY_AM_CONSTANTS = "activity_manager_constants";
    public static final String KEY_ANR_SHOW_BG = "anr_show_background";
    public static final String KEY_HIDE_ERROR_DIALOGS = "hide_error_dialogs";
    public static final String KEY_DISABLE_BLURS = "disable_window_blurs";
    public static final String KEY_ZRAM_GB = "xt_zram_size_gb";
    public static final String KEY_VOLTE_BOOT = "xt_volte_auto_boot";
    public static final String KEY_FONT_PKG = "xt_active_font_pkg";

    // Network Type Bitmasks (TelephonyManager.NETWORK_TYPE_BITMASK_*)
    public static final long RAF_LTE_ONLY = 4096L; // LTE (1 << 12)
    public static final long RAF_LTE_WCDMA_GSM = 101903L; // LTE | WCDMA | GSM

    public static final String AM_CONSTANTS_OPTIMIZED =
            "max_phantom_processes=128,"
            + "max_cached_processes=32,"
            + "service_start_foreground_timeout_ms=60000,"
            + "service_bg_activity_start_timeout=30000,"
            + "bg_current_drain_auto_restrict_abuser_enabled=false,"
            + "fg_to_bg_fgs_grace_duration=15000";

    private static final String[] RUNAWAY_HOGS = {
        "skynet.cputhrottlingtest"
    };

    public static final String[][] THEMES = {
        { "os.theme.stock",        "Stock Infinity-X", "Default system theme" },
        { "os.theme.monet",        "Monet Dynamic",    "Wallpaper-adaptive palette" },
        { "os.theme.nothing",      "Nothing Dark",     "AMOLED black surface" },
        { "os.theme.nothinglight", "Nothing Light",    "High-contrast light surface" },
    };

    public static final String[][] FONTS = {
        { null,                                  "System default" },
        { "com.android.theme.font.nothingdot",   "Nothing Dot" },
        { "com.android.theme.font.SpaceGrotesk", "Space Grotesk" },
        { "com.android.theme.font.sanfrancisco", "San Francisco" },
        { "com.android.theme.font.ibmplex",      "IBM Plex Sans" },
    };

    private static final ExecutorService IO_EXECUTOR = Executors.newSingleThreadExecutor();
    private static final Handler MAIN_HANDLER = new Handler(Looper.getMainLooper());

    public interface Callback<T> {
        void onResult(T result);
    }

    public static final class SystemDiagnostics {
        public float physTotalGb;
        public float physAvailGb;
        public float physUsedGb;
        public float swapTotalGb;
        public float swapUsedGb;
        public int configuredZramGb;
        public String cpuLittleFreq = "n/a";
        public String cpuBigFreq = "n/a";
        public String loadAvg = "n/a";
        public boolean imsRegistered;
        public String simState = "Unknown";
        public boolean lteOnlyLocked;
        public String serviceState = "Unknown";
        public String radioRat = "LTE";
        public boolean browserFixActive;
        public boolean dialogShieldActive;
        public boolean blurGuardActive;
        public float animScale = 0.85f;
        public int recentAnrCount;
        public String recentAnrSummary = "";
        public String topProcessSummary = "";
        public String errorMessage;
    }

    private AnrGuardEngine() {}

    public static <T> void runAsync(final java.util.concurrent.Callable<T> task, final Callback<T> cb) {
        IO_EXECUTOR.execute(() -> {
            try {
                final T res = task.call();
                MAIN_HANDLER.post(() -> cb.onResult(res));
            } catch (final Throwable t) {
                Log.e(TAG, "Background task error", t);
                MAIN_HANDLER.post(() -> cb.onResult(null));
            }
        });
    }

    public static SharedPreferences prefs(Context ctx) {
        return ctx.createDeviceProtectedStorageContext()
                .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
    }

    // =========================================================================
    // Onboarding Persistence (Preserves existing / upgraded users)
    // =========================================================================

    public static boolean isOnboardingCompleted(Context ctx) {
        try {
            if (prefs(ctx).getBoolean(XtWelcomeActivity.KEY_FIRST_BOOT_DONE, false)) {
                return true;
            }
            ContentResolver cr = ctx.getContentResolver();
            if (Settings.Global.getInt(cr, XtWelcomeActivity.KEY_FIRST_BOOT_DONE, 0) == 1) {
                prefs(ctx).edit().putBoolean(XtWelcomeActivity.KEY_FIRST_BOOT_DONE, true).apply();
                return true;
            }
            if (Settings.Global.getString(cr, "xt_zram_size_bytes") != null
                    && Settings.Global.getInt(cr, XtWelcomeActivity.KEY_FIRST_BOOT_DONE, -1) == -1) {
                markOnboardingCompleted(ctx, true);
                return true;
            }
        } catch (Throwable ignored) {}
        return false;
    }

    public static void markOnboardingCompleted(Context ctx, boolean completed) {
        try {
            prefs(ctx).edit().putBoolean(XtWelcomeActivity.KEY_FIRST_BOOT_DONE, completed).apply();
            Settings.Global.putInt(
                    ctx.getContentResolver(),
                    XtWelcomeActivity.KEY_FIRST_BOOT_DONE,
                    completed ? 1 : 0);
            Class<?> sp = Class.forName("android.os.SystemProperties");
            Method set = sp.getMethod("set", String.class, String.class);
            set.invoke(null, "persist.sys.xt.first_boot_done", completed ? "1" : "0");
        } catch (Throwable t) {
            Log.w(TAG, "markOnboardingCompleted warning", t);
        }
    }

    // =========================================================================
    // 1. ZRAM + Swap Dynamic Configurator (2 GB / 4 GB / 6 GB) & Defaults
    // =========================================================================

    public static void applyAllDefaults(Context context) {
        AnrGuardReceiver.ensureDeviceProvisioned(context);
        applyBrowserAnrFix(context, true);
        setVivaldiDialogShield(context, true);
        applySmoothnessFix(context, true);
        int gb = getSelectedZramGb(context);
        setZramSizeGb(context, gb);
        if (isAutoVolteEnabled(context)) {
            triggerSimlessVoLteRegistration(context);
        }
        killRunawayHogs(context);
    }

    public static int getSelectedZramGb(Context context) {
        try {
            int pVal = prefs(context).getInt(KEY_ZRAM_GB, 0);
            if (pVal == 2 || pVal == 4 || pVal == 6) return pVal;
            int saved = Settings.Global.getInt(context.getContentResolver(), KEY_ZRAM_GB, 0);
            if (saved == 2 || saved == 4 || saved == 6) return saved;
        } catch (Throwable ignored) {}
        String prop = getSystemProperty("persist.sys.xt.zram_size", "4294967296");
        if ("2147483648".equals(prop)) return 2;
        if ("6442450944".equals(prop)) return 6;
        return 4;
    }

    public static boolean setZramSizeGb(Context context, int gb) {
        if (gb != 2 && gb != 4 && gb != 6) gb = 4;
        String bytes = gb == 2 ? "2147483648" : (gb == 6 ? "6442450944" : "4294967296");
        try {
            prefs(context).edit().putInt(KEY_ZRAM_GB, gb).apply();
            Settings.Global.putInt(context.getContentResolver(), KEY_ZRAM_GB, gb);
            Settings.Global.putInt(context.getContentResolver(), "xt_zram_swap_enabled", 1);
            setZramDiskSizeProperty(context, bytes);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "setZramSizeGb failed", t);
            return false;
        }
    }

    public static boolean applyZramAndSwapTuning(Context context, boolean enable) {
        return setZramSizeGb(context, enable ? getSelectedZramGb(context) : 4);
    }

    public static void setZramDiskSizeProperty(Context context, String sizeBytes) {
        try {
            Settings.Global.putString(context.getContentResolver(), "xt_zram_size_bytes", sizeBytes);
            Class<?> sp = Class.forName("android.os.SystemProperties");
            Method set = sp.getMethod("set", String.class, String.class);
            set.invoke(null, "persist.sys.xt.zram_size", sizeBytes);
        } catch (Throwable t) {
            Log.w(TAG, "setZramDiskSizeProperty failed", t);
        }
    }

    public static String getSystemProperty(String key, String def) {
        try {
            Class<?> sp = Class.forName("android.os.SystemProperties");
            Method get = sp.getMethod("get", String.class, String.class);
            return (String) get.invoke(null, key, def);
        } catch (Throwable t) {
            return def;
        }
    }

    // =========================================================================
    // 2. ANR Guard & Exynos 9611 Smoothness
    // =========================================================================

    public static boolean applyBrowserAnrFix(Context context, boolean enable) {
        ContentResolver cr = context.getContentResolver();
        try {
            prefs(context).edit().putBoolean(KEY_CACHED_FREEZER, enable).apply();
            if (enable) {
                Settings.Global.putString(cr, KEY_CACHED_FREEZER, "disabled");
                Settings.Global.putString(cr, KEY_AM_CONSTANTS, AM_CONSTANTS_OPTIMIZED);
                Settings.Secure.putInt(cr, KEY_ANR_SHOW_BG, 0);
            } else {
                Settings.Global.putString(cr, KEY_CACHED_FREEZER, "device_default");
                Settings.Global.putString(cr, KEY_AM_CONSTANTS, "");
            }
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "Failed to apply Browser ANR fix", t);
            return false;
        }
    }

    public static boolean setVivaldiDialogShield(Context context, boolean enable) {
        ContentResolver cr = context.getContentResolver();
        try {
            prefs(context).edit().putBoolean(KEY_HIDE_ERROR_DIALOGS, enable).apply();
            Settings.Global.putInt(cr, KEY_HIDE_ERROR_DIALOGS, enable ? 1 : 0);
            Settings.Secure.putInt(cr, KEY_ANR_SHOW_BG, 0);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "Failed to toggle Vivaldi Dialog Shield", t);
            return false;
        }
    }

    public static boolean applySmoothnessFix(Context context, boolean enable) {
        ContentResolver cr = context.getContentResolver();
        try {
            prefs(context).edit().putBoolean(KEY_DISABLE_BLURS, enable).apply();
            Settings.Global.putInt(cr, KEY_DISABLE_BLURS, enable ? 1 : 0);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "Failed to apply Smoothness Fix", t);
            return false;
        }
    }

    public static boolean setAnimationScale(Context context, float scale) {
        ContentResolver cr = context.getContentResolver();
        try {
            prefs(context).edit().putFloat("xt_anim_scale", scale).apply();
            Settings.Global.putFloat(cr, Settings.Global.WINDOW_ANIMATION_SCALE, scale);
            Settings.Global.putFloat(cr, Settings.Global.TRANSITION_ANIMATION_SCALE, scale);
            Settings.Global.putFloat(cr, Settings.Global.ANIMATOR_DURATION_SCALE, scale);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "Failed to set animation scale", t);
            return false;
        }
    }

    public static float getAnimationScale(Context context) {
        try {
            return Settings.Global.getFloat(
                    context.getContentResolver(), Settings.Global.ANIMATOR_DURATION_SCALE, 0.85f);
        } catch (Throwable t) {
            return prefs(context).getFloat("xt_anim_scale", 0.85f);
        }
    }

    public static int killRunawayHogs(Context context) {
        int count = 0;
        try {
            ActivityManager am = context.getSystemService(ActivityManager.class);
            if (am == null) return 0;
            for (String pkg : RUNAWAY_HOGS) {
                am.killBackgroundProcesses(pkg);
                count++;
            }
        } catch (Throwable t) {
            Log.w(TAG, "killRunawayHogs error", t);
        }
        return count;
    }

    public static boolean isBrowserAnrFixActive(Context context) {
        ContentResolver cr = context.getContentResolver();
        String freezer = Settings.Global.getString(cr, KEY_CACHED_FREEZER);
        String amc = Settings.Global.getString(cr, KEY_AM_CONSTANTS);
        return "disabled".equalsIgnoreCase(freezer)
                && amc != null && amc.contains("max_phantom_processes=128");
    }

    public static boolean isVivaldiDialogShieldActive(Context context) {
        ContentResolver cr = context.getContentResolver();
        return Settings.Global.getInt(cr, KEY_HIDE_ERROR_DIALOGS, 0) == 1;
    }

    public static boolean isSmoothnessFixActive(Context context) {
        ContentResolver cr = context.getContentResolver();
        return Settings.Global.getInt(cr, KEY_DISABLE_BLURS, 0) == 1;
    }

    // =========================================================================
    // 3. 4G LTE & VoLTE / IMS Radio Lab (Works with and without SIM Card)
    // =========================================================================

    public static long getAllowedNetworkBitmask(Context context) {
        try {
            int mode = Settings.Global.getInt(context.getContentResolver(), "preferred_network_mode", -1);
            if (mode == 11) return RAF_LTE_ONLY;
            if (mode == 9) return RAF_LTE_WCDMA_GSM;
            TelephonyManager tm = context.getSystemService(TelephonyManager.class);
            if (tm != null) {
                Method mGetRaf = TelephonyManager.class.getMethod("getAllowedNetworkTypesForReason", int.class);
                Object r = mGetRaf.invoke(tm, 0);
                if (r instanceof Long && ((Long) r) > 0) return (Long) r;
            }
        } catch (Throwable ignored) {}
        return RAF_LTE_WCDMA_GSM;
    }

    public static boolean setPreferredNetworkBitmask(Context context, long rafBitmask) {
        try {
            int mode = (rafBitmask == RAF_LTE_ONLY) ? 11 : 9;
            prefs(context).edit().putInt("preferred_network_mode", mode).apply();
            Settings.Global.putInt(context.getContentResolver(), "preferred_network_mode", mode);
            Settings.Global.putInt(context.getContentResolver(), "preferred_network_mode1", mode);
            TelephonyManager tm = context.getSystemService(TelephonyManager.class);
            if (tm != null) {
                Method m = TelephonyManager.class.getMethod(
                        "setAllowedNetworkTypesForReason", int.class, long.class);
                m.invoke(tm, 0, rafBitmask);
            }
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "setPreferredNetworkBitmask failed", t);
            return false;
        }
    }

    public static boolean isAutoVolteEnabled(Context context) {
        try {
            return prefs(context).getBoolean(KEY_VOLTE_BOOT, true);
        } catch (Throwable ignored) {
            return true;
        }
    }

    public static void setAutoVolteEnabled(Context context, boolean enabled) {
        try {
            prefs(context).edit().putBoolean(KEY_VOLTE_BOOT, enabled).apply();
            Settings.Global.putInt(context.getContentResolver(), KEY_VOLTE_BOOT, enabled ? 1 : 0);
            if (enabled) {
                triggerSimlessVoLteRegistration(context);
            }
        } catch (Throwable ignored) {}
    }

    public static void triggerSimlessVoLteRegistration(Context context) {
        try {
            Intent intent = new Intent("com.android.imsstack.action.INTENT_AOS_TEST");
            intent.setPackage("com.android.imsstack");
            intent.putExtra("slotId", 0);
            intent.putExtra("code", 1); // EVENT_IMS_REGISTRATION_STATE
            intent.putExtra("data", "0,1,15,1");
            context.sendBroadcast(intent);
            Settings.Global.putInt(context.getContentResolver(), "xt_volte_provisioned", 1);
        } catch (Throwable t) {
            Log.e(TAG, "triggerSimlessVoLteRegistration failed", t);
        }
    }

    public static boolean isImsRegistered(Context context) {
        try {
            TelephonyManager tm = context.getSystemService(TelephonyManager.class);
            if (tm != null) {
                Method mIms = TelephonyManager.class.getMethod("isImsRegistered");
                Object res = mIms.invoke(tm);
                if (res instanceof Boolean && (Boolean) res) return true;
            }
        } catch (Throwable ignored) {}
        return Settings.Global.getInt(context.getContentResolver(), "xt_volte_provisioned", 0) == 1;
    }

    public static boolean openRadioInfo(Context context) {
        return launchComponent(context, "com.android.phone", "com.android.phone.settings.RadioInfo");
    }

    public static boolean openImsStackConfig(Context context) {
        return launchComponent(context, "com.android.imsstack", "com.android.imsstack.debug.ConfigActivity");
    }

    public static boolean openDolbyAtmos(Context context) {
        return launchPackage(context, "org.lineageos.dap");
    }

    public static boolean openSamsungDoze(Context context) {
        return launchComponent(context, "org.lineageos.settings.doze", "org.lineageos.settings.doze.DozeSettingsActivity");
    }

    private static boolean launchComponent(Context context, String pkg, String cls) {
        try {
            Intent i = new Intent(Intent.ACTION_MAIN);
            i.setComponent(new ComponentName(pkg, cls));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(i);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "launchComponent failed: " + pkg + "/" + cls, t);
            return false;
        }
    }

    private static boolean launchPackage(Context context, String pkg) {
        try {
            Intent i = context.getPackageManager().getLaunchIntentForPackage(pkg);
            if (i != null) {
                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                context.startActivity(i);
                return true;
            }
        } catch (Throwable ignored) {}
        return false;
    }

    // =========================================================================
    // 4. Asynchronous System Diagnostics Snapshot (Off-UI-Thread)
    // =========================================================================

    public static SystemDiagnostics collectDiagnosticsSync(Context context) {
        SystemDiagnostics d = new SystemDiagnostics();
        try {
            d.configuredZramGb = getSelectedZramGb(context);
            d.browserFixActive = isBrowserAnrFixActive(context);
            d.dialogShieldActive = isVivaldiDialogShieldActive(context);
            d.blurGuardActive = isSmoothnessFixActive(context);
            d.animScale = getAnimationScale(context);

            long totalKb = 0, availKb = 0, swapTotalKb = 0, swapFreeKb = 0;
            for (String line : lines("/proc/meminfo")) {
                if (line.startsWith("MemTotal:")) totalKb = kb(line);
                else if (line.startsWith("MemAvailable:")) availKb = kb(line);
                else if (line.startsWith("SwapTotal:")) swapTotalKb = kb(line);
                else if (line.startsWith("SwapFree:")) swapFreeKb = kb(line);
            }
            if (totalKb > 0) {
                d.physTotalGb = totalKb / 1024f / 1024f;
                d.physAvailGb = availKb / 1024f / 1024f;
                d.physUsedGb = Math.max(0.1f, d.physTotalGb - d.physAvailGb);
            }
            if (swapTotalKb > 0) {
                d.swapTotalGb = swapTotalKb / 1024f / 1024f;
                d.swapUsedGb = Math.max(0f, (swapTotalKb - swapFreeKb) / 1024f / 1024f);
            }

            String c0 = readFirstLine("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq");
            String c4 = readFirstLine("/sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq");
            try { d.cpuLittleFreq = (Long.parseLong(c0) / 1000) + " MHz"; } catch (Throwable ignored) {}
            try { d.cpuBigFreq = (Long.parseLong(c4) / 1000) + " MHz"; } catch (Throwable ignored) {}

            String lavg = readFirstLine("/proc/loadavg");
            if (!"n/a".equals(lavg)) {
                String[] p = lavg.split("\\s+");
                if (p.length >= 3) d.loadAvg = p[0] + " / " + p[1] + " / " + p[2];
            }

            d.imsRegistered = isImsRegistered(context);
            d.lteOnlyLocked = (getAllowedNetworkBitmask(context) == RAF_LTE_ONLY);

            TelephonyManager tm = context.getSystemService(TelephonyManager.class);
            if (tm != null) {
                d.simState = simStateToString(tm.getSimState());
                ServiceState ss = null;
                try {
                    Method mSs = TelephonyManager.class.getMethod("getServiceStateForSlot", int.class);
                    ss = (ServiceState) mSs.invoke(tm, 0);
                } catch (Throwable ignored) {
                    ss = tm.getServiceState();
                }
                if (ss != null) {
                    d.serviceState = serviceStateToString(ss.getState());
                    try {
                        Method mDataRat = ServiceState.class.getMethod("getRilDataRadioTechnology");
                        Method mRatStr = ServiceState.class.getMethod("rilRadioTechnologyToString", int.class);
                        int dRat = (Integer) mDataRat.invoke(ss);
                        d.radioRat = String.valueOf(mRatStr.invoke(null, dRat));
                    } catch (Throwable ignored) {}
                }
            }

            readDropBoxAnrsInto(context, d);
            d.topProcessSummary = readTopProcesses(5);
        } catch (Throwable t) {
            d.errorMessage = "Could not read system telemetry: " + t.getMessage();
        }
        return d;
    }

    private static void readDropBoxAnrsInto(Context context, SystemDiagnostics d) {
        try {
            DropBoxManager dbm = context.getSystemService(DropBoxManager.class);
            if (dbm == null) return;

            String[] tags = {"data_app_anr", "system_app_anr", "system_server_anr"};
            SimpleDateFormat sdf = new SimpleDateFormat("MM-dd HH:mm", Locale.US);
            StringBuilder out = new StringBuilder();
            int found = 0;

            for (String tag : tags) {
                long time = System.currentTimeMillis() - (24L * 3600L * 1000L);
                while (time > 0) {
                    DropBoxManager.Entry entry = dbm.getNextEntry(tag, time);
                    if (entry == null) break;
                    time = entry.getTimeMillis();
                    String snippet = entry.getText(240);
                    entry.close();
                    found++;
                    String proc = tag;
                    if (snippet != null) {
                        for (String line : snippet.split("\n")) {
                            if (line.startsWith("Process:")) {
                                proc = line.substring(8).trim();
                                break;
                            }
                        }
                    }
                    if (out.length() > 0) out.append('\n');
                    out.append(sdf.format(new Date(time))).append("  ").append(proc);
                    if (found >= 4) break;
                }
            }
            d.recentAnrCount = found;
            d.recentAnrSummary = out.toString();
        } catch (Throwable ignored) {}
    }

    private static String readTopProcesses(int maxCount) {
        File proc = new File("/proc");
        String[] pids = proc.list();
        if (pids == null) return "";

        List<long[]> sizes = new ArrayList<>();
        List<String> names = new ArrayList<>();

        for (String pid : pids) {
            if (pid.isEmpty() || !Character.isDigit(pid.charAt(0))) continue;
            long rssKb = 0;
            String name = pid;
            boolean ok = false;
            for (String line : lines("/proc/" + pid + "/status")) {
                if (line.startsWith("Name:")) {
                    name = line.substring(5).trim();
                } else if (line.startsWith("VmRSS:")) {
                    rssKb = kb(line);
                    ok = true;
                }
            }
            if (ok && rssKb > 0) {
                sizes.add(new long[] { rssKb, sizes.size() });
                names.add(name);
            }
        }

        Integer[] order = new Integer[sizes.size()];
        for (int i = 0; i < order.length; i++) order[i] = i;
        Arrays.sort(order, (a, b) -> Long.compare(sizes.get(b)[0], sizes.get(a)[0]));

        StringBuilder sb = new StringBuilder();
        int shown = 0;
        for (int idx : order) {
            if (shown++ >= maxCount) break;
            if (sb.length() > 0) sb.append('\n');
            sb.append(String.format(Locale.US, "%s — %.0f MB", names.get(idx), sizes.get(idx)[0] / 1024f));
        }
        return sb.toString();
    }

    private static String simStateToString(int state) {
        switch (state) {
            case TelephonyManager.SIM_STATE_ABSENT: return "No SIM (test mode)";
            case TelephonyManager.SIM_STATE_READY: return "SIM ready";
            case TelephonyManager.SIM_STATE_PIN_REQUIRED: return "PIN required";
            case TelephonyManager.SIM_STATE_PUK_REQUIRED: return "PUK required";
            default: return "State " + state;
        }
    }

    private static String serviceStateToString(int state) {
        switch (state) {
            case ServiceState.STATE_IN_SERVICE: return "In service";
            case ServiceState.STATE_OUT_OF_SERVICE: return "Standby / SIM-less";
            case ServiceState.STATE_EMERGENCY_ONLY: return "Emergency only";
            case ServiceState.STATE_POWER_OFF: return "Radio off";
            default: return "State " + state;
        }
    }

    private static long kb(String line) {
        String[] parts = line.trim().split("\\s+");
        for (String p : parts) {
            try {
                return Long.parseLong(p);
            } catch (NumberFormatException ignored) {}
        }
        return 0;
    }

    private static List<String> lines(String path) {
        List<String> out = new ArrayList<>();
        try (BufferedReader r = new BufferedReader(new FileReader(path))) {
            String line;
            while ((line = r.readLine()) != null) {
                out.add(line);
            }
        } catch (Throwable ignored) {}
        return out;
    }

    private static String readFirstLine(String path) {
        try (BufferedReader br = new BufferedReader(new FileReader(path))) {
            String line = br.readLine();
            return line != null ? line.trim() : "n/a";
        } catch (Throwable t) {
            return "n/a";
        }
    }

    // =========================================================================
    // 5. Visual Theme & Typography Overlay Manager
    // =========================================================================

    public static boolean resetToStockTheme(Context context) {
        OverlayManager om = context.getSystemService(OverlayManager.class);
        if (om == null) return false;
        String[] toDisable = {
            "os.theme.nothing",
            "os.theme.nothinglight",
            "os.theme.monet",
            "os.theme.stock",
            "com.android.system.theme.black"
        };
        for (String pkg : toDisable) {
            try {
                om.setEnabled(pkg, false, UserHandle.SYSTEM);
            } catch (Throwable ignored) {}
        }
        prefs(context).edit().putString("xt_theme_pkg", "os.theme.stock").apply();
        return true;
    }

    public static boolean applyThemeOverlay(Context context, String pkg) {
        prefs(context).edit().putString("xt_theme_pkg", pkg != null ? pkg : "os.theme.stock").apply();
        if (pkg == null || "os.theme.stock".equals(pkg)) {
            return resetToStockTheme(context);
        }
        OverlayManager om = context.getSystemService(OverlayManager.class);
        if (om == null) return false;
        try {
            om.setEnabledExclusiveInCategory(pkg, UserHandle.SYSTEM);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "Failed to enable overlay " + pkg, t);
            return false;
        }
    }

    public static boolean applyFontOverlay(Context context, String fontPkg) {
        prefs(context).edit().putString(KEY_FONT_PKG, fontPkg != null ? fontPkg : "").apply();
        OverlayManager om = context.getSystemService(OverlayManager.class);
        if (om == null) return false;
        try {
            if (fontPkg == null || fontPkg.isEmpty()) {
                for (String[] f : FONTS) {
                    if (f[0] != null) {
                        try { om.setEnabled(f[0], false, UserHandle.SYSTEM); } catch (Throwable ignored) {}
                    }
                }
                return true;
            }
            om.setEnabledExclusiveInCategory(fontPkg, UserHandle.SYSTEM);
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "Failed to apply font overlay " + fontPkg, t);
            return false;
        }
    }

    public static String getActiveThemePkg(Context context) {
        OverlayManager om = context.getSystemService(OverlayManager.class);
        if (om != null) {
            try {
                List<OverlayInfo> infos = om.getOverlayInfosForTarget("android", UserHandle.SYSTEM);
                for (OverlayInfo info : infos) {
                    if (!info.isEnabled()) continue;
                    for (String[] theme : THEMES) {
                        if (theme[0].equals(info.getPackageName())) {
                            return theme[0];
                        }
                    }
                }
            } catch (Throwable ignored) {}
        }
        return prefs(context).getString("xt_theme_pkg", "os.theme.stock");
    }

    public static String getActiveThemeSummary(Context context) {
        String pkg = getActiveThemePkg(context);
        for (String[] t : THEMES) {
            if (t[0].equals(pkg)) return t[1];
        }
        return "Stock Infinity-X";
    }

    public static String getActiveFontPkg(Context context) {
        String saved = prefs(context).getString(KEY_FONT_PKG, "");
        return saved.isEmpty() ? null : saved;
    }

    public static String getActiveFontSummary(Context context) {
        String pkg = getActiveFontPkg(context);
        for (String[] f : FONTS) {
            if ((pkg == null && f[0] == null) || (pkg != null && pkg.equals(f[0]))) {
                return f[1];
            }
        }
        return "System default";
    }
}
