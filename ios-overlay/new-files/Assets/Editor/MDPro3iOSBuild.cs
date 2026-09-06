// ============================================================================
// MDPro3 iOS Build(Editor 批处理入口)— 草稿 v2(首轮云构建联调中)
// 放置路径:Assets/Editor/MDPro3iOSBuild.cs(由 ios-overlay 在构建时拷入)
// 用途:Unity -batchmode 下直接导出 iOS Xcode 工程,无需人工打开编辑器。
// 调用方式(由 GitHub Actions 执行):
//   Unity -batchmode -nographics -quit -projectPath . -executeMethod MDPro3iOSBuild.Build
// 环境变量: IOS_BUNDLE_ID / IOS_TARGET_OS / IOS_OUTPUT(默认 Build/iOS)
// ============================================================================
using System;
using System.IO;
using System.Linq;
using System.Collections.Generic;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

public static class MDPro3iOSBuild
{
    public static void Build()
    {
        try
        {
            ConfigureNativePlugins();
            var bundleId = Env("IOS_BUNDLE_ID", "com.shirodaifuku.mdpro3");
            var targetOs = Env("IOS_TARGET_OS", "16.0");
            var outDir = Path.GetFullPath(Env("IOS_OUTPUT", "Build/iOS"));

            // --- iOS 平台基本设置(第 1 版先取保守默认,后续按真机反馈调整)---
            PlayerSettings.companyName = Env("IOS_COMPANY_NAME", "ShiroDaifuku");
            PlayerSettings.productName = "MDPro3";
            PlayerSettings.SetApplicationIdentifier(BuildTargetGroup.iOS, bundleId);

            // IL2CPP + arm64 是 iOS 默认;显式声明,避免误改
            PlayerSettings.SetScriptingBackend(BuildTargetGroup.iOS, ScriptingImplementation.IL2CPP);
            PlayerSettings.SetArchitecture(BuildTargetGroup.iOS, 1 /*ARM64*/);

            // iOS 版本与设备目标
            PlayerSettings.iOS.targetOSVersionString = targetOs;   // 例 "16.0"
            PlayerSettings.iOS.sdkVersion = iOSSdkVersion.Device;  // 真机包;模拟器联调时改 Simulator
            PlayerSettings.iOS.targetDevice = iOSTargetDevice.iPhoneAndiPad;

            // 界面方向(先自动旋转;若联调发现卡牌对局需横屏,改 Landscape)
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.AutoRotation;

            Directory.CreateDirectory(outDir);
            var scenes = EditorBuildSettings.scenes
                .Where(s => s.enabled)
                .Select(s => s.path)
                .ToArray();
            if (scenes.Length == 0)
                throw new Exception("EditorBuildSettings 无启用场景(Boot.unity 缺失?)");
            Debug.Log("[MDPro3iOSBuild] scenes: " + string.Join(",", scenes));

            // 切换到 iOS 目标(触发平台资源导入,首次会较慢)
            EditorUserBuildSettings.SwitchActiveBuildTarget(BuildTargetGroup.iOS, BuildTarget.iOS);

            var report = BuildPipeline.BuildPlayer(
                scenes, outDir, BuildTarget.iOS, BuildOptions.None);

            if (report.summary.result != BuildResult.Succeeded)
                throw new Exception("iOS build failed: " + report.summary.result + ", totalErrors=" + report.summary.totalErrors);
            Debug.Log("[MDPro3iOSBuild] SUCCESS -> " + outDir);
            EditorApplication.Exit(0);
        }
        catch (Exception e)
        {
            Debug.LogError("[MDPro3iOSBuild] FAILED: " + e);
            EditorApplication.Exit(1);
        }
    }

    // --- 原生静态库插件配置:Assets/Plugins/iOS/lib*.a ---
    // 默认:仅 iOS + arm64;DllImport 名 = 去 lib 前缀/扩展(ocgcore/ygoserver/sqlite3)
    static void ConfigureNativePlugins()
    {
        var nameOf = new Dictionary<string, string>
        {
            { "libocgcore.a", "ocgcore" },
            { "libygoserver.a", "ygoserver" },
            { "libsqlite3.a", "sqlite3" },
        };
        int n = 0;
        foreach (var importer in PluginImporter.GetAllImporters())
        {
            var p = importer.assetPath.Replace('\\', '/');
            if (!p.Contains("/iOS/lib") || !p.EndsWith(".a")) continue;
            var fname = Path.GetFileName(p);
            importer.SetCompatibleWithAnyPlatform(false);
            importer.SetCompatibleWithEditor(false);
            importer.SetCompatibleWithPlatform(BuildTarget.iOS, true);
            importer.SetPlatformData(BuildTarget.iOS, "CPU", "ARM64");
            string dllName;
            if (nameOf.TryGetValue(fname, out dllName))
                importer.SetPlatformData(BuildTarget.iOS, "Name", dllName);
            importer.SaveAndReimport();
            n++;
            Debug.Log("[MDPro3iOSBuild] plugin configured: " + fname +
                (nameOf.ContainsKey(fname) ? " -> " + nameOf[fname] : ""));
        }
        if (n == 0)
            Debug.LogWarning("[MDPro3iOSBuild] Assets/Plugins/iOS 下未找到 lib*.a —— 原生库未接入?");
    }

    private static string Env(string k, string def)
    {
        var v = Environment.GetEnvironmentVariable(k);
        return string.IsNullOrEmpty(v) ? def : v;
    }
}
