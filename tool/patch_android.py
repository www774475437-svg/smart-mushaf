"""Adjusts the Android project that `flutter create` generates in CI."""
import os
import pathlib
import re
import shutil

app = pathlib.Path('android/app')
key = os.environ.get('KEY_PATH', '')
pw = os.environ.get('KEY_PASS', '')

kts = app / 'build.gradle.kts'
groovy = app / 'build.gradle'
if kts.exists():
    s = kts.read_text()
    if key and 'create("release")' not in s:
        block = (
            '    signingConfigs {\n'
            '        create("release") {\n'
            f'            storeFile = file("{key}")\n'
            f'            storePassword = "{pw}"\n'
            '            keyAlias = "mushaf"\n'
            f'            keyPassword = "{pw}"\n'
            '        }\n'
            '    }\n\n'
            '    buildTypes {'
        )
        s = re.sub(r'^\s*buildTypes\s*\{', '\n' + block, s, count=1, flags=re.M)
        s = s.replace('signingConfigs.getByName("debug")', 'signingConfigs.getByName("release")')
    s = re.sub(r'minSdk\s*=\s*flutter\.minSdkVersion', 'minSdk = 23', s)
    kts.write_text(s)
    print(s)
elif groovy.exists():
    s = groovy.read_text()
    if key and 'signingConfigs' not in s:
        block = (
            '    signingConfigs {\n'
            '        release {\n'
            f'            storeFile file("{key}")\n'
            f'            storePassword "{pw}"\n'
            '            keyAlias "mushaf"\n'
            f'            keyPassword "{pw}"\n'
            '        }\n'
            '    }\n\n'
            '    buildTypes {'
        )
        s = re.sub(r'^\s*buildTypes\s*\{', '\n' + block, s, count=1, flags=re.M)
        s = s.replace('signingConfig signingConfigs.debug', 'signingConfig signingConfigs.release')
    s = re.sub(r'minSdkVersion\s+flutter\.minSdkVersion', 'minSdkVersion 23', s)
    groovy.write_text(s)

man = app / 'src/main/AndroidManifest.xml'
m = man.read_text()
perms = (
    '    <uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-permission android:name="android.permission.RECORD_AUDIO"/>\n'
    '    <uses-permission android:name="android.permission.WAKE_LOCK"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION"/>\n'
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION"/>\n'
    '    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>\n'
)
if 'android.permission.INTERNET' not in m:
    m = re.sub(r'(<manifest[^>]*>)', r'\1\n' + perms, m, count=1)
m = re.sub(r'android:label="[^"]*"', 'android:label="المصحف الذكي"', m, count=1)
# background playback with lock-screen controls (just_audio_background)
m = m.replace('android:name=".MainActivity"', 'android:name="com.ryanheise.audioservice.AudioServiceActivity"')
if 'com.ryanheise.audioservice.AudioService"' not in m:
    svc = (
        '        <service android:name="com.ryanheise.audioservice.AudioService"\n'
        '            android:foregroundServiceType="mediaPlayback" android:exported="true">\n'
        '            <intent-filter><action android:name="android.media.browse.MediaBrowserService"/></intent-filter>\n'
        '        </service>\n'
        '        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver" android:exported="true">\n'
        '            <intent-filter><action android:name="android.intent.action.MEDIA_BUTTON"/></intent-filter>\n'
        '        </receiver>\n'
    )
    m = m.replace('</application>', svc + '    </application>', 1)

extra = (
    '        <intent><action android:name="android.speech.RecognitionService"/></intent>\n'
    '        <intent><action android:name="android.intent.action.TTS_SERVICE"/></intent>\n'
    '        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>\n'
)
if '<queries>' in m:
    m = m.replace('<queries>', '<queries>\n' + extra, 1)
else:
    m = m.replace('</manifest>', '    <queries>\n' + extra + '    </queries>\n</manifest>')
man.write_text(m)
print(m)

res = app / 'src/main/res'
for d in pathlib.Path('tool/res').iterdir():
    tgt = res / d.name
    tgt.mkdir(parents=True, exist_ok=True)
    for f in d.iterdir():
        shutil.copy(f, tgt / f.name)

# ---------------- home-screen widgets ----------------
WIDGETS = [
    ('PrayerWidget', 'أوقات الصلاة', 250, 80),
    ('ContinueWidget', 'متابعة القراءة', 180, 60),
    ('KhatmaWidget', 'ورد الختمة', 180, 60),
    ('AyahWidget', 'آية اليوم', 250, 80),
    ('ReviewWidget', 'مراجعة اليوم', 180, 60),
    ('StreakWidget', 'أيام متتالية', 110, 60),
    ('TasmeeWidget', 'تسميع سريع', 110, 60),
    ('PlayerWidget', 'تشغيل التلاوة', 180, 60),
    ('MajlisWidget', 'مجلس الحفاظ', 180, 60),
    ('FawasilWidget', 'الفواصل', 250, 60),
]
kdir = None
for d in (app / 'src/main/kotlin').rglob('MainActivity.kt'):
    kdir = d.parent
