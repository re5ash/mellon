from pathlib import Path
import xml.etree.ElementTree as ET
import re
root=Path(__file__).resolve().parents[1]
a='http://schemas.android.com/apk/res/android'
ET.register_namespace('android',a)
p=root/'android/app/src/main/AndroidManifest.xml'
tree=ET.parse(p);manifest=tree.getroot()
if not any(e.get('{'+a+'}name')=='android.permission.INTERNET' for e in manifest.findall('uses-permission')):
 ET.SubElement(manifest,'uses-permission',{'{'+a+'}name':'android.permission.INTERNET'})
app=manifest.find('application');app.set('{'+a+'}label','Mellon');app.set('{'+a+'}allowBackup','false')
activity=app.find('activity')
activity.set('{'+a+'}windowSoftInputMode','adjustResize')
f=ET.SubElement(activity,'intent-filter')
ET.SubElement(f,'action',{'{'+a+'}name':'android.intent.action.VIEW'})
for category in ['android.intent.category.DEFAULT','android.intent.category.BROWSABLE']:
 ET.SubElement(f,'category',{'{'+a+'}name':category})
ET.SubElement(f,'data',{'{'+a+'}scheme':'org.moyprihod.app','{'+a+'}host':'login-callback'})
ET.indent(tree);tree.write(p,encoding='utf-8',xml_declaration=True)
gradle=root/'android/app/build.gradle.kts'
text=gradle.read_text();text=re.sub(r'minSdk\s*=\s*flutter.minSdkVersion','minSdk = maxOf(24, flutter.minSdkVersion)',text)
gradle.write_text(text)
print('Android: Internet permission, Auth callback, backup disabled, adaptive keyboard; minimum API 24.')
