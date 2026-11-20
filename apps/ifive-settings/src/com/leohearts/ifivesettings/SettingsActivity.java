package com.leohearts.ifivesettings;

import android.app.Activity;
import android.content.Context;
import android.os.Bundle;
import android.preference.ListPreference;
import android.preference.Preference;
import android.preference.PreferenceFragment;
import android.preference.PreferenceScreen;
import android.preference.SwitchPreference;
import android.widget.Toast;

/*
 * Each switch maps to one thing init or the framework already reads:
 *  - deep Doze: persist.vendor.ifive.deep_doze; init copies it to ro.vendor.ifive.deep_doze,
 *    which gates the static overlay com.leohearts.overlay.deepdoze
 *    (config_autoPowerModeUseMotionSensor=false) at the next boot;
 *  - charger boost: persist.vendor.chg.boost, init.rk3288.rc writes rn5t618 chg_boost;
 *  - kernel deep sleep: persist.vendor.ifive.deep_sleep, init writes /sys/module/pm/parameters/deep_sleep;
 *  - DDR: persist.vendor.ifive.ddr_freq (396 or 456), init writes the dmc-cros userspace set_freq.
 * SystemProperties is not in the public SDK, so it is called by reflection; the
 * SELinux rules that let priv_app set these properties live in the vendor image.
 */
public class SettingsActivity extends Activity {
    @Override
    protected void onCreate(Bundle b) {
        super.onCreate(b);
        if (b == null) {
            getFragmentManager().beginTransaction()
                    .replace(android.R.id.content, new Prefs()).commit();
        }
    }

    public static class Prefs extends PreferenceFragment {
        @Override
        public void onCreate(Bundle b) {
            super.onCreate(b);
            Context c = getActivity();
            PreferenceScreen s = getPreferenceManager().createPreferenceScreen(c);
            setPreferenceScreen(s);

            s.addPreference(sw(c, R.string.doze_title, R.string.doze_summary,
                    !"0".equals(prop("persist.vendor.ifive.deep_doze")),
                    v -> setProp("persist.vendor.ifive.deep_doze", v ? "1" : "0") && rebootNote(c)));
            s.addPreference(sw(c, R.string.sleep_title, R.string.sleep_summary,
                    !"0".equals(prop("persist.vendor.ifive.deep_sleep")),
                    v -> setProp("persist.vendor.ifive.deep_sleep", v ? "1" : "0")));
            String ddr = prop("persist.vendor.ifive.ddr_freq");
            s.addPreference(list(c, R.string.ddr_title, R.array.ddr_entries,
                    new String[] {"456", "396"}, ddr.isEmpty() ? "456" : ddr,
                    v -> setProp("persist.vendor.ifive.ddr_freq", v)));

            String chg = prop("persist.vendor.chg.boost");
            s.addPreference(list(c, R.string.chg_title, R.array.chg_entries,
                    new String[] {"auto", "on", "off"}, chg.isEmpty() ? "auto" : chg,
                    v -> setProp("persist.vendor.chg.boost", v)));
        }
    }

    interface Apply { boolean set(boolean v); }
    interface ApplyValue { boolean set(String v); }

    static ListPreference list(Context c, int title, int entries, String[] values, String cur,
            ApplyValue a) {
        ListPreference p = new ListPreference(c);
        p.setPersistent(false);
        p.setTitle(title);
        p.setDialogTitle(title);
        p.setEntries(entries);
        p.setEntryValues(values);
        p.setValue(cur);
        p.setSummary("%s");
        p.setOnPreferenceChangeListener((pref, v) -> a.set((String) v));
        return p;
    }

    static SwitchPreference sw(Context c, int title, int summary, boolean on, Apply a) {
        SwitchPreference p = new SwitchPreference(c);
        p.setPersistent(false);
        p.setTitle(title);
        p.setSummary(summary);
        p.setChecked(on);
        p.setOnPreferenceChangeListener((pref, v) -> a.set((Boolean) v));
        return p;
    }

    static boolean rebootNote(Context c) {
        Toast.makeText(c, R.string.reboot_note, Toast.LENGTH_LONG).show();
        return true;
    }

    static String prop(String k) {
        try {
            return (String) Class.forName("android.os.SystemProperties")
                    .getMethod("get", String.class).invoke(null, k);
        } catch (ReflectiveOperationException e) {
            return "";
        }
    }

    static boolean setProp(String k, String v) {
        try {
            Class.forName("android.os.SystemProperties")
                    .getMethod("set", String.class, String.class).invoke(null, k, v);
            return true;
        } catch (ReflectiveOperationException e) {
            return false;
        }
    }
}
