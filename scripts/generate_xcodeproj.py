#!/usr/bin/env python3
"""產生 LidarRadar.xcodeproj 與 App 圖示。

Mac 上平常直接打開產生好的專案即可。這個腳本是給沒有 Xcode 的環境，
用同一份檔案清單把專案檔寫出來。改過程式檔之後若要重跑：

    python3 scripts/generate_xcodeproj.py
"""

from __future__ import annotations

import hashlib
import math
import struct
import zlib
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
PROJECT = ROOT / "LidarRadar.xcodeproj"

APP_SOURCES = [
    "LidarRadar/LidarRadarApp.swift",
    "LidarRadar/AR/DistanceStabilizer.swift",
    "LidarRadar/AR/LiDARSessionController.swift",
    "LidarRadar/AR/MetalDepthReducer.swift",
    "LidarRadar/AR/MultitaskingCamera.swift",
    "LidarRadar/AR/LiDARMultitaskingCapture.swift",
    "LidarRadar/Alerts/AlertEngine.swift",
    "LidarRadar/LiveActivity/LiveActivityManager.swift",
    "LidarRadar/PiP/DistanceCardRenderer.swift",
    "LidarRadar/PiP/DistancePictureInPicture.swift",
    "LidarRadar/Services/AppModel.swift",
    "LidarRadar/Services/BackgroundKeeper.swift",
    "LidarRadar/Services/SettingsStore.swift",
    "LidarRadar/Views/ConsentView.swift",
    "LidarRadar/Views/PermissionView.swift",
    "LidarRadar/Views/RadarView.swift",
    "LidarRadar/Views/SettingsView.swift",
    "LidarRadar/Views/Theme.swift",
    "LidarRadar/Views/UnsupportedDeviceView.swift",
    "LidarRadar/Shaders/DepthReduction.metal",
    "Shared/DangerLevel.swift",
    "Shared/RadarAttributes.swift",
    "Shared/L10n.swift",
]

APP_RESOURCES = [
    "LidarRadar/Assets.xcassets",
    "LidarRadar/PrivacyInfo.xcprivacy",
    "Shared/Localizable.xcstrings",
]

WIDGET_SOURCES = [
    "LidarRadarWidget/RadarLiveActivityWidget.swift",
    "Shared/DangerLevel.swift",
    "Shared/RadarAttributes.swift",
    "Shared/L10n.swift",
]

WIDGET_RESOURCES = [
    "LidarRadarWidget/PrivacyInfo.xcprivacy",
    "Shared/Localizable.xcstrings",
]

NAV_ONLY = [
    "LidarRadar/Info.plist",
    "LidarRadar/LidarRadar.entitlements",
    "LidarRadarWidget/Info.plist",
    "LidarRadarWidget/LidarRadarWidget.entitlements",
    "README.md",
    "README.en.md",
    "project.yml",
    "scripts/generate_xcodeproj.py",
]

APP_INFO_STRINGS = [
    ("en", "LidarRadar/en.lproj/InfoPlist.strings"),
    ("zh-Hant", "LidarRadar/zh-Hant.lproj/InfoPlist.strings"),
]

WIDGET_INFO_STRINGS = [
    ("en", "LidarRadarWidget/en.lproj/InfoPlist.strings"),
    ("zh-Hant", "LidarRadarWidget/zh-Hant.lproj/InfoPlist.strings"),
]

APP_FRAMEWORKS = [
    "ARKit",
    "Metal",
    "ActivityKit",
    "CoreHaptics",
    "AVFoundation",
    "AVKit",
    "CoreMedia",
    "AudioToolbox",
    "CoreLocation",
    "CoreVideo",
    "Combine",
    "UIKit",
    "SwiftUI",
]

WIDGET_FRAMEWORKS = [
    "WidgetKit",
    "SwiftUI",
    "ActivityKit",
]


def uid(name: str) -> str:
    return hashlib.md5(name.encode("utf-8")).hexdigest()[:24].upper()


def quote(value: str) -> str:
    if value and all(ch.isalnum() or ch in "._/" for ch in value):
        return value
    escaped = value.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{escaped}"'


