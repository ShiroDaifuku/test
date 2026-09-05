// ============================================================================
// overlay.js — MDPro3 iOS 覆盖层实施脚本(在云构建机 / 本地对基线工程执行)
// 用法:node overlay.js <基线Unity工程根目录>
// 依赖:Node 18+(自带 fetch/fs)。本脚本不产生网络请求、不读取任何密钥。
// ============================================================================
const fs = require('fs');
const path = require('path');

const ROOT = process.argv[2];
if (!ROOT || !fs.existsSync(ROOT)) {
  console.error('用法: node overlay.js <基线Unity工程根目录>');
  process.exit(2);
}

// ---------------------------------------------------------------------------
// ① 字节级替换表:{ file, from, to, note }
//    from 必须与基线文件逐字节一致;找不到即 FAIL(不静默,便于发现基线漂移)
// ---------------------------------------------------------------------------
const TRANSFORMS = [
  {
    file: 'Assets/Scripts/MDPro3/Boot.cs',
    from: '#if !UNITY_EDITOR && UNITY_ANDROID',
    to: '#if !UNITY_EDITOR && (UNITY_ANDROID || UNITY_IOS)',
    note: 'G1:首启数据播种平台守卫扩到 iOS',
  },
  {
    file: 'Assets/Scripts/MDPro3/Boot.cs',
    from: [
      '                BetterStreamingAssets.Initialize();',
      '                var paths = BetterStreamingAssets.GetFiles("\\\\", "*.zip");',
      '                foreach (var zip in paths)',
      '                    zips.Add(Path.GetFileName(zip).Replace(".zip", ""));',
    ].join('\n'),
    to: [
      '#if UNITY_ANDROID',
      '                BetterStreamingAssets.Initialize();',
      '                var paths = BetterStreamingAssets.GetFiles("\\\\", "*.zip");',
      '                foreach (var zip in paths)',
      '                    zips.Add(Path.GetFileName(zip).Replace(".zip", ""));',
      '#else',
      '                // iOS: StreamingAssets is on real disk; enumerate directly (BetterStreamingAssets only works in Editor/Android)',
      '                foreach (var zip in System.IO.Directory.GetFiles(UnityEngine.Application.streamingAssetsPath, "*.zip"))',
      '                    zips.Add(System.IO.Path.GetFileName(zip).Replace(".zip", ""));',
      '#endif',
    ].join('\n'),
    note: 'G1:iOS 分支用文件系统枚举 StreamingAssets 下的 *.zip',
  },
  {
    file: 'Assets/Scripts/MDPro3/Program.cs',
    from: '        public const string rootAndroid = "Android/";',
    to: '        public const string rootAndroid = "Android/";\n        public const string rootIos = "iOS/";',
    note: 'G2:新增 iOS 内容根目录常量',
  },
  {
    file: 'Assets/Scripts/MDPro3/Program.cs',
    from: '#if UNITY_ANDROID\n            root = rootAndroid;\n#endif',
    to: '#if UNITY_ANDROID\n            root = rootAndroid;\n#elif UNITY_IOS\n            root = rootIos;\n#endif',
    note: 'G2:Awake 内按 iOS 赋值 root',
  },
];

// ---------------------------------------------------------------------------
// ② 需要整体拷入基线的文件(相对本文件目录 new-files/)
// ---------------------------------------------------------------------------
const COPY_DIR = path.join(__dirname, 'new-files');

function fail(msg) { console.error('FAIL: ' + msg); process.exitCode = 1; }
function ok(msg) { console.log('  ok  ' + msg); }

function applyTransforms() {
  console.log('[1/2] transforms ...');
  for (const t of TRANSFORMS) {
    const fp = path.join(ROOT, t.file);
    if (!fs.existsSync(fp)) { fail(t.file + ' 不存在'); continue; }
    const buf = fs.readFileSync(fp);
    const hay = buf.toString('latin1');
    const from = Buffer.from(t.from, 'utf8').toString('latin1');
    if (!hay.includes(from)) { fail(t.file + ' 未匹配替换目标 → ' + t.note); continue; }
    const to = Buffer.from(t.to, 'utf8').toString('latin1');
    // 保持原文件字节数/编码风格:latin1 层面替换等价于字节替换
    fs.writeFileSync(fp, Buffer.from(hay.split(from).join(to), 'latin1'));
    ok(t.file + ' → ' + t.note);
  }
}

function copyNewFiles() {
  console.log('[2/2] copy new-files ...');
  if (!fs.existsSync(COPY_DIR)) { ok('(new-files 不存在,跳过)'); return; }
  const walk = (dir) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      const s = path.join(dir, e.name);
      if (e.isDirectory()) walk(s);
      else {
        const rel = path.relative(COPY_DIR, s).split(path.sep).join('/');
        const dest = path.join(ROOT, rel);
        fs.mkdirSync(path.dirname(dest), { recursive: true });
        fs.copyFileSync(s, dest);
        ok('+ ' + rel);
      }
    }
  };
  walk(COPY_DIR);
}

applyTransforms();
copyNewFiles();
console.log(process.exitCode ? 'overlay 存在失败项,请检查上方 FAIL' : 'overlay 完成 ✅');
