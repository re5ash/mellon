from pathlib import Path
import json,re,sys
root=Path(__file__).resolve().parents[1]
errors=[]
for p in (root/'lib').rglob('*.dart'):
 text=p.read_text()
 for imp in re.findall(r"import '([^']+)'",text):
  if not imp.startswith(('dart:','package:')) and not (p.parent/imp).resolve().exists(): errors.append(f'Missing import in {p}: {imp}')
 if re.search(r"import 'dart:(io|html)'",text): errors.append(f'Web-incompatible import: {p}')
 if 'service_role' in text or 'sb_secret_' in text: errors.append(f'Server key marker in client code: {p}')
 if 'features' in p.parts and ('Color(0x' in text or 'Color.from' in text): errors.append(f'Local palette in feature: {p}')
manifest=json.loads((root/'web/manifest.json').read_text())
for icon in manifest['icons']:
 if not (root/'web'/icon['src']).exists():errors.append(f'Missing icon {icon}')
if errors:
 print('\n'.join(errors));sys.exit(1)
print('PASS imports, Web-compatible imports, client key boundary, palette centralization, PWA icon references')