def file_type(path: str) -> str:
    name = Path(path).name
    if name.endswith(".swift"):
        return "sourcecode.swift"
    if name.endswith(".metal"):
        return "sourcecode.metal"
    if name.endswith(".plist"):
        return "text.plist.xml"
    if name.endswith(".entitlements"):
        return "text.plist.entitlements"
    if name.endswith(".xcprivacy"):
        return "text.plist.xml"
    if name.endswith(".xcassets"):
        return "folder.assetcatalog"
    if name.endswith(".xcstrings"):
        return "text.json.xcstrings"
    if name.endswith(".strings"):
        return "text.plist.strings"
    if name.endswith(".md"):
        return "net.daringfireball.markdown"
    if name.endswith(".yml") or name.endswith(".yaml"):
        return "text.yaml"
    if name.endswith(".py"):
        return "text.script.python"
    return "text"


class Project:
    def __init__(self) -> None:
        self.blocks: list[tuple[str, str]] = []
        self.seen: set[str] = set()

    def add(self, object_id: str, comment: str, body: str) -> str:
        if object_id in self.seen:
            raise SystemExit(f"duplicate id {object_id} for {comment}")
        self.seen.add(object_id)
        self.blocks.append((object_id, f"\t\t{object_id} /* {comment} */ = {{\n{body}\t\t}};"))
        return object_id

    def render(self) -> str:
        objects = "\n".join(block for _, block in self.blocks)
        root = uid("PBXProject")
        return (
            "// !$*UTF8*$!\n"
            "{\n"
            "\tarchiveVersion = 1;\n"
            "\tclasses = {\n"
            "\t};\n"
            "\tobjectVersion = 56;\n"
            "\tobjects = {\n"
            f"{objects}\n"
            "\t};\n"
            f"\trootObject = {root} /* Project object */;\n"
            "}\n"
        )


def build_file(project: Project, key: str, file_ref: str, comment: str, settings: str | None = None) -> str:
    object_id = uid(f"buildfile {key}")
    extra = f"\t\t\tsettings = {settings};\n" if settings else ""
    project.add(
        object_id,
        comment,
        "\t\t\tisa = PBXBuildFile;\n"
        f"\t\t\tfileRef = {file_ref} /* {comment.split(' in ')[0]} */;\n"
        f"{extra}",
    )
    return object_id


def file_ref(project: Project, path: str) -> str:
    object_id = uid(f"fileref {path}")
    name = Path(path).name
    project.add(
        object_id,
        name,
        "\t\t\tisa = PBXFileReference;\n"
        f"\t\t\tlastKnownFileType = {file_type(path)};\n"
        f"\t\t\tname = {quote(name)};\n"
        f"\t\t\tpath = {quote(path)};\n"
        "\t\t\tsourceTree = SOURCE_ROOT;\n",
    )
    return object_id


def framework_ref(project: Project, name: str) -> str:
    object_id = uid(f"framework {name}")
    project.add(
        object_id,
        f"{name}.framework",
        "\t\t\tisa = PBXFileReference;\n"
        "\t\t\tlastKnownFileType = wrapper.framework;\n"
        f"\t\t\tname = {name}.framework;\n"
        f"\t\t\tpath = System/Library/Frameworks/{name}.framework;\n"
        "\t\t\tsourceTree = SDKROOT;\n",
    )
    return object_id


def product_ref(project: Project, name: str, explicit_type: str, path: str) -> str:
    object_id = uid(f"product {name}")
    project.add(
        object_id,
        path,
        "\t\t\tisa = PBXFileReference;\n"
        f"\t\t\texplicitFileType = {explicit_type};\n"
        "\t\t\tincludeInIndex = 0;\n"
        f"\t\t\tpath = {path};\n"
        "\t\t\tsourceTree = BUILT_PRODUCTS_DIR;\n",
    )
    return object_id


def group(project: Project, key: str, name: str, children: list[tuple[str, str]]) -> str:
    object_id = uid(f"group {key}")
    lines = "\n".join(f"\t\t\t\t{child_id} /* {comment} */," for child_id, comment in children)
    project.add(
        object_id,
        name,
        "\t\t\tisa = PBXGroup;\n"
        "\t\t\tchildren = (\n"
        f"{lines}\n"
        "\t\t\t);\n"
        f"\t\t\tname = {quote(name)};\n"
        "\t\t\tsourceTree = \"<group>\";\n",
    )
    return object_id


