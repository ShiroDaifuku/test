# ios-overlay — MDPro3 iOS 覆盖层(构建时应用)

## 为什么需要覆盖层
- 基线 `src\MDPro3-main`(约 962MB,含大量素材与 GBK 编码源文件)保持**不动**;
- iOS 改动以「新增文件 + 字节级替换脚本」表达,在**云构建机上**对最新解压的基线实施;
- 这样 `ShiroDaifuku/test`(public)只需存本覆盖层(全部为自有代码),不碰任何素材/基线内容。

## 目录结构
```
ios-overlay/
├── README.md                      本说明
├── overlay.js                     node 脚本:node overlay.js <基线工程根目录>
│                                    ① 按 transforms 表做字节级替换(仅 ASCII 目标行,GBK/UTF8 均可)
│                                    ② 把 new-files/ 整体拷入基线工程
└── new-files/                     新增/覆盖文件(相对 Unity 工程根)
    └── Assets/
        ├── Editor/MDPro3iOSBuild.cs   批处理导出 iOS(见代码头注释)
        └── link.xml                   IL2CPP 裁剪保留清单(草稿)
```

## transforms 表如何维护
`overlay.js` 顶部的 `TRANSFORMS` 数组,每项 `{ file, from, to, note }`:
- `from` 必须与基线文件**逐字节一致**(用编辑器看空格/Tab);脚本找不到会**报警并标 FAIL**(不静默);
- 只改 ASCII 行 → 不会破坏 GBK 注释行字节;
- 新增逻辑优先以**独立新文件**落地(overlay 机制二),仅当必须改既有方法体时才用替换。

当前已实现(与 `../ios-适配点清单.md` 对应):
| 项 | 文件 | 替换内容 | 清单条目 |
|---|---|---|---|
| T1 | `Assets/Scripts/MDPro3/Boot.cs` | 平台守卫扩到 iOS | G1 |
| T2 | 同文件 37-40 行 | Android 用 BetterStreamingAssets;iOS 用 `Directory.GetFiles(streamingAssetsPath)` | G1 |
| T3 | `Assets/Scripts/MDPro3/Program.cs` | 新增 `rootIos` 常量并在 Awake 按 iOS 赋值 | G2 |

> 后续按适配点清单逐条追加(ABLoader/MonsterCutin/OcgCore 的 Windows 写点、ATS 后处理等)。

## 本地自测方法(改完 transforms 后)
```
node overlay.js "D:\fish\MDPro3移植iOS评估\src\MDPro3-main"
# 然后 grep 确认目标行已变(如 grep "UNITY_IOS" src\MDPro3-main\Assets\Scripts\MDPro3\Boot.cs)
# 基线如需还原:重新解压 .downloads\mdpro3-baseline.zip
```
