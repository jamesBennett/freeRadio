#!/usr/bin/env python3
"""Regenerate the dependency-free Xcode project from the Swift source folders."""
from pathlib import Path
import hashlib
root = Path(__file__).resolve().parent.parent
objects = []
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def add(name, body):
    key = uid(name); objects.append(f'{key} = {{ {body} }};'); return key
def array(items): return '(' + ', '.join(items) + (',' if items else '') + ')'
def quote(value): return '"' + value.replace('"', '\\"') + '"'
appfiles = sorted(root.glob('FreeRadio/**/*.swift'))
testfiles = sorted(root.glob('FreeRadioTests/**/*.swift'))
refs = {}; builds = {}
for path in appfiles + testfiles:
    name = str(path.relative_to(root))
    refs[name] = add('ref:'+name, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {quote(name)}; sourceTree = SOURCE_ROOT;')
    builds[name] = add('build:'+name, f'isa = PBXBuildFile; fileRef = {refs[name]};')
appProduct = add('appProduct', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = FreeRadio.app; sourceTree = BUILT_PRODUCTS_DIR;')
testProduct = add('testProduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = FreeRadioTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
signing = add('ref:Config/Signing.xcconfig', 'isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = "Config/Signing.xcconfig"; sourceTree = SOURCE_ROOT;')
products = add('products', f'isa = PBXGroup; children = {array([appProduct,testProduct])}; name = Products; sourceTree = "<group>";')
main = add('main', f'isa = PBXGroup; children = {array(list(refs.values())+[signing,products])}; sourceTree = "<group>";')
def configs(name, common, baseConfig=None):
    ids=[]
    for kind in ['Debug','Release']:
        settings=dict(common)
        settings.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone' if kind=='Debug' else '-O','DEBUG_INFORMATION_FORMAT':'dwarf' if kind=='Debug' else 'dwarf-with-dsym'})
        if kind=='Debug': settings.update({'ENABLE_TESTABILITY':'YES','SWIFT_ACTIVE_COMPILATION_CONDITIONS':'DEBUG'})
        body=' '.join(f'{k} = {quote(v)};' for k,v in settings.items())
        base = f'baseConfigurationReference = {baseConfig}; ' if baseConfig else ''
        ids.append(add(name+kind, f'isa = XCBuildConfiguration; {base}buildSettings = {{ {body} }}; name = {kind};'))
    return add(name+'configs', f'isa = XCConfigurationList; buildConfigurations = {array(ids)}; defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
projectConfigs=configs('project',{'IPHONEOS_DEPLOYMENT_TARGET':'18.0','SDKROOT':'iphoneos','SWIFT_VERSION':'5.0','CLANG_ENABLE_MODULES':'YES','GCC_C_LANGUAGE_STANDARD':'gnu17','SWIFT_STRICT_CONCURRENCY':'targeted'},signing)
base={'CODE_SIGN_STYLE':'Automatic','CURRENT_PROJECT_VERSION':'1','MARKETING_VERSION':'0.1','TARGETED_DEVICE_FAMILY':'1','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','PRODUCT_NAME':'$(TARGET_NAME)','LD_RUNPATH_SEARCH_PATHS':'$(inherited) @executable_path/Frameworks'}
appConfigs=configs('app',dict(base,INFOPLIST_FILE='Config/Info.plist',PRODUCT_BUNDLE_IDENTIFIER='dev.freeradio.app',GENERATE_INFOPLIST_FILE='NO'))
testConfigs=configs('tests',dict(base,PRODUCT_BUNDLE_IDENTIFIER='dev.freeradio.app.tests',GENERATE_INFOPLIST_FILE='YES',TEST_HOST='$(BUILT_PRODUCTS_DIR)/FreeRadio.app/FreeRadio',BUNDLE_LOADER='$(TEST_HOST)'))
proxy=add('proxy', f'isa = PBXContainerItemProxy; containerPortal = {uid("project")}; proxyType = 1; remoteGlobalIDString = {uid("app")}; remoteInfo = FreeRadio;')
dep=add('dep',f'isa = PBXTargetDependency; target = {uid("app")}; targetProxy = {proxy};')
for target, paths, config, product, name, ptype in [('app',appfiles,appConfigs,appProduct,'FreeRadio','application'),('tests',testfiles,testConfigs,testProduct,'FreeRadioTests','bundle.unit-test')]:
    sources=add(target+'sources',f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = {array([builds[str(p.relative_to(root))] for p in paths])}; runOnlyForDeploymentPostprocessing = 0;')
    frameworks=add(target+'frameworks','isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    resources=add(target+'resources','isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
    add(target,f'isa = PBXNativeTarget; buildConfigurationList = {config}; buildPhases = {array([sources,frameworks,resources])}; buildRules = (); dependencies = {array([dep] if target=="tests" else [])}; name = {name}; productName = {name}; productReference = {product}; productType = "com.apple.product-type.{ptype}";')
add('project',f'isa = PBXProject; attributes = {{ BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {{ {uid("tests")} = {{ TestTargetID = {uid("app")}; }}; }}; }}; buildConfigurationList = {projectConfigs}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = {array([uid("app"),uid("tests")])};')
project=root/'FreeRadio.xcodeproj'; project.mkdir(exist_ok=True)
(project/'project.pbxproj').write_text('// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+'\n}; rootObject = '+uid('project')+'; }\n')
schemes=project/'xcshareddata/xcschemes'; schemes.mkdir(parents=True,exist_ok=True)
def buildref(target,name):return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid(target)}" BuildableName="{name}" BlueprintName="{name.split(".")[0]}" ReferencedContainer="container:FreeRadio.xcodeproj"/>'
(schemes/'FreeRadio.xcscheme').write_text(f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="2700" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{buildref('app','FreeRadio.app')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{buildref('tests','FreeRadioTests.xctest')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref('app','FreeRadio.app')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{buildref('app','FreeRadio.app')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(f'Generated project: {len(appfiles)} app sources, {len(testfiles)} test sources')