def phase(project: Project, isa: str, name: str, files: list[tuple[str, str]], extra: str = "") -> str:
    object_id = uid(f"phase {name}")
    lines = "\n".join(f"\t\t\t\t{file_id} /* {comment} */," for file_id, comment in files)
    project.add(
        object_id,
        name,
        f"\t\t\tisa = {isa};\n"
        "\t\t\tbuildActionMask = 2147483647;\n"
        "\t\t\tfiles = (\n"
        f"{lines}\n"
        "\t\t\t);\n"
        f"\t\t\tname = {quote(name)};\n"
        "\t\t\trunOnlyForDeploymentPostprocessing = 0;\n"
        f"{extra}",
    )
    return object_id


def config(project: Project, name: str, target: str, settings: list[tuple[str, str | list[str]]]) -> str:
    object_id = uid(f"config {target} {name}")
    lines = []
    for key, value in settings:
        if isinstance(value, list):
            inner = "\n".join(f"\t\t\t\t\t{quote(item)}," for item in value)
            lines.append(f"\t\t\t\t{key} = (\n{inner}\n\t\t\t\t);")
        else:
            lines.append(f"\t\t\t\t{key} = {value};")
    body = "\n".join(lines)
    project.add(
        object_id,
        name,
        "\t\t\tisa = XCBuildConfiguration;\n"
        "\t\t\tbuildSettings = {\n"
        f"{body}\n"
        "\t\t\t};\n"
        f"\t\t\tname = {name};\n",
    )
    return object_id


def config_list(project: Project, owner: str, debug: str, release: str) -> str:
    object_id = uid(f"configlist {owner}")
    project.add(
        object_id,
        f"Build configuration list for {owner}",
        "\t\t\tisa = XCConfigurationList;\n"
        "\t\t\tbuildConfigurations = (\n"
        f"\t\t\t\t{debug} /* Debug */,\n"
        f"\t\t\t\t{release} /* Release */,\n"
        "\t\t\t);\n"
        "\t\t\tdefaultConfigurationIsVisible = 0;\n"
        "\t\t\tdefaultConfigurationName = Release;\n",
    )
    return object_id


