#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
print 'Quit Conch and play build/synthetic-tone.wav in QuickTime before running this opt-in test.'
python3 scripts/generate-project.py
xcodebuild -project Conch.xcodeproj -scheme Conch -configuration Debug -derivedDataPath .build/Xcode CODE_SIGN_IDENTITY=- build-for-testing
python3 - <<'PY'
from pathlib import Path
import plistlib
products = Path('.build/Xcode/Build/Products')
source = next(p for p in products.glob('Conch_*.xctestrun'))
data = plistlib.loads(source.read_bytes())
targets = [t for c in data.get('TestConfigurations', []) for t in c.get('TestTargets', [])]
if not targets:
    targets = [v for k,v in data.items() if k != '__xctestrun_metadata__' and isinstance(v,dict)]
for target in targets:
    target.setdefault('EnvironmentVariables', {})['CONCH_LIVE_AUDIO_TEST'] = '1'
(products/'Conch-live.xctestrun').write_bytes(plistlib.dumps(data))
PY
xcodebuild test-without-building -xctestrun .build/Xcode/Build/Products/Conch-live.xctestrun -destination 'platform=macOS'
