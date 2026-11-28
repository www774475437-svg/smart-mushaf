"""Prepare the generated iOS project: name, permissions, background audio, icon, team."""
import json, os, pathlib, plistlib, re
from PIL import Image

ios = pathlib.Path('ios')
p = ios / 'Runner/Info.plist'
d = plistlib.loads(p.read_bytes())
d['CFBundleDisplayName'] = 'المصحف الذكي'
d['CFBundleName'] = 'SmartMushaf'
d['CFBundleDevelopmentRegion'] = 'ar'
d['CFBundleLocalizations'] = ['ar', 'en']
d['ITSAppUsesNonExemptEncryption'] = False
d['UIBackgroundModes'] = ['audio']
d['NSMicrophoneUsageDescription'] = 'يُستخدم الميكروفون لتسميع حفظك من القرآن وتصحيح الأخطاء.'
d['NSSpeechRecognitionUsageDescription'] = 'يُستخدم التعرّف على الصوت لمتابعة تلاوتك أثناء التسميع.'
d['NSLocationWhenInUseUsageDescription'] = 'يُستخدم موقعك لحساب أوقات الصلاة واتجاه القبلة.'
d['NSLocationAlwaysAndWhenInUseUsageDescription'] = 'يُستخدم موقعك لحساب أوقات الصلاة واتجاه القبلة.'
d['NSLocationAlwaysUsageDescription'] = 'يُستخدم موقعك لحساب أوقات الصلاة واتجاه القبلة.'
p.write_bytes(plistlib.dumps(d))

# deployment target (the speech and recognition plugins need a recent iOS)
pod = ios / 'Podfile'
if pod.exists():
    s = pod.read_text()
    s = re.sub(r"#?\s*platform :ios, '[\d.]+'", "platform :ios, '13.0'", s, count=1)
    pod.write_text(s)
pbx = ios / 'Runner.xcodeproj/project.pbxproj'
s = pbx.read_text()
s = re.sub(r'IPHONEOS_DEPLOYMENT_TARGET = [\d.]+;', 'IPHONEOS_DEPLOYMENT_TARGET = 13.0;', s)
team = os.environ.get('APPLE_TEAM_ID', '')
if team:
    s = s.replace('PRODUCT_BUNDLE_IDENTIFIER = com.abualathari.smartMushaf;',
                  'PRODUCT_BUNDLE_IDENTIFIER = com.abualathari.smartMushaf;\n\t\t\t\tDEVELOPMENT_TEAM = %s;' % team)
pbx.write_text(s)

# app icon (no transparency allowed by the App Store)
logo = Image.open('assets/images/logo.png').convert('RGB')
big = logo.resize((1024, 1024), Image.LANCZOS)
ic = ios / 'Runner/Assets.xcassets/AppIcon.appiconset'
for e in json.loads((ic / 'Contents.json').read_text())['images']:
    if 'filename' not in e:
        continue
    px = round(float(e['size'].split('x')[0]) * int(e['scale'][0]))
    big.resize((px, px), Image.LANCZOS).save(ic / e['filename'])
print('ios patched', 'team set' if team else 'no team')
