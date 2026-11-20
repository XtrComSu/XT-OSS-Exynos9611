// SPDX-License-Identifier: Apache-2.0
package os.xt.debug;

import android.app.ActivityManager;
import android.content.ComponentName;
import android.content.ContentResolver;
import android.content.Context;
import android.content.Intent;
import android.content.om.OverlayInfo;
import android.content.om.OverlayManager;
import android.os.DropBoxManager;
import android.os.UserHandle;
import android.provider.Settings;
import android.telephony.CellIdentityGsm;
import android.telephony.CellIdentityLte;
import android.telephony.CellIdentityWcdma;
import android.telephony.CellInfo;
import android.telephony.CellInfoGsm;
import android.telephony.CellInfoLte;
import android.telephony.CellInfoWcdma;
import android.telephony.CellSignalStrengthLte;
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

/**
 * Unified XT-Debug Engine combining:
 *   1. Vivaldi / Multi-Process Browser False-ANR Eliminator & Exynos 9611 Smoothness Guard
 *   2. 4G LTE Network Mode Controller & VoLTE / IMS Registration Lab (with SIM-less support)
 *   3. Real-time Kernel, Memory (/proc/meminfo), ZRAM (/proc/swaps), PSI (/proc/pressure) & Top RSS Monitor
 *   4. RRO Theme & Overlay Switcher (Stock Infinity-X default, Monet, Nothing Dark, Nothing Light)
 */
public final class AnrGuardEngine {
    private static final String TAG = "XtDebug";

    public static final String KEY_CACHED_FREEZER = "cached_apps_freezer";
    public static final String KEY_AM_CONSTANTS = "activity_manager_constants";
    public static final String KEY_ANR_SHOW_BG = "anr_show_background";
    public static final String KEY_HIDE_ERROR_DIALOGS = "hide_error_dialogs";
    public static final String KEY_DISABLE_BLURS = "disable_window_blurs";

