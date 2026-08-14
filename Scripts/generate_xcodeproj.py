#!/usr/bin/env python3
"""Generate LifeCue.xcodeproj/project.pbxproj from the current source tree.

App/test Swift files are discovered from disk. PBXGroup hierarchy mirrors the
on-disk folders under LifeCue/ (App, Domain/*, Services/*, Features/*, …).
"""

from pathlib import Path
from typing import Dict, List
import uuid

ROOT = Path("/Users/deepalikorde/Desktop/LifeCue")


def discover_swift_files(relative_root: str) -> List[str]:
    base = ROOT / relative_root
    return sorted(
        str(path.relative_to(ROOT)).replace("\\", "/")
        for path in base.rglob("*.swift")
    )


APP_FILES = discover_swift_files("LifeCue")
TEST_FILES = discover_swift_files("LifeCueTests")


def uid() -> str:
    return uuid.uuid4().hex[:24].upper()


def files_under(prefix: str, pool: List[str]) -> List[str]:
    """Swift files directly in prefix/ (not nested subfolders)."""
    prefix = prefix.rstrip("/") + "/"
    depth = prefix.count("/")
    matched = [
        path for path in pool
        if path.startswith(prefix) and path.count("/") == depth
    ]
    return sorted(matched)


def main() -> None:
    ids = {k: uid() for k in [
        "project", "root", "products", "app_group", "tests_group",
        "app_target", "test_target", "app_product", "test_product",
        "src_app", "src_tests", "res_app", "fw_app", "fw_tests",
        "app_cfgs", "test_cfgs", "proj_cfgs",
        "app_dbg", "app_rel", "test_dbg", "test_rel", "proj_dbg", "proj_rel",
        "assets_ref", "assets_build",
        "dep", "proxy",
        "copy_repo_snapshot",
        "g_app", "g_design", "g_domain", "g_models", "g_class", "g_engine",
        "g_calendar_domain", "g_backup_domain",
        "g_services", "g_persist", "g_notifications", "g_ocr", "g_extraction",
        "g_calendar_services", "g_forward", "g_backup_services", "g_settings_services",
        "g_features", "g_calendar_features", "g_home", "g_reminder",
        "g_people", "g_more", "g_backup_features", "g_help", "g_settings_features",
        "g_capture", "g_placeholders", "g_root", "g_resources",
        "g_ocr_domain", "g_extraction_domain",
    ]}

    file_ids = {f: uid() for f in APP_FILES + TEST_FILES}
    build_ids = {f: uid() for f in APP_FILES + TEST_FILES}

    lines: list[str] = []
    lines.append("// !$*UTF8*$!")
    lines.append("{")
    lines.append("\tarchiveVersion = 1;")
    lines.append("\tclasses = {")
    lines.append("\t};")
    lines.append("\tobjectVersion = 56;")
    lines.append("\tobjects = {")
    lines.append("")

    # PBXBuildFile
    lines.append("/* Begin PBXBuildFile section */")
    for f in APP_FILES:
        name = Path(f).name
        lines.append(
            f"\t\t{build_ids[f]} /* {name} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_ids[f]} /* {name} */; }};"
        )
    for f in TEST_FILES:
        name = Path(f).name
        lines.append(
            f"\t\t{build_ids[f]} /* {name} in Sources */ = "
            f"{{isa = PBXBuildFile; fileRef = {file_ids[f]} /* {name} */; }};"
        )
    lines.append(
        f"\t\t{ids['assets_build']} /* Assets.xcassets in Resources */ = "
        f"{{isa = PBXBuildFile; fileRef = {ids['assets_ref']} /* Assets.xcassets */; }};"
    )
    lines.append("/* End PBXBuildFile section */")
    lines.append("")

    # PBXContainerItemProxy
    lines.append("/* Begin PBXContainerItemProxy section */")
    lines.append(f"\t\t{ids['proxy']} /* PBXContainerItemProxy */ = {{")
    lines.append("\t\t\tisa = PBXContainerItemProxy;")
    lines.append(f"\t\t\tcontainerPortal = {ids['project']} /* Project object */;")
    lines.append("\t\t\tproxyType = 1;")
    lines.append(f"\t\t\tremoteGlobalIDString = {ids['app_target']};")
    lines.append('\t\t\tremoteInfo = LifeCue;')
    lines.append("\t\t};")
    lines.append("/* End PBXContainerItemProxy section */")
    lines.append("")

    # PBXFileReference
    lines.append("/* Begin PBXFileReference section */")
    for f in APP_FILES + TEST_FILES:
        name = Path(f).name
        lines.append(
            f"\t\t{file_ids[f]} /* {name} */ = "
            "{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
            f'path = "{f}"; sourceTree = SOURCE_ROOT; }};'
        )
    lines.append(
        f"\t\t{ids['app_product']} /* LifeCue.app */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.application; includeInIndex = 0; "
        "path = LifeCue.app; sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    lines.append(
        f"\t\t{ids['test_product']} /* LifeCueTests.xctest */ = {{isa = PBXFileReference; "
        "explicitFileType = wrapper.cfbundle; includeInIndex = 0; "
        "path = LifeCueTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };"
    )
    lines.append(
        f"\t\t{ids['assets_ref']} /* Assets.xcassets */ = {{isa = PBXFileReference; "
        'lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; '
        'sourceTree = "<group>"; };'
    )
    lines.append("/* End PBXFileReference section */")
    lines.append("")

    # Frameworks
    lines.append("/* Begin PBXFrameworksBuildPhase section */")
    for key in ("fw_app", "fw_tests"):
        lines.append(f"\t\t{ids[key]} /* Frameworks */ = {{")
        lines.append("\t\t\tisa = PBXFrameworksBuildPhase;")
        lines.append("\t\t\tbuildActionMask = 2147483647;")
        lines.append("\t\t\tfiles = (")
        lines.append("\t\t\t);")
        lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
        lines.append("\t\t};")
    lines.append("/* End PBXFrameworksBuildPhase section */")
    lines.append("")

    def emit_group(gid, name, path, children):
        lines.append(f"\t\t{gid} /* {name} */ = {{")
        lines.append("\t\t\tisa = PBXGroup;")
        lines.append("\t\t\tchildren = (")
        for child in children:
            lines.append(f"\t\t\t\t{child},")
        lines.append("\t\t\t);")
        if path is not None:
            lines.append(f"\t\t\tpath = {path};")
        else:
            lines.append(f"\t\t\tname = {name};")
        lines.append('\t\t\tsourceTree = "<group>";')
        lines.append("\t\t};")

    def file_child(path: str) -> str:
        return f"{file_ids[path]} /* {Path(path).name} */"

    def leaf_children(relative_dir: str) -> List[str]:
        files = files_under(relative_dir, APP_FILES)
        if not files:
            raise SystemExit(f"No Swift files found under {relative_dir}/")
        return [file_child(p) for p in files]

    # Leaf folders that must own every app Swift file exactly once.
    leaf_dirs = [
        "LifeCue/App",
        "LifeCue/DesignSystem",
        "LifeCue/Domain/Models",
        "LifeCue/Domain/Classification",
        "LifeCue/Domain/Calendar",
        "LifeCue/Domain/ReminderEngine",
        "LifeCue/Domain/OCR",
        "LifeCue/Domain/Extraction",
        "LifeCue/Domain/Backup",
        "LifeCue/Services/Persistence",
        "LifeCue/Services/Notifications",
        "LifeCue/Services/Calendar",
        "LifeCue/Services/OCR",
        "LifeCue/Services/Extraction",
        "LifeCue/Services/Forward",
        "LifeCue/Services/Backup",
        "LifeCue/Services/Settings",
        "LifeCue/Features/Home",
        "LifeCue/Features/Reminder",
        "LifeCue/Features/Calendar",
        "LifeCue/Features/People",
        "LifeCue/Features/More",
        "LifeCue/Features/Capture",
        "LifeCue/Features/Placeholders",
        "LifeCue/Features/Root",
        "LifeCue/Features/Backup",
        "LifeCue/Features/Help",
        "LifeCue/Features/Settings",
    ]

    grouped: Dict[str, List[str]] = {
        directory: files_under(directory, APP_FILES) for directory in leaf_dirs
    }
    placed = [path for paths in grouped.values() for path in paths]
    missing = sorted(set(APP_FILES) - set(placed))
    duplicate_check = sorted({p for p in placed if placed.count(p) > 1})
    if missing:
        raise SystemExit(
            "App Swift files not mapped to any PBXGroup leaf folder:\n  "
            + "\n  ".join(missing)
        )
    if duplicate_check:
        raise SystemExit(
            "App Swift files mapped to multiple PBXGroup leaf folders:\n  "
            + "\n  ".join(duplicate_check)
        )

    lines.append("/* Begin PBXGroup section */")
    emit_group(ids["g_app"], "App", "App", leaf_children("LifeCue/App"))
    emit_group(ids["g_design"], "DesignSystem", "DesignSystem", leaf_children("LifeCue/DesignSystem"))
    emit_group(ids["g_models"], "Models", "Models", leaf_children("LifeCue/Domain/Models"))
    emit_group(ids["g_class"], "Classification", "Classification", leaf_children("LifeCue/Domain/Classification"))
    emit_group(ids["g_calendar_domain"], "Calendar", "Calendar", leaf_children("LifeCue/Domain/Calendar"))
    emit_group(ids["g_engine"], "ReminderEngine", "ReminderEngine", leaf_children("LifeCue/Domain/ReminderEngine"))
    emit_group(ids["g_ocr_domain"], "OCR", "OCR", leaf_children("LifeCue/Domain/OCR"))
    emit_group(ids["g_extraction_domain"], "Extraction", "Extraction", leaf_children("LifeCue/Domain/Extraction"))
    emit_group(ids["g_backup_domain"], "Backup", "Backup", leaf_children("LifeCue/Domain/Backup"))
    emit_group(ids["g_domain"], "Domain", "Domain", [
        f"{ids['g_models']} /* Models */",
        f"{ids['g_class']} /* Classification */",
        f"{ids['g_calendar_domain']} /* Calendar */",
        f"{ids['g_engine']} /* ReminderEngine */",
        f"{ids['g_ocr_domain']} /* OCR */",
        f"{ids['g_extraction_domain']} /* Extraction */",
        f"{ids['g_backup_domain']} /* Backup */",
    ])
    emit_group(ids["g_persist"], "Persistence", "Persistence", leaf_children("LifeCue/Services/Persistence"))
    emit_group(ids["g_notifications"], "Notifications", "Notifications", leaf_children("LifeCue/Services/Notifications"))
    emit_group(ids["g_calendar_services"], "Calendar", "Calendar", leaf_children("LifeCue/Services/Calendar"))
    emit_group(ids["g_ocr"], "OCR", "OCR", leaf_children("LifeCue/Services/OCR"))
    emit_group(ids["g_extraction"], "Extraction", "Extraction", leaf_children("LifeCue/Services/Extraction"))
    emit_group(ids["g_forward"], "Forward", "Forward", leaf_children("LifeCue/Services/Forward"))
    emit_group(ids["g_backup_services"], "Backup", "Backup", leaf_children("LifeCue/Services/Backup"))
    emit_group(ids["g_settings_services"], "Settings", "Settings", leaf_children("LifeCue/Services/Settings"))
    emit_group(ids["g_services"], "Services", "Services", [
        f"{ids['g_persist']} /* Persistence */",
        f"{ids['g_notifications']} /* Notifications */",
        f"{ids['g_calendar_services']} /* Calendar */",
        f"{ids['g_ocr']} /* OCR */",
        f"{ids['g_extraction']} /* Extraction */",
        f"{ids['g_forward']} /* Forward */",
        f"{ids['g_backup_services']} /* Backup */",
        f"{ids['g_settings_services']} /* Settings */",
    ])
    emit_group(ids["g_home"], "Home", "Home", leaf_children("LifeCue/Features/Home"))
    emit_group(ids["g_reminder"], "Reminder", "Reminder", leaf_children("LifeCue/Features/Reminder"))
    emit_group(ids["g_calendar_features"], "Calendar", "Calendar", leaf_children("LifeCue/Features/Calendar"))
    emit_group(ids["g_people"], "People", "People", leaf_children("LifeCue/Features/People"))
    emit_group(ids["g_more"], "More", "More", leaf_children("LifeCue/Features/More"))
    emit_group(ids["g_capture"], "Capture", "Capture", leaf_children("LifeCue/Features/Capture"))
    emit_group(ids["g_placeholders"], "Placeholders", "Placeholders", leaf_children("LifeCue/Features/Placeholders"))
    emit_group(ids["g_root"], "Root", "Root", leaf_children("LifeCue/Features/Root"))
    emit_group(ids["g_backup_features"], "Backup", "Backup", leaf_children("LifeCue/Features/Backup"))
    emit_group(ids["g_help"], "Help", "Help", leaf_children("LifeCue/Features/Help"))
    emit_group(ids["g_settings_features"], "Settings", "Settings", leaf_children("LifeCue/Features/Settings"))
    emit_group(ids["g_features"], "Features", "Features", [
        f"{ids['g_home']} /* Home */",
        f"{ids['g_calendar_features']} /* Calendar */",
        f"{ids['g_reminder']} /* Reminder */",
        f"{ids['g_people']} /* People */",
        f"{ids['g_more']} /* More */",
        f"{ids['g_capture']} /* Capture */",
        f"{ids['g_placeholders']} /* Placeholders */",
        f"{ids['g_root']} /* Root */",
        f"{ids['g_backup_features']} /* Backup */",
        f"{ids['g_help']} /* Help */",
        f"{ids['g_settings_features']} /* Settings */",
    ])
    emit_group(ids["g_resources"], "Resources", "Resources", [
        f"{ids['assets_ref']} /* Assets.xcassets */",
    ])
    emit_group(ids["app_group"], "LifeCue", "LifeCue", [
        f"{ids['g_app']} /* App */",
        f"{ids['g_design']} /* DesignSystem */",
        f"{ids['g_domain']} /* Domain */",
        f"{ids['g_services']} /* Services */",
        f"{ids['g_features']} /* Features */",
        f"{ids['g_resources']} /* Resources */",
    ])
    emit_group(ids["tests_group"], "LifeCueTests", "LifeCueTests", [
        file_child(p) for p in TEST_FILES
    ])
    emit_group(ids["products"], "Products", None, [
        f"{ids['app_product']} /* LifeCue.app */",
        f"{ids['test_product']} /* LifeCueTests.xctest */",
    ])
    # root group without name override using path
    lines.append(f"\t\t{ids['root']} = {{")
    lines.append("\t\t\tisa = PBXGroup;")
    lines.append("\t\t\tchildren = (")
    lines.append(f"\t\t\t\t{ids['app_group']} /* LifeCue */,")
    lines.append(f"\t\t\t\t{ids['tests_group']} /* LifeCueTests */,")
    lines.append(f"\t\t\t\t{ids['products']} /* Products */,")
    lines.append("\t\t\t);")
    lines.append('\t\t\tsourceTree = "<group>";')
    lines.append("\t\t};")
    lines.append("/* End PBXGroup section */")
    lines.append("")

    # Native targets
    lines.append("/* Begin PBXNativeTarget section */")
    lines.append(f"\t\t{ids['app_target']} /* LifeCue */ = {{")
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append(
        f"\t\t\tbuildConfigurationList = {ids['app_cfgs']} "
        '/* Build configuration list for PBXNativeTarget "LifeCue" */;'
    )
    lines.append("\t\t\tbuildPhases = (")
    lines.append(f"\t\t\t\t{ids['src_app']} /* Sources */,")
    lines.append(f"\t\t\t\t{ids['fw_app']} /* Frameworks */,")
    lines.append(f"\t\t\t\t{ids['res_app']} /* Resources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdependencies = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = LifeCue;")
    lines.append("\t\t\tproductName = LifeCue;")
    lines.append(f"\t\t\tproductReference = {ids['app_product']} /* LifeCue.app */;")
    lines.append('\t\t\tproductType = "com.apple.product-type.application";')
    lines.append("\t\t};")

    lines.append(f"\t\t{ids['test_target']} /* LifeCueTests */ = {{")
    lines.append("\t\t\tisa = PBXNativeTarget;")
    lines.append(
        f"\t\t\tbuildConfigurationList = {ids['test_cfgs']} "
        '/* Build configuration list for PBXNativeTarget "LifeCueTests" */;'
    )
    lines.append("\t\t\tbuildPhases = (")
    lines.append(f"\t\t\t\t{ids['src_tests']} /* Sources */,")
    lines.append(f"\t\t\t\t{ids['fw_tests']} /* Frameworks */,")
    lines.append(f"\t\t\t\t{ids['copy_repo_snapshot']} /* Copy LifeCue Repo Snapshot */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tbuildRules = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tdependencies = (")
    lines.append(f"\t\t\t\t{ids['dep']} /* PBXTargetDependency */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\tname = LifeCueTests;")
    lines.append("\t\t\tproductName = LifeCueTests;")
    lines.append(f"\t\t\tproductReference = {ids['test_product']} /* LifeCueTests.xctest */;")
    lines.append('\t\t\tproductType = "com.apple.product-type.bundle.unit-test";')
    lines.append("\t\t};")
    lines.append("/* End PBXNativeTarget section */")
    lines.append("")

    # Project
    lines.append("/* Begin PBXProject section */")
    lines.append(f"\t\t{ids['project']} /* Project object */ = {{")
    lines.append("\t\t\tisa = PBXProject;")
    lines.append("\t\t\tattributes = {")
    lines.append("\t\t\t\tBuildIndependentTargetsInParallel = 1;")
    lines.append("\t\t\t\tLastSwiftUpdateCheck = 2600;")
    lines.append("\t\t\t\tLastUpgradeCheck = 2600;")
    lines.append("\t\t\t\tTargetAttributes = {")
    lines.append(f"\t\t\t\t\t{ids['app_target']} = {{")
    lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;")
    lines.append("\t\t\t\t\t};")
    lines.append(f"\t\t\t\t\t{ids['test_target']} = {{")
    lines.append("\t\t\t\t\t\tCreatedOnToolsVersion = 26.0;")
    lines.append(f"\t\t\t\t\t\tTestTargetID = {ids['app_target']};")
    lines.append("\t\t\t\t\t};")
    lines.append("\t\t\t\t};")
    lines.append("\t\t\t};")
    lines.append(
        f"\t\t\tbuildConfigurationList = {ids['proj_cfgs']} "
        '/* Build configuration list for PBXProject "LifeCue" */;'
    )
    lines.append('\t\t\tcompatibilityVersion = "Xcode 15.0";')
    lines.append("\t\t\tdevelopmentRegion = en;")
    lines.append("\t\t\thasScannedForEncodings = 0;")
    lines.append("\t\t\tknownRegions = (")
    lines.append("\t\t\t\ten,")
    lines.append("\t\t\t\tBase,")
    lines.append("\t\t\t);")
    lines.append(f"\t\t\tmainGroup = {ids['root']};")
    lines.append(f"\t\t\tproductRefGroup = {ids['products']} /* Products */;")
    lines.append('\t\t\tprojectDirPath = "";')
    lines.append('\t\t\tprojectRoot = "";')
    lines.append("\t\t\ttargets = (")
    lines.append(f"\t\t\t\t{ids['app_target']} /* LifeCue */,")
    lines.append(f"\t\t\t\t{ids['test_target']} /* LifeCueTests */,")
    lines.append("\t\t\t);")
    lines.append("\t\t};")
    lines.append("/* End PBXProject section */")
    lines.append("")

    # Resources
    lines.append("/* Begin PBXResourcesBuildPhase section */")
    lines.append(f"\t\t{ids['res_app']} /* Resources */ = {{")
    lines.append("\t\t\tisa = PBXResourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append(f"\t\t\t\t{ids['assets_build']} /* Assets.xcassets in Resources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXResourcesBuildPhase section */")
    lines.append("")

    # Copy repo snapshot into the test bundle so source-scan tests work on device.
    lines.append("/* Begin PBXShellScriptBuildPhase section */")
    lines.append(f"\t\t{ids['copy_repo_snapshot']} /* Copy LifeCue Repo Snapshot */ = {{")
    lines.append("\t\t\tisa = PBXShellScriptBuildPhase;")
    lines.append("\t\t\talwaysOutOfDate = 1;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tinputFileListPaths = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\tinputPaths = (")
    lines.append("\t\t\t);")
    lines.append('\t\t\tname = "Copy LifeCue Repo Snapshot";')
    lines.append("\t\t\toutputFileListPaths = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\toutputPaths = (")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t\tshellPath = /bin/sh;")
    lines.append(
        '\t\t\tshellScript = "\\"${SRCROOT}/Scripts/copy_lifecue_repo_snapshot_for_tests.sh\\"\\n";'
    )
    lines.append("\t\t};")
    lines.append("/* End PBXShellScriptBuildPhase section */")
    lines.append("")

    # Sources
    lines.append("/* Begin PBXSourcesBuildPhase section */")
    lines.append(f"\t\t{ids['src_app']} /* Sources */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for f in APP_FILES:
        lines.append(f"\t\t\t\t{build_ids[f]} /* {Path(f).name} in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append(f"\t\t{ids['src_tests']} /* Sources */ = {{")
    lines.append("\t\t\tisa = PBXSourcesBuildPhase;")
    lines.append("\t\t\tbuildActionMask = 2147483647;")
    lines.append("\t\t\tfiles = (")
    for f in TEST_FILES:
        lines.append(f"\t\t\t\t{build_ids[f]} /* {Path(f).name} in Sources */,")
    lines.append("\t\t\t);")
    lines.append("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
    lines.append("\t\t};")
    lines.append("/* End PBXSourcesBuildPhase section */")
    lines.append("")

    # Target dependency
    lines.append("/* Begin PBXTargetDependency section */")
    lines.append(f"\t\t{ids['dep']} /* PBXTargetDependency */ = {{")
    lines.append("\t\t\tisa = PBXTargetDependency;")
    lines.append(f"\t\t\ttarget = {ids['app_target']} /* LifeCue */;")
    lines.append(f"\t\t\ttargetProxy = {ids['proxy']} /* PBXContainerItemProxy */;")
    lines.append("\t\t};")
    lines.append("/* End PBXTargetDependency section */")
    lines.append("")

    # Build configurations — preserve existing signing/bundle/deployment settings.
    lines.append("/* Begin XCBuildConfiguration section */")
    lines.append(f"\t\t{ids['proj_dbg']} /* Debug */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    lines.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    lines.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    lines.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
    lines.append("\t\t\t\tENABLE_TESTABILITY = YES;")
    lines.append("\t\t\t\tGCC_DYNAMIC_NO_PIC = NO;")
    lines.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    lines.append("\t\t\t\tONLY_ACTIVE_ARCH = YES;")
    lines.append("\t\t\t\tSDKROOT = iphoneos;")
    lines.append('\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";')
    lines.append('\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = "-Onone";')
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = Debug;")
    lines.append("\t\t};")

    lines.append(f"\t\t{ids['proj_rel']} /* Release */ = {{")
    lines.append("\t\t\tisa = XCBuildConfiguration;")
    lines.append("\t\t\tbuildSettings = {")
    lines.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    lines.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    lines.append("\t\t\t\tCLANG_ENABLE_OBJC_ARC = YES;")
    lines.append('\t\t\t\tDEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";')
    lines.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    lines.append("\t\t\t\tSDKROOT = iphoneos;")
    lines.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    lines.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    lines.append("\t\t\t\tVALIDATE_PRODUCT = YES;")
    lines.append("\t\t\t};")
    lines.append("\t\t\tname = Release;")
    lines.append("\t\t};")

    for cfg_id, name in ((ids["app_dbg"], "Debug"), (ids["app_rel"], "Release")):
        lines.append(f"\t\t{cfg_id} /* {name} */ = {{")
        lines.append("\t\t\tisa = XCBuildConfiguration;")
        lines.append("\t\t\tbuildSettings = {")
        lines.append("\t\t\t\tASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;")
        lines.append("\t\t\t\tASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;")
        lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        lines.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
        lines.append("\t\t\t\tDEVELOPMENT_TEAM = 8N3N7WP2A9;")
        lines.append("\t\t\t\tENABLE_PREVIEWS = YES;")
        lines.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
        # Merge LifeCue/Info.plist (document types / UTExportedTypeDeclarations for .lifecuebackup)
        # with generated INFOPLIST_KEY_* values. Without this, backup UTI declarations are omitted.
        lines.append('\t\t\t\tINFOPLIST_FILE = LifeCue/Info.plist;')
        lines.append("\t\t\t\tINFOPLIST_KEY_CFBundleDisplayName = LifeCue;")
        lines.append('\t\t\t\tINFOPLIST_KEY_NSCameraUsageDescription = "LifeCue uses the camera so you can capture a photo of a note or document to read on your device.";')
        lines.append('\t\t\t\tINFOPLIST_KEY_NSCalendarsFullAccessUsageDescription = "LifeCue can optionally show your upcoming calendar events while you create reminders. Your calendar stays on this device.";')
        lines.append("\t\t\t\tINFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;")
        lines.append("\t\t\t\tINFOPLIST_KEY_UILaunchScreen_Generation = YES;")
        lines.append("\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;")
        lines.append(
            '\t\t\t\tINFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = '
            '"UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown '
            'UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight";'
        )
        lines.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (")
        lines.append('\t\t\t\t\t"$(inherited)",')
        lines.append('\t\t\t\t\t"@executable_path/Frameworks",')
        lines.append("\t\t\t\t);")
        lines.append("\t\t\t\tMARKETING_VERSION = 1.0;")
        lines.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.lifecue.app;")
        lines.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
        lines.append('\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
        lines.append("\t\t\t\tSUPPORTS_MACCATALYST = NO;")
        lines.append("\t\t\t\tSWIFT_EMIT_LOC_STRINGS = YES;")
        lines.append('\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";')
        lines.append("\t\t\t};")
        lines.append(f"\t\t\tname = {name};")
        lines.append("\t\t};")

    for cfg_id, name in ((ids["test_dbg"], "Debug"), (ids["test_rel"], "Release")):
        lines.append(f"\t\t{cfg_id} /* {name} */ = {{")
        lines.append("\t\t\tisa = XCBuildConfiguration;")
        lines.append("\t\t\tbuildSettings = {")
        lines.append('\t\t\t\tBUNDLE_LOADER = "$(TEST_HOST)";')
        lines.append("\t\t\t\tCODE_SIGN_STYLE = Automatic;")
        lines.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
        lines.append("\t\t\t\tGENERATE_INFOPLIST_FILE = YES;")
        lines.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
        lines.append("\t\t\t\tMARKETING_VERSION = 1.0;")
        lines.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.lifecue.app.tests;")
        lines.append('\t\t\t\tPRODUCT_NAME = "$(TARGET_NAME)";')
        lines.append('\t\t\t\tSUPPORTED_PLATFORMS = "iphoneos iphonesimulator";')
        lines.append('\t\t\t\tTARGETED_DEVICE_FAMILY = "1,2";')
        lines.append(
            '\t\t\t\tTEST_HOST = '
            '"$(BUILT_PRODUCTS_DIR)/LifeCue.app/$(BUNDLE_EXECUTABLE_FOLDER_PATH)/LifeCue";'
        )
        lines.append("\t\t\t};")
        lines.append(f"\t\t\tname = {name};")
        lines.append("\t\t};")
    lines.append("/* End XCBuildConfiguration section */")
    lines.append("")

    lines.append("/* Begin XCConfigurationList section */")
    for list_id, dbg, rel, label in [
        (ids["proj_cfgs"], ids["proj_dbg"], ids["proj_rel"], 'PBXProject "LifeCue"'),
        (ids["app_cfgs"], ids["app_dbg"], ids["app_rel"], 'PBXNativeTarget "LifeCue"'),
        (ids["test_cfgs"], ids["test_dbg"], ids["test_rel"], 'PBXNativeTarget "LifeCueTests"'),
    ]:
        lines.append(f"\t\t{list_id} /* Build configuration list for {label} */ = {{")
        lines.append("\t\t\tisa = XCConfigurationList;")
        lines.append("\t\t\tbuildConfigurations = (")
        lines.append(f"\t\t\t\t{dbg} /* Debug */,")
        lines.append(f"\t\t\t\t{rel} /* Release */,")
        lines.append("\t\t\t);")
        lines.append("\t\t\tdefaultConfigurationIsVisible = 0;")
        lines.append("\t\t\tdefaultConfigurationName = Release;")
        lines.append("\t\t};")
    lines.append("/* End XCConfigurationList section */")
    lines.append("\t};")
    lines.append(f"\trootObject = {ids['project']} /* Project object */;")
    lines.append("}")

    out = ROOT / "LifeCue.xcodeproj" / "project.pbxproj"
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"Wrote {out}")
    print(f"App sources: {len(APP_FILES)}")
    print(f"Test sources: {len(TEST_FILES)}")


if __name__ == "__main__":
    main()
