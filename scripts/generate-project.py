#!/usr/bin/env python3
"""Generate a dependency-free Xcode app and hosted Swift Testing target."""
import hashlib
from pathlib import Path
root = Path(__file__).resolve().parent.parent
objects = {}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, body):
    key = uid(name); objects[key] = body; return key
def q(s): return '"' + str(s).replace('"', '\\"') + '"'
def refs(ids): return '(' + ', '.join(ids) + ')'
source_files = sorted(root.glob('Sources/Conch/*.swift')) + [root/'Sources/Realtime/Realtime.c']
headers = [root/'Sources/Realtime/include/Realtime.h', root/'Sources/Realtime/include/module.modulemap']
tests = sorted(root.glob('Tests/ConchTests/*.swift'))
file_ids = {}
for path in source_files + headers + tests + [root/'Resources/Info.plist', root/'Resources/AppIcon.icon']:
    rel = str(path.relative_to(root))
    typ = {'.swift':'sourcecode.swift', '.c':'sourcecode.c.c', '.h':'sourcecode.c.h', '.plist':'text.plist.xml', '.icon':'folder.iconcomposer.icon'}.get(path.suffix,'sourcecode.module-map')
    file_ids[rel] = add(rel, f'isa = PBXFileReference; lastKnownFileType = {typ}; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
def phase(name, paths, kind='PBXSourcesBuildPhase'):
    # Stable IDs across local and CI checkout paths.
    builds = [add('build:'+name+str(p.relative_to(root)), f'isa = PBXBuildFile; fileRef = {file_ids[str(p.relative_to(root))]};') for p in paths]
    return add(name, f'isa = {kind}; buildActionMask = 2147483647; files = {refs(builds)}; runOnlyForDeploymentPostprocessing = 0;')
app_sources = phase('app-sources', source_files)
app_resources = phase('app-resources', [root/'Resources/AppIcon.icon'], 'PBXResourcesBuildPhase')
test_sources = phase('test-sources', tests)
app_product = add('app-product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = Conch.app; sourceTree = BUILT_PRODUCTS_DIR;')
test_product = add('test-product', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = ConchTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = add('products','isa = PBXGroup; name = Products; children = '+refs([app_product,test_product])+'; sourceTree = "<group>";')
group = add('root-group','isa = PBXGroup; children = '+refs(list(file_ids.values())+[products])+'; sourceTree = "<group>";')
def configs(name, common):
    configs = []
    for mode in ['Debug','Release']:
        settings = dict(common)
        settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if mode=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if mode=='Debug' else 'dwarf-with-dsym'})
        if mode=='Debug': settings['ENABLE_TESTABILITY']='YES'
        body=' '.join(f'{k} = {q(v)};' for k,v in settings.items())
        configs.append(add(name+mode, f'isa = XCBuildConfiguration; name = {mode}; buildSettings = {{ {body} }};'))
    return add(name+'configs','isa = XCConfigurationList; buildConfigurations = '+refs(configs)+'; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
common={'MACOSX_DEPLOYMENT_TARGET':'27.0','SDKROOT':'macosx','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','CLANG_C_LANGUAGE_STANDARD':'c11','SYMROOT':'$(SRCROOT)/.build/Xcode/Build/Products'}
project_configs=configs('project',common)
app_configs=configs('app',{'PRODUCT_NAME':'Conch','PRODUCT_BUNDLE_IDENTIFIER':'dev.conch.mixer','INFOPLIST_FILE':'Resources/Info.plist','SWIFT_INCLUDE_PATHS':'$(SRCROOT)/Sources/Realtime/include','HEADER_SEARCH_PATHS':'$(SRCROOT)/Sources/Realtime/include','CODE_SIGN_STYLE':'Automatic','ENABLE_HARDENED_RUNTIME':'YES','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon'})
test_configs=configs('tests',{'PRODUCT_NAME':'ConchTests','PRODUCT_BUNDLE_IDENTIFIER':'dev.conch.mixer.tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Conch.app/Contents/MacOS/Conch','BUNDLE_LOADER':'$(TEST_HOST)','SWIFT_INCLUDE_PATHS':'$(SRCROOT)/Sources/Realtime/include'})
app=add('app',f'isa = PBXNativeTarget; name = Conch; productName = Conch; productType = "com.apple.product-type.application"; productReference = {app_product}; buildConfigurationList = {app_configs}; buildPhases = {refs([app_sources,app_resources])}; buildRules = (); dependencies = ();')
proxy=add('proxy',f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {app}; remoteInfo = Conch;')
dep=add('test-dependency',f'isa = PBXTargetDependency; target = {app}; targetProxy = {proxy};')
test=add('tests',f'isa = PBXNativeTarget; name = ConchTests; productName = ConchTests; productType = "com.apple.product-type.bundle.unit-test"; productReference = {test_product}; buildConfigurationList = {test_configs}; buildPhases = {refs([test_sources])}; buildRules = (); dependencies = {refs([dep])};')
project=add('project',f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 2700; }}; buildConfigurationList = {project_configs}; compatibilityVersion = "Xcode 16.0"; developmentRegion = en; knownRegions = (en, Base); mainGroup = {group}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {refs([app,test])};')
(root/'Conch.xcodeproj/project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 77; objects = {\n'+'\n'.join(f'{key} = {{ {value} }};' for key,value in objects.items())+f'\n}}; rootObject = {project}; }}\n')
scheme=root/'Conch.xcodeproj/xcshareddata/xcschemes/Conch.xcscheme';scheme.parent.mkdir(parents=True,exist_ok=True)
def ref(key,name): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{key}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:Conch.xcodeproj"/>'
scheme.write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.7">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{ref(app,'Conch.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB"><Testables><TestableReference skipped="NO">{ref(test,'ConchTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'Conch.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release"><BuildableProductRunnable runnableDebuggingMode="0">{ref(app,'Conch.app')}</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print('Generated Conch.xcodeproj')