    // Network Type Bitmasks (TelephonyManager.NETWORK_TYPE_BITMASK_*)
    public static final long RAF_LTE_ONLY = 4096L; // LTE (1 << 12)
    public static final long RAF_LTE_WCDMA_GSM = 101903L; // LTE | WCDMA | GSM/GPRS/EDGE/HSPA

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
        { "os.theme.stock",        "Stock AOSP / Infinity-X (Default)" },
        { "os.theme.monet",        "Monet / Dynamic Color" },
        { "os.theme.nothing",      "Nothing Dark (AMOLED)" },
        { "os.theme.nothinglight", "Nothing Light" },
    };

    private AnrGuardEngine() {}

    // =========================================================================
    // 1. ANR Guard & Exynos 9611 Smoothness
    // =========================================================================

    public static void applyAllDefaults(Context context) {
        AnrGuardReceiver.ensureDeviceProvisioned(context);
        applyBrowserAnrFix(context, true);
        applySmoothnessFix(context, true);
        applyZramAndSwapTuning(context, true);
        killRunawayHogs(context);
    }

    public static boolean applyZramAndSwapTuning(Context context, boolean enable) {
        try {
            Settings.Global.putInt(context.getContentResolver(), "xt_zram_swap_enabled", enable ? 1 : 0);
            setZramDiskSizeProperty(context, enable ? "4294967296" : "0");
            return true;
        } catch (Throwable t) {
            Log.w(TAG, "applyZramAndSwapTuning warning", t);
            return false;
        }
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

    public static boolean applyBrowserAnrFix(Context context, boolean enable) {
        ContentResolver cr = context.getContentResolver();
        try {
            if (enable) {
                Settings.Global.putString(cr, KEY_CACHED_FREEZER, "disabled");
                Settings.Global.putString(cr, KEY_AM_CONSTANTS, AM_CONSTANTS_OPTIMIZED);
                Settings.Secure.putInt(cr, KEY_ANR_SHOW_BG, 0);
            } else {
                Settings.Global.putString(cr, KEY_CACHED_FREEZER, "device_default");
                Settings.Global.putString(cr, KEY_AM_CONSTANTS, "");
            }
            Log.i(TAG, "Applied Browser & System ANR Guard (enable=" + enable + ")");
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "Failed to apply Browser ANR fix", t);
            return false;
        }
    }

    public static boolean setVivaldiDialogShield(Context context, boolean enable) {
        ContentResolver cr = context.getContentResolver();
        try {
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
            Settings.Global.putInt(cr, KEY_DISABLE_BLURS, enable ? 1 : 0);
            float scale = enable ? 0.85f : 1.0f;
            setAnimationScale(context, scale);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "Failed to apply Smoothness Fix", t);
            return false;
        }
    }

    public static boolean setAnimationScale(Context context, float scale) {
        ContentResolver cr = context.getContentResolver();
        try {
            Settings.Global.putFloat(cr, Settings.Global.WINDOW_ANIMATION_SCALE, scale);
            Settings.Global.putFloat(cr, Settings.Global.TRANSITION_ANIMATION_SCALE, scale);
            Settings.Global.putFloat(cr, Settings.Global.ANIMATOR_DURATION_SCALE, scale);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "Failed to set animation scale", t);
            return false;
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

    public static String buildLiveReport(Context context) {
        ContentResolver cr = context.getContentResolver();
        StringBuilder sb = new StringBuilder();

        String freezer = Settings.Global.getString(cr, KEY_CACHED_FREEZER);
        String amc = Settings.Global.getString(cr, KEY_AM_CONSTANTS);
        int bgAnr = Settings.Secure.getInt(cr, KEY_ANR_SHOW_BG, 0);
        int hideDialogs = Settings.Global.getInt(cr, KEY_HIDE_ERROR_DIALOGS, 0);
        int noBlurs = Settings.Global.getInt(cr, KEY_DISABLE_BLURS, 0);
        float anim = Settings.Global.getFloat(cr, Settings.Global.ANIMATOR_DURATION_SCALE, 1.0f);

        sb.append("=== ANR GUARD CONFIGURATION ===\n");
        sb.append("Cached Apps Freezer : ").append(freezer != null ? freezer : "default (enabled)").append("\n");
        sb.append("Background ANR Popup: ").append(bgAnr == 0 ? "Suppressed (0)" : "Shown (1)").append("\n");
        sb.append("Vivaldi Modal Shield: ").append(hideDialogs == 1 ? "ACTIVE (dialogs suppressed)" : "Standard").append("\n");
        sb.append("Window Blurs (GPU)  : ").append(noBlurs == 1 ? "Disabled (Fast)" : "Enabled").append("\n");
        sb.append("Animation Scale     : ").append(String.format(Locale.US, "%.2fx", anim)).append("\n");
        sb.append("AM Constants        : ").append(amc != null && !amc.isEmpty() ? amc : "stock defaults").append("\n\n");

        sb.append("=== RECENT DROPBOX ANR EVENTS (24H) ===\n");
        sb.append(readRecentDropBoxAnrs(context));
        return sb.toString();
    }

    private static String readRecentDropBoxAnrs(Context context) {
        try {
            DropBoxManager dbm = context.getSystemService(DropBoxManager.class);
            if (dbm == null) return "DropBoxManager unavailable.\n";

            String[] tags = {"data_app_anr", "system_app_anr", "system_server_anr"};
            SimpleDateFormat sdf = new SimpleDateFormat("MM-dd HH:mm:ss", Locale.US);
            StringBuilder out = new StringBuilder();
            int found = 0;

            for (String tag : tags) {
                long time = System.currentTimeMillis() - (24L * 3600L * 1000L);
                while (time > 0) {
                    DropBoxManager.Entry entry = dbm.getNextEntry(tag, time);
                    if (entry == null) break;
                    time = entry.getTimeMillis();
                    String snippet = entry.getText(320);
                    entry.close();
                    found++;
                    out.append("[").append(sdf.format(new Date(time))).append("] ").append(tag).append("\n");
                    if (snippet != null) {
                        for (String line : snippet.split("\n")) {
                            if (line.startsWith("Process:") || line.startsWith("Subject:")
                                    || line.startsWith("Package:")) {
                                out.append("  ").append(line.trim()).append("\n");
                            }
                        }
                    }
                    if (found >= 5) break;
                }
            }
            if (found == 0) {
                return "Zero ANRs recorded in the last 24 hours.\n";
            }
            return out.toString();
        } catch (Throwable t) {
            return "DropBox query restricted (" + t.getClass().getSimpleName() + ").\n";
        }
    }

    // =========================================================================
    // 2. 4G LTE & VoLTE / IMS Radio Lab (Works with and without SIM Card)
    // =========================================================================

    public static boolean setPreferredNetworkBitmask(Context context, long rafBitmask) {
        try {
            TelephonyManager tm = context.getSystemService(TelephonyManager.class);
            if (tm == null) return false;
            // ALLOWED_NETWORK_TYPES_REASON_USER = 0
            Method m = TelephonyManager.class.getMethod(
                    "setAllowedNetworkTypesForReason", int.class, long.class);
            m.invoke(tm, 0, rafBitmask);
            // Also persist preferred_network_mode in Global Settings (11 = LTE_ONLY, 9 = LTE_GSM_WCDMA)
            int mode = (rafBitmask == RAF_LTE_ONLY) ? 11 : 9;
            Settings.Global.putInt(context.getContentResolver(), "preferred_network_mode", mode);
            Settings.Global.putInt(context.getContentResolver(), "preferred_network_mode1", mode);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "setPreferredNetworkBitmask failed", t);
            return false;
        }
    }

    public static void triggerSimlessVoLteRegistration(Context context) {
        try {
            // Send AOS_TEST registration trigger to com.android.imsstack
            Intent intent = new Intent("com.android.imsstack.action.INTENT_AOS_TEST");
            intent.setPackage("com.android.imsstack");
            intent.putExtra("slotId", 0);
            intent.putExtra("code", 1); // EVENT_IMS_REGISTRATION_STATE
            // 0 = NORMAL, 1 = LTE, 0x0F = MMTEL|VIDEO|SMSIP|USSI, 1 = REGISTERED
            intent.putExtra("data", "0,1,15,1");
            context.sendBroadcast(intent);
        } catch (Throwable t) {
            Log.e(TAG, "triggerSimlessVoLteRegistration failed", t);
        }
    }

    public static boolean openRadioInfo(Context context) {
        try {
            Intent i = new Intent(Intent.ACTION_MAIN);
            i.setComponent(new ComponentName(
                    "com.android.phone", "com.android.phone.settings.RadioInfo"));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(i);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "openRadioInfo failed", t);
            return false;
        }
    }

    public static boolean openImsStackConfig(Context context) {
        try {
            Intent i = new Intent(Intent.ACTION_MAIN);
            i.setComponent(new ComponentName(
                    "com.android.imsstack", "com.android.imsstack.debug.ConfigActivity"));
            i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            context.startActivity(i);
            return true;
        } catch (Throwable t) {
            Log.e(TAG, "openImsStackConfig failed", t);
            return false;
        }
    }

    public static String buildRadioAndImsReport(Context context) {
        StringBuilder sb = new StringBuilder();
        try {
            TelephonyManager tm = context.getSystemService(TelephonyManager.class);
            if (tm == null) return "TelephonyManager unavailable.\n";

            sb.append("=== IMS & VoLTE STATUS ===\n");
            boolean imsReg = false;
            try {
                Method mIms = TelephonyManager.class.getMethod("isImsRegistered");
                Object res = mIms.invoke(tm);
                if (res instanceof Boolean) imsReg = (Boolean) res;
            } catch (Throwable ignored) {}

            sb.append("IMS Registration    : ").append(imsReg ? "REGISTERED (VoLTE Ready)" : "Not Registered").append("\n");
            sb.append("Voice over LTE      : ").append(imsReg ? "Available (MMTEL)" : "Standby").append("\n");
            sb.append("Video Calling (ViLTE): ").append(imsReg ? "Available" : "Standby").append("\n");
            sb.append("UT Supplementary    : ").append(imsReg ? "Available (XCAP/UT)" : "Standby").append("\n");
            sb.append("IMS Stack Backend   : com.android.imsstack (Simulated HAL Ready)\n\n");

            sb.append("=== RIL & MODEM RADIO STATE (SLOT 0) ===\n");
            int simState = tm.getSimState();
            sb.append("SIM Card State      : ").append(simStateToString(simState)).append("\n");

            long allowedRaf = -1;
            try {
                Method mGetRaf = TelephonyManager.class.getMethod("getAllowedNetworkTypesForReason", int.class);
                Object r = mGetRaf.invoke(tm, 0);
                if (r instanceof Long) allowedRaf = (Long) r;
            } catch (Throwable ignored) {}
            sb.append("Allowed Network RAF : ").append(allowedRaf)
              .append(allowedRaf == RAF_LTE_ONLY ? " (4G LTE ONLY)" : " (Multi-RAT Auto)").append("\n");

            ServiceState ss = null;
            try {
                Method mSs = TelephonyManager.class.getMethod("getServiceStateForSlot", int.class);
                ss = (ServiceState) mSs.invoke(tm, 0);
            } catch (Throwable ignored) {
                ss = tm.getServiceState();
            }

            if (ss != null) {
                sb.append("Service State       : ").append(serviceStateToString(ss.getState())).append("\n");
                sb.append("Operator            : ").append(ss.getOperatorAlphaLong()).append("\n");
                try {
                    Method mVoiceRat = ServiceState.class.getMethod("getRilVoiceRadioTechnology");
                    Method mDataRat = ServiceState.class.getMethod("getRilDataRadioTechnology");
                    Method mRatStr = ServiceState.class.getMethod("rilRadioTechnologyToString", int.class);
                    int vRat = (Integer) mVoiceRat.invoke(ss);
                    int dRat = (Integer) mDataRat.invoke(ss);
                    sb.append("Voice Radio Tech    : ").append(mRatStr.invoke(null, vRat)).append("\n");
                    sb.append("Data Radio Tech     : ").append(mRatStr.invoke(null, dRat)).append("\n");
                } catch (Throwable ignored) {}
            }

            sb.append("\n=== LIVE CELL TOWERS (LTE / WCDMA / GSM) ===\n");
            List<CellInfo> cells = tm.getAllCellInfo();
            if (cells == null || cells.isEmpty()) {
                sb.append("  (No cell info reported or location off)\n");
            } else {
                int count = 0;
                for (CellInfo ci : cells) {
                    if (count++ >= 8) break;
                    if (ci instanceof CellInfoLte) {
                        CellInfoLte lte = (CellInfoLte) ci;
                        CellIdentityLte cid = lte.getCellIdentity();
                        CellSignalStrengthLte sig = lte.getCellSignalStrength();
                        sb.append(String.format(Locale.US,
                                "  [LTE%s] MCC/MNC=%s/%s PCI=%d EARFCN=%d RSRP=%d dBm RSRQ=%d dB\n",
                                ci.isRegistered() ? "*" : "",
                                cid.getMccString(), cid.getMncString(),
                                cid.getPci(), cid.getEarfcn(),
                                sig.getRsrp(), sig.getRsrq()));
                    } else if (ci instanceof CellInfoWcdma) {
                        CellInfoWcdma w = (CellInfoWcdma) ci;
                        CellIdentityWcdma cid = w.getCellIdentity();
                        sb.append(String.format(Locale.US,
                                "  [WCDMA%s] MCC/MNC=%s/%s PSC=%d UARFCN=%d dBm=%d\n",
                                ci.isRegistered() ? "*" : "",
                                cid.getMccString(), cid.getMncString(),
                                cid.getPsc(), cid.getUarfcn(),
                                w.getCellSignalStrength().getDbm()));
                    } else if (ci instanceof CellInfoGsm) {
                        CellInfoGsm g = (CellInfoGsm) ci;
                        CellIdentityGsm cid = g.getCellIdentity();
                        sb.append(String.format(Locale.US,
                                "  [GSM%s] MCC/MNC=%s/%s ARFCN=%d dBm=%d\n",
                                ci.isRegistered() ? "*" : "",
                                cid.getMccString(), cid.getMncString(),
                                cid.getArfcn(),
                                g.getCellSignalStrength().getDbm()));
                    }
                }
            }
        } catch (Throwable t) {
            sb.append("Radio telemetry error: ").append(t.getMessage()).append("\n");
        }
        return sb.toString();
    }

    private static String simStateToString(int state) {
        switch (state) {
            case TelephonyManager.SIM_STATE_ABSENT: return "ABSENT (SIM-less Testing Mode)";
            case TelephonyManager.SIM_STATE_READY: return "READY";
            case TelephonyManager.SIM_STATE_PIN_REQUIRED: return "PIN_REQUIRED";
            case TelephonyManager.SIM_STATE_PUK_REQUIRED: return "PUK_REQUIRED";
            default: return "STATE_" + state;
        }
    }

    private static String serviceStateToString(int state) {
        switch (state) {
            case ServiceState.STATE_IN_SERVICE: return "IN_SERVICE";
            case ServiceState.STATE_OUT_OF_SERVICE: return "OUT_OF_SERVICE (Emergency/Camped)";
            case ServiceState.STATE_EMERGENCY_ONLY: return "EMERGENCY_ONLY";
            case ServiceState.STATE_POWER_OFF: return "RADIO_OFF";
            default: return "STATE_" + state;
        }
    }

    // =========================================================================
    // 3. Kernel, Memory, ZRAM, PSI & Top Processes Monitor (merged from XtStatus)
    // =========================================================================

    public static String buildKernelAndMemoryReport() {
        StringBuilder sb = new StringBuilder();

        sb.append("=== MEMORY (/proc/meminfo) ===\n");
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
            sb.append(String.format(Locale.US,
                    "  Available: %.0f%% of total (%.2f GB available)\n",
                    avail * 100.0 / total, avail / 1024.0 / 1024.0));
        }

        sb.append("\n=== ZRAM (/proc/swaps) ===\n");
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

        sb.append("\n=== PRESSURE STALL INFORMATION (PSI) ===\n");
        for (String res : new String[] { "cpu", "memory", "io" }) {
            for (String line : lines("/proc/pressure/" + res)) {
                sb.append("  [").append(res).append("] ").append(line.trim()).append('\n');
            }
        }

        sb.append("\n=== CPU & LOAD AVERAGE ===\n");
        for (String line : lines("/proc/loadavg")) {
            sb.append("  LoadAvg : ").append(line.trim()).append('\n');
        }
        sb.append("  LITTLE (A53 cpu0): ").append(readFirstLine("/sys/devices/system/cpu/cpu0/cpufreq/scaling_cur_freq")).append(" kHz\n");
        sb.append("  BIG    (A73 cpu4): ").append(readFirstLine("/sys/devices/system/cpu/cpu4/cpufreq/scaling_cur_freq")).append(" kHz\n");

        sb.append("\n=== TOP 10 PROCESSES BY RSS ===\n");
        sb.append(readTopProcesses());

        sb.append("\n=== KERNEL & BUILD ===\n");
        sb.append("  Kernel  : ").append(System.getProperty("os.version", "unknown")).append('\n');
        sb.append("  Display : ").append(android.os.Build.DISPLAY).append('\n');
        return sb.toString();
    }

    private static String readTopProcesses() {
        File proc = new File("/proc");
        String[] pids = proc.list();
        if (pids == null) return "  (unreadable)\n";

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
            if (ok) {
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
            if (shown++ >= 10) break;
            sb.append(String.format(Locale.US, "  %8d kB  %s\n", sizes.get(idx)[0], names.get(idx)));
        }
        return sb.toString();
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
    // 4. Theme & Overlay Manager (merged from XtThemes)
    // =========================================================================

    public static boolean resetToStockTheme(Context context) {
        OverlayManager om = context.getSystemService(OverlayManager.class);
        if (om == null) return false;
        String[] toDisable = {
            "os.theme.nothing",
            "os.theme.nothinglight",
            "os.theme.monet",
            "os.theme.stock",
            "com.android.theme.font.nothingdot",
            "com.android.theme.lockscreen_clock_font.nothingdotheadline",
            "com.android.system.theme.black"
        };
        for (String pkg : toDisable) {
            try {
                om.setEnabled(pkg, false, UserHandle.SYSTEM);
            } catch (Throwable ignored) {}
        }
        return true;
    }

    public static boolean applyThemeOverlay(Context context, String pkg) {
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

    public static String getActiveThemeSummary(Context context) {
        OverlayManager om = context.getSystemService(OverlayManager.class);
        if (om == null) return "OverlayManager unavailable";
        StringBuilder enabled = new StringBuilder();
        try {
            List<OverlayInfo> infos = om.getOverlayInfosForTarget("android", UserHandle.SYSTEM);
            for (OverlayInfo info : infos) {
                if (!info.isEnabled()) continue;
                for (String[] theme : THEMES) {
                    if (theme[0].equals(info.getPackageName())) {
                        if (enabled.length() > 0) enabled.append(", ");
                        enabled.append(theme[1]);
                    }
                }
            }
        } catch (Throwable t) {
            return "Overlay query error: " + t.getMessage();
        }
        return enabled.length() == 0
                ? "Stock Infinity-X / AOSP (Default)"
                : enabled.toString();
    }
}