if kdir is None:
    kdir = app / 'src/main/kotlin/com/abualathari/smart_mushaf'
    kdir.mkdir(parents=True, exist_ok=True)
shutil.copy('tool/widgets/Widgets.kt', kdir / 'Widgets.kt')
(res / 'drawable').mkdir(parents=True, exist_ok=True)
(res / 'layout').mkdir(parents=True, exist_ok=True)
(res / 'xml').mkdir(parents=True, exist_ok=True)
(res / 'drawable/widget_bg.xml').write_text("""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <gradient android:angle="315" android:startColor="#0B4436" android:endColor="#167A61"/>
    <corners android:radius="22dp"/>
</shape>
""")
(res / 'drawable/widget_cell.xml').write_text("""<?xml version="1.0" encoding="utf-8"?>
<shape xmlns:android="http://schemas.android.com/apk/res/android" android:shape="rectangle">
    <solid android:color="#22FFFFFF"/>
    <corners android:radius="14dp"/>
</shape>
""")
(res / 'layout/widget_card.xml').write_text("""<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:id="@+id/w_root" android:layout_width="match_parent" android:layout_height="match_parent"
    android:orientation="vertical" android:gravity="center" android:padding="12dp"
    android:layoutDirection="rtl" android:background="@drawable/widget_bg">
    <TextView android:id="@+id/w_title" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:gravity="center" android:textColor="#E3C66B" android:textSize="12sp" android:maxLines="1"/>
    <TextView android:id="@+id/w_main" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:gravity="center" android:textColor="#FFFFFF" android:textSize="19sp" android:textStyle="bold"
        android:maxLines="2" android:ellipsize="end" android:paddingTop="2dp"/>
    <TextView android:id="@+id/w_sub" android:layout_width="match_parent" android:layout_height="wrap_content"
        android:gravity="center" android:textColor="#CCFFFFFF" android:textSize="11sp" android:maxLines="2"
        android:ellipsize="end" android:paddingTop="2dp"/>
</LinearLayout>
""")
cells = ''
for i, colr in enumerate(['#F08A80', '#F1D06B', '#8FD19A', '#8DB8F0']):
    cells += f"""    <TextView android:id="@+id/f{i}" android:layout_width="0dp" android:layout_height="match_parent"
        android:layout_weight="1" android:layout_margin="3dp" android:gravity="center" android:textColor="{colr}"
        android:textSize="12sp" android:textStyle="bold" android:maxLines="2" android:background="@drawable/widget_cell"/>
"""
(res / 'layout/widget_fawasil.xml').write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<LinearLayout xmlns:android="http://schemas.android.com/apk/res/android"
    android:layout_width="match_parent" android:layout_height="match_parent" android:orientation="horizontal"
    android:padding="8dp" android:layoutDirection="rtl" android:background="@drawable/widget_bg">
{cells}</LinearLayout>
""")
recv = ''
for name, label, w, h in WIDGETS:
    layout = 'widget_fawasil' if name == 'FawasilWidget' else 'widget_card'
    (res / f'xml/w_{name.lower()}.xml').write_text(f"""<?xml version="1.0" encoding="utf-8"?>
<appwidget-provider xmlns:android="http://schemas.android.com/apk/res/android"
    android:minWidth="{w}dp" android:minHeight="{h}dp" android:updatePeriodMillis="1800000"
    android:initialLayout="@layout/{layout}" android:resizeMode="horizontal|vertical"
    android:widgetCategory="home_screen"/>
""")
    recv += (
        f'        <receiver android:name=".{name}" android:exported="true" android:label="{label}">\n'
        '            <intent-filter><action android:name="android.appwidget.action.APPWIDGET_UPDATE"/></intent-filter>\n'
        f'            <meta-data android:name="android.appwidget.provider" android:resource="@xml/w_{name.lower()}"/>\n'
        '        </receiver>\n'
    )
m = man.read_text()
if '.PrayerWidget' not in m:
    m = m.replace('</application>', recv + '    </application>', 1)
    # links from the widgets open the app
    m = m.replace('<category android:name="android.intent.category.LAUNCHER"/>\n            </intent-filter>',
                  '<category android:name="android.intent.category.LAUNCHER"/>\n            </intent-filter>\n'
                  '            <intent-filter><action android:name="es.antonborri.home_widget.action.LAUNCH"/></intent-filter>', 1)
    if 'home_widget.action.LAUNCH' not in m:
        m = re.sub(r'(</intent-filter>)', r'\1\n            <intent-filter><action android:name="es.antonborri.home_widget.action.LAUNCH"/></intent-filter>', m, count=1)
    man.write_text(m)
print('android patched')