def project_settings(name: str) -> list[tuple[str, str | list[str]]]:
    common: list[tuple[str, str | list[str]]] = [
        ("ALWAYS_SEARCH_USER_PATHS", "NO"),
        ("CLANG_ANALYZER_NONNULL", "YES"),
        ("CLANG_ANALYZER_NUMBER_OBJECT_CONVERSION", "YES_AGGRESSIVE"),
        ("CLANG_CXX_LANGUAGE_STANDARD", '"gnu++20"'),
        ("CLANG_ENABLE_MODULES", "YES"),
        ("CLANG_ENABLE_OBJC_ARC", "YES"),
        ("CLANG_ENABLE_OBJC_WEAK", "YES"),
        ("CLANG_WARN_BLOCK_CAPTURE_AUTORELEASING", "YES"),
        ("CLANG_WARN_BOOL_CONVERSION", "YES"),
        ("CLANG_WARN_COMMA", "YES"),
        ("CLANG_WARN_CONSTANT_CONVERSION", "YES"),
        ("CLANG_WARN_DEPRECATED_OBJC_IMPLEMENTATIONS", "YES"),
        ("CLANG_WARN_DIRECT_OBJC_ISA_USAGE", "YES_ERROR"),
        ("CLANG_WARN_EMPTY_BODY", "YES"),
        ("CLANG_WARN_ENUM_CONVERSION", "YES"),
        ("CLANG_WARN_INFINITE_RECURSION", "YES"),
        ("CLANG_WARN_INT_CONVERSION", "YES"),
        ("CLANG_WARN_NON_LITERAL_NULL_CONVERSION", "YES"),
        ("CLANG_WARN_OBJC_IMPLICIT_RETAIN_SELF", "YES"),
        ("CLANG_WARN_OBJC_LITERAL_CONVERSION", "YES"),
        ("CLANG_WARN_OBJC_ROOT_CLASS", "YES_ERROR"),
        ("CLANG_WARN_QUOTED_INCLUDE_IN_FRAMEWORK_HEADER", "YES"),
        ("CLANG_WARN_RANGE_LOOP_ANALYSIS", "YES"),
        ("CLANG_WARN_STRICT_PROTOTYPES", "YES"),
        ("CLANG_WARN_SUSPICIOUS_MOVE", "YES"),
        ("CLANG_WARN_UNGUARDED_AVAILABILITY", "YES_AGGRESSIVE"),
        ("CLANG_WARN_UNREACHABLE_CODE", "YES"),
        ("CLANG_WARN__DUPLICATE_METHOD_MATCH", "YES"),
        ("COPY_PHASE_STRIP", "NO"),
        ("ENABLE_STRICT_OBJC_MSGSEND", "YES"),
        ("ENABLE_USER_SCRIPT_SANDBOXING", "YES"),
        ("GCC_C_LANGUAGE_STANDARD", "gnu17"),
        ("GCC_NO_COMMON_BLOCKS", "YES"),
        ("GCC_WARN_64_TO_32_BIT_CONVERSION", "YES"),
        ("GCC_WARN_ABOUT_RETURN_TYPE", "YES_ERROR"),
        ("GCC_WARN_UNDECLARED_SELECTOR", "YES"),
        ("GCC_WARN_UNINITIALIZED_AUTOS", "YES_AGGRESSIVE"),
        ("GCC_WARN_UNUSED_FUNCTION", "YES"),
        ("GCC_WARN_UNUSED_VARIABLE", "YES"),
        ("DEVELOPMENT_LANGUAGE", "en"),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.1"),
        ("LOCALIZATION_PREFERS_STRING_CATALOGS", "YES"),
        ("SDKROOT", "iphoneos"),
        ("SUPPORTED_PLATFORMS", '"iphoneos iphonesimulator"'),
        ("SUPPORTS_MACCATALYST", "NO"),
        ("SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD", "NO"),
        ("SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD", "NO"),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", "1"),
    ]
    if name == "Debug":
        common.extend(
            [
                ("DEBUG_INFORMATION_FORMAT", "dwarf"),
                ("ENABLE_TESTABILITY", "YES"),
                ("GCC_DYNAMIC_NO_PIC", "NO"),
                ("GCC_OPTIMIZATION_LEVEL", "0"),
                ("GCC_PREPROCESSOR_DEFINITIONS", ["DEBUG=1", "$(inherited)"]),
                ("MTL_ENABLE_DEBUG_INFO", "INCLUDE_SOURCE"),
                ("ONLY_ACTIVE_ARCH", "YES"),
                ("SWIFT_ACTIVE_COMPILATION_CONDITIONS", '"DEBUG $(inherited)"'),
                ("SWIFT_OPTIMIZATION_LEVEL", '"-Onone"'),
            ]
        )
    else:
        common.extend(
            [
                ("DEBUG_INFORMATION_FORMAT", '"dwarf-with-dsym"'),
                ("ENABLE_NS_ASSERTIONS", "NO"),
                ("GCC_OPTIMIZATION_LEVEL", "s"),
                ("MTL_ENABLE_DEBUG_INFO", "NO"),
                ("SWIFT_COMPILATION_MODE", "wholemodule"),
                ("SWIFT_OPTIMIZATION_LEVEL", '"-O"'),
                ("VALIDATE_PRODUCT", "YES"),
            ]
        )
    return common


def app_settings() -> list[tuple[str, str | list[str]]]:
    return [
        ("ASSETCATALOG_COMPILER_APPICON_NAME", "AppIcon"),
        ("ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME", "AccentColor"),
        ("CODE_SIGN_ENTITLEMENTS", "LidarRadar/LidarRadar.entitlements"),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("ENABLE_PREVIEWS", "YES"),
        ("GENERATE_INFOPLIST_FILE", "NO"),
        ("INFOPLIST_FILE", "LidarRadar/Info.plist"),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.1"),
        ("LD_RUNPATH_SEARCH_PATHS", ["$(inherited)", "@executable_path/Frameworks"]),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.kwok.lidarradar"),
        ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
        ("SUPPORTED_PLATFORMS", '"iphoneos iphonesimulator"'),
        ("SUPPORTS_MACCATALYST", "NO"),
        ("SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD", "NO"),
        ("SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD", "NO"),
        ("SWIFT_EMIT_LOC_STRINGS", "YES"),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", "1"),
    ]


