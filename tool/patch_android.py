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
print('android patched')