def widget_settings() -> list[tuple[str, str | list[str]]]:
    return [
        ("APPLICATION_EXTENSION_API_ONLY", "YES"),
        ("CODE_SIGN_ENTITLEMENTS", "LidarRadarWidget/LidarRadarWidget.entitlements"),
        ("CODE_SIGN_STYLE", "Automatic"),
        ("CURRENT_PROJECT_VERSION", "1"),
        ("GENERATE_INFOPLIST_FILE", "NO"),
        ("INFOPLIST_FILE", "LidarRadarWidget/Info.plist"),
        ("IPHONEOS_DEPLOYMENT_TARGET", "16.1"),
        (
            "LD_RUNPATH_SEARCH_PATHS",
            ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
        ),
        ("MARKETING_VERSION", "1.0"),
        ("PRODUCT_BUNDLE_IDENTIFIER", "com.kwok.lidarradar.widget"),
        ("PRODUCT_NAME", '"$(TARGET_NAME)"'),
        ("SKIP_INSTALL", "YES"),
        ("SWIFT_EMIT_LOC_STRINGS", "YES"),
        ("SWIFT_VERSION", "5.0"),
        ("TARGETED_DEVICE_FAMILY", "1"),
    ]


def variant_child(project: Project, path: str, language: str) -> str:
    object_id = uid(f"variant {path}")
    project.add(
        object_id,
        language,
        "\t\t\tisa = PBXFileReference;\n"
        "\t\t\tlastKnownFileType = text.plist.strings;\n"
        f"\t\t\tname = {quote(language)};\n"
        f"\t\t\tpath = {quote(path)};\n"
        "\t\t\tsourceTree = SOURCE_ROOT;\n",
    )
    return object_id


def variant_group(project: Project, key: str, variants: list[tuple[str, str]]) -> str:
    object_id = uid(f"variantgroup {key}")
    children = []
    for language, path in variants:
        children.append((variant_child(project, path, language), language))
    lines = "\n".join(f"\t\t\t\t{child_id} /* {comment} */," for child_id, comment in children)
    project.add(
        object_id,
        "InfoPlist.strings",
        "\t\t\tisa = PBXVariantGroup;\n"
        "\t\t\tchildren = (\n"
        f"{lines}\n"
        "\t\t\t);\n"
        "\t\t\tname = InfoPlist.strings;\n"
        '\t\t\tsourceTree = "<group>";\n',
    )
    return object_id


def subgroup(project: Project, title: str, paths: list[str], refs: dict[str, str]) -> tuple[str, str]:
    children = [(refs[path], Path(path).name) for path in paths]
    return group(project, f"LidarRadar/{title}", title, children), title


def write_icon(path: Path) -> None:
    size = 1024
    raw = bytearray()
    center = (size - 1) / 2

    def blend(base: tuple[int, int, int], color: tuple[int, int, int], alpha: float) -> tuple[int, int, int]:
        alpha = max(0.0, min(1.0, alpha))
        return tuple(int(base[i] * (1 - alpha) + color[i] * alpha) for i in range(3))

    for y in range(size):
        raw.append(0)
        for x in range(size):
            dx = x - center
            dy = y - center
            radius = math.hypot(dx, dy)
            background = (11, 14, 19)
            vignette = min(1.0, radius / (size * 0.72))
            color = blend(background, (6, 8, 12), vignette * 0.85)
            color = blend(color, (18, 42, 36), max(0.0, 1 - radius / 280) * 0.55)
            for ring, width in ((150, 10), (270, 8), (390, 7)):
                color = blend(color, (61, 220, 151), max(0.0, 1 - abs(radius - ring) / width) * 0.9)
            angle = math.atan2(dy, dx)
            sweep_start = -2.35
            sweep_end = -0.35
            if radius < 430 and sweep_start <= angle <= sweep_end:
                edge = min(angle - sweep_start, sweep_end - angle) / 0.25
                color = blend(color, (61, 220, 151), max(0.0, min(1.0, edge)) * 0.28 * (1 - radius / 500))
            obstacle = math.hypot(dx - 210, dy + 150)
            color = blend(color, (255, 90, 96), max(0.0, 1 - obstacle / 42))
            color = blend(color, (255, 196, 92), max(0.0, 1 - obstacle / 16))
            color = blend(color, (232, 255, 244), max(0.0, 1 - radius / 28))
            color = blend(color, (61, 220, 151), max(0.0, 1 - abs(radius - 46) / 8))
            raw.extend(color)
    png = b"\x89PNG\r\n\x1a\n"

    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png += chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")
    path.write_bytes(png)


def generate() -> None:
    missing = [
        path
        for path in APP_SOURCES
        + APP_RESOURCES
        + WIDGET_SOURCES
        + WIDGET_RESOURCES
        + NAV_ONLY
        + [path for _, path in APP_INFO_STRINGS + WIDGET_INFO_STRINGS]
        if not (ROOT / path).exists()
    ]
    if missing:
        raise SystemExit("missing files:\n" + "\n".join(missing))

    project = Project()
    all_paths = []
    for path in APP_SOURCES + APP_RESOURCES + WIDGET_SOURCES + WIDGET_RESOURCES + NAV_ONLY:
        if path not in all_paths:
            all_paths.append(path)
    refs = {path: file_ref(project, path) for path in all_paths}

    framework_refs = {name: framework_ref(project, name) for name in dict.fromkeys(APP_FRAMEWORKS + WIDGET_FRAMEWORKS)}
    app_product = product_ref(project, "LidarRadar", "wrapper.application", "LidarRadar.app")
    widget_product = product_ref(project, "LidarRadarWidget", "wrapper.app-extension", "LidarRadarWidget.appex")

    def files_in(prefix: str) -> list[str]:
        return [path for path in all_paths if path.startswith(prefix)]

    app_groups = []
    for folder in ["AR", "Alerts", "LiveActivity", "PiP", "Services", "Views", "Shaders"]:
        paths = files_in(f"LidarRadar/{folder}/")
        app_groups.append(subgroup(project, folder, paths, refs))
    app_root_files = [
        path for path in files_in("LidarRadar/") if path.count("/") == 1
    ]
    app_info_strings = variant_group(project, "app InfoPlist", APP_INFO_STRINGS)
    widget_info_strings = variant_group(project, "widget InfoPlist", WIDGET_INFO_STRINGS)
    app_children = [(refs[path], Path(path).name) for path in app_root_files] + app_groups
    app_children.append((app_info_strings, "InfoPlist.strings"))
    app_group = group(project, "app", "LidarRadar", app_children)

    widget_files = [path for path in files_in("LidarRadarWidget/") if path.count("/") == 1]
    widget_children = [(refs[path], Path(path).name) for path in widget_files]
    widget_children.append((widget_info_strings, "InfoPlist.strings"))
    widget_group = group(project, "widget", "LidarRadarWidget", widget_children)
    shared_files = files_in("Shared/")
    shared_group = group(project, "shared", "Shared", [(refs[path], Path(path).name) for path in shared_files])
    script_group = group(project, "scripts", "scripts", [(refs["scripts/generate_xcodeproj.py"], "generate_xcodeproj.py")])

    framework_children = [(framework_refs[name], f"{name}.framework") for name in framework_refs]
    frameworks_group = group(project, "frameworks", "Frameworks", framework_children)
    products_group = group(
        project,
        "products",
        "Products",
        [(app_product, "LidarRadar.app"), (widget_product, "LidarRadarWidget.appex")],
    )
    main_children = [
        (app_group, "LidarRadar"),
        (widget_group, "LidarRadarWidget"),
        (shared_group, "Shared"),
        (script_group, "scripts"),
        (refs["README.md"], "README.md"),
        (refs["README.en.md"], "README.en.md"),
        (refs["project.yml"], "project.yml"),
        (frameworks_group, "Frameworks"),
        (products_group, "Products"),
    ]
    main_group = group(project, "main", "LidarRadar", main_children)

    def phase_files(paths: list[str], owner: str) -> list[tuple[str, str]]:
        result = []
        for path in paths:
            comment = f"{Path(path).name} in {owner}"
            result.append((build_file(project, f"{owner} {path}", refs[path], comment), comment))
        return result

    def framework_files(names: list[str], owner: str) -> list[tuple[str, str]]:
        result = []
        for name in names:
            comment = f"{name}.framework in {owner}"
            result.append(
                (build_file(project, f"{owner} framework {name}", framework_refs[name], comment), comment)
            )
        return result

    app_sources_phase = phase(project, "PBXSourcesBuildPhase", "Sources", phase_files(APP_SOURCES, "Sources"))
    app_frameworks_phase = phase(
        project, "PBXFrameworksBuildPhase", "Frameworks", framework_files(APP_FRAMEWORKS, "Frameworks")
    )
    app_resource_files = phase_files(APP_RESOURCES, "Resources")
    app_strings_comment = "InfoPlist.strings in Resources"
    app_resource_files.append(
        (
            build_file(project, "app InfoPlist.strings", app_info_strings, app_strings_comment),
            app_strings_comment,
        )
    )
    app_resources_phase = phase(project, "PBXResourcesBuildPhase", "Resources", app_resource_files)
    embed_comment = "LidarRadarWidget.appex in Embed Foundation Extensions"
    embed_file = build_file(
        project,
        "embed widget",
        widget_product,
        embed_comment,
        "{ATTRIBUTES = (CodeSignOnCopy, RemoveHeadersOnCopy, ); }",
    )
    embed_phase = phase(
        project,
        "PBXCopyFilesBuildPhase",
        "Embed Foundation Extensions",
        [(embed_file, embed_comment)],
        "\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n",
    )

    widget_sources_phase = phase(
        project, "PBXSourcesBuildPhase", "Widget Sources", phase_files(WIDGET_SOURCES, "Widget Sources")
    )
    widget_frameworks_phase = phase(
        project,
        "PBXFrameworksBuildPhase",
        "Widget Frameworks",
        framework_files(WIDGET_FRAMEWORKS, "Widget Frameworks"),
    )
    widget_resource_files = phase_files(WIDGET_RESOURCES, "Widget Resources")
    widget_strings_comment = "InfoPlist.strings in Widget Resources"
    widget_resource_files.append(
        (
            build_file(project, "widget InfoPlist.strings", widget_info_strings, widget_strings_comment),
            widget_strings_comment,
        )
    )
    widget_resources_phase = phase(
        project, "PBXResourcesBuildPhase", "Widget Resources", widget_resource_files
    )

    app_target = uid("target LidarRadar")
    widget_target = uid("target LidarRadarWidget")
    project_id = uid("PBXProject")
    proxy = uid("proxy widget")
    dependency = uid("dependency widget")

    project.add(
        proxy,
        "PBXContainerItemProxy",
        "\t\t\tisa = PBXContainerItemProxy;\n"
        f"\t\t\tcontainerPortal = {project_id} /* Project object */;\n"
        "\t\t\tproxyType = 1;\n"
        f"\t\t\tremoteGlobalIDString = {widget_target};\n"
        "\t\t\tremoteInfo = LidarRadarWidget;\n",
    )
    project.add(
        dependency,
        "PBXTargetDependency",
        "\t\t\tisa = PBXTargetDependency;\n"
        f"\t\t\ttarget = {widget_target} /* LidarRadarWidget */;\n"
        f"\t\t\ttargetProxy = {proxy} /* PBXContainerItemProxy */;\n",
    )

    app_debug = config(project, "Debug", "app", app_settings())
    app_release = config(project, "Release", "app", app_settings())
    widget_debug = config(project, "Debug", "widget", widget_settings())
    widget_release = config(project, "Release", "widget", widget_settings())
    proj_debug = config(project, "Debug", "project", project_settings("Debug"))
    proj_release = config(project, "Release", "project", project_settings("Release"))
    app_list = config_list(project, 'PBXNativeTarget "LidarRadar"', app_debug, app_release)
    widget_list = config_list(project, 'PBXNativeTarget "LidarRadarWidget"', widget_debug, widget_release)
    project_list = config_list(project, "PBXProject", proj_debug, proj_release)

    project.add(
        widget_target,
        "LidarRadarWidget",
        "\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {widget_list} /* Build configuration list for PBXNativeTarget \"LidarRadarWidget\" */;\n"
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{widget_sources_phase} /* Widget Sources */,\n"
        f"\t\t\t\t{widget_frameworks_phase} /* Widget Frameworks */,\n"
        f"\t\t\t\t{widget_resources_phase} /* Widget Resources */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        "\t\t\t);\n"
        "\t\t\tname = LidarRadarWidget;\n"
        "\t\t\tproductName = LidarRadarWidget;\n"
        f"\t\t\tproductReference = {widget_product} /* LidarRadarWidget.appex */;\n"
        '\t\t\tproductType = "com.apple.product-type.app-extension";\n',
    )
    project.add(
        app_target,
        "LidarRadar",
        "\t\t\tisa = PBXNativeTarget;\n"
        f"\t\t\tbuildConfigurationList = {app_list} /* Build configuration list for PBXNativeTarget \"LidarRadar\" */;\n"
        "\t\t\tbuildPhases = (\n"
        f"\t\t\t\t{app_sources_phase} /* Sources */,\n"
        f"\t\t\t\t{app_frameworks_phase} /* Frameworks */,\n"
        f"\t\t\t\t{app_resources_phase} /* Resources */,\n"
        f"\t\t\t\t{embed_phase} /* Embed Foundation Extensions */,\n"
        "\t\t\t);\n"
        "\t\t\tbuildRules = (\n"
        "\t\t\t);\n"
        "\t\t\tdependencies = (\n"
        f"\t\t\t\t{dependency} /* PBXTargetDependency */,\n"
        "\t\t\t);\n"
        "\t\t\tname = LidarRadar;\n"
        "\t\t\tproductName = LidarRadar;\n"
        f"\t\t\tproductReference = {app_product} /* LidarRadar.app */;\n"
        '\t\t\tproductType = "com.apple.product-type.application";\n',
    )
    project.add(
        project_id,
        "Project object",
        "\t\t\tisa = PBXProject;\n"
        "\t\t\tattributes = {\n"
        "\t\t\t\tBuildIndependentTargetsInParallel = 1;\n"
        "\t\t\t\tLastSwiftUpdateCheck = 1600;\n"
        "\t\t\t\tLastUpgradeCheck = 1600;\n"
        "\t\t\t\tORGANIZATIONNAME = Kwok;\n"
        "\t\t\t\tTargetAttributes = {\n"
        f"\t\t\t\t\t{app_target} = {{\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n"
        "\t\t\t\t\t\tProvisioningStyle = Automatic;\n"
        "\t\t\t\t\t};\n"
        f"\t\t\t\t\t{widget_target} = {{\n"
        "\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n"
        "\t\t\t\t\t\tProvisioningStyle = Automatic;\n"
        "\t\t\t\t\t};\n"
        "\t\t\t\t};\n"
        "\t\t\t};\n"
        f"\t\t\tbuildConfigurationList = {project_list} /* Build configuration list for PBXProject */;\n"
        '\t\t\tcompatibilityVersion = "Xcode 14.0";\n'
        '\t\t\tdevelopmentRegion = en;\n'
        "\t\t\thasScannedForEncodings = 0;\n"
        "\t\t\tknownRegions = (\n"
        "\t\t\t\ten,\n"
        "\t\t\t\tBase,\n"
        '\t\t\t\t"zh-Hant",\n'
        "\t\t\t);\n"
        f"\t\t\tmainGroup = {main_group} /* LidarRadar */;\n"
        f"\t\t\tproductRefGroup = {products_group} /* Products */;\n"
        '\t\t\tprojectDirPath = "";\n'
        '\t\t\tprojectRoot = "";\n'
        "\t\t\ttargets = (\n"
        f"\t\t\t\t{app_target} /* LidarRadar */,\n"
        f"\t\t\t\t{widget_target} /* LidarRadarWidget */,\n"
        "\t\t\t);\n",
    )

    text = project.render()
    if text.count("{") != text.count("}"):
        raise SystemExit("unbalanced braces")
    if text.count("(") != text.count(")"):
        raise SystemExit("unbalanced parentheses")
    for object_id in project.seen:
        if text.count(object_id) < 2:
            raise SystemExit(f"id {object_id} is never referenced")

    PROJECT.mkdir(parents=True, exist_ok=True)
    (PROJECT / "project.pbxproj").write_text(text, encoding="utf-8")
    scheme_dir = PROJECT / "xcshareddata" / "xcschemes"
    scheme_dir.mkdir(parents=True, exist_ok=True)
    (scheme_dir / "LidarRadar.xcscheme").write_text(scheme(app_target, widget_target), encoding="utf-8")
    icon_path = ROOT / "LidarRadar" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
    write_icon(icon_path)
    print(f"wrote {PROJECT / 'project.pbxproj'}")
    print(f"wrote {icon_path} ({icon_path.stat().st_size} bytes)")


def scheme(app_target: str, widget_target: str) -> str:
    def ref(target: str, name: str, product: str) -> str:
        return f"""         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{target}"
            BuildableName = "{product}"
            BlueprintName = "{name}"
            ReferencedContainer = "container:LidarRadar.xcodeproj">
         </BuildableReference>"""

    app_ref = ref(app_target, "LidarRadar", "LidarRadar.app")
    widget_ref = ref(widget_target, "LidarRadarWidget", "LidarRadarWidget.appex")
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1600"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
{app_ref}
         </BuildActionEntry>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
{widget_ref}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{app_ref}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
{app_ref}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""


if __name__ == "__main__":
    generate()
