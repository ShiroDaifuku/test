#!/usr/bin/env bash
# ============================================================================
# MDPro3 iOS 原生库交叉编译(macOS runner · xcrun · iphoneos arm64)
# 用法: bash build-ios-libs.sh <项目根> <输出目录>
# 产物:liblua.a libsqlite3.a libevent.a libirrlicht.a libclzma.a libcspmemvfs.a libocgcore.a libygoserver.a
# 依据:各组件 Android.mk 的源文件集/宏 + iOS 平台修正(epoll->kqueue、event-config 派生)
# 说明:静态库相互独立归档;最终由 Unity iOS 工程统一链接。
# ============================================================================
set -uo pipefail

ROOT="${1:?usage: build-ios-libs.sh <projectRoot> <outDir>}"
OUT="${2:?usage: build-ios-libs.sh <projectRoot> <outDir>}"
NC="$ROOT/Tools/YGO Classes"

SDK_NAME="iphoneos"
SDK="$(xcrun --sdk $SDK_NAME --show-sdk-path)"
ARCH="arm64"
MIN="16.0"

CC="$(xcrun --sdk $SDK_NAME --find clang)"
CXX="$(xcrun --sdk $SDK_NAME --find clang++)"
AR="$(xcrun --sdk $SDK_NAME --find ar)"

BASE_FLAGS="-arch $ARCH -isysroot $SDK -miphoneos-version-min=$MIN -O2 -fno-objc-arc -Wno-unused-command-line-argument"
C_FLAGS="$BASE_FLAGS"
CXX_FLAGS="$BASE_FLAGS -std=gnu++14"

OBJROOT="$OUT/.obj"
GENCFG="$OUT/.gencfg"
mkdir -p "$OBJROOT" "$GENCFG/event2"

echo "[ios-native] sdk=$SDK_NAME arch=$ARCH min=$MIN"
echo "[ios-native] root=$ROOT"

# 1) 派生 iOS 版 event-config.h(以 android 版为底,关 epoll/eventfd,开 kqueue)
SRC_CFG="$NC/event/android/event2/event-config.h"
DST_CFG="$GENCFG/event2/event-config.h"
if [[ -f "$SRC_CFG" ]]; then
  {
    sed -e 's|^#define \(_EVENT_HAVE_EPOLL[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_SYS_EPOLL[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_[A-Z_]*EVENTFD[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_[A-Z_]*TIMERFD[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_[A-Z_]*SENDFILE[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_[A-Z_]*NETINET_IN6[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_[A-Z_]*SYS_SENDFILE[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_SELECT[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_POLL[A-Z_]*\).*|/* #undef \1 */|' \
        -e 's|^#define \(_EVENT_HAVE_DEVPOLL[A-Z_]*\).*|/* #undef \1 */|' \
        "$SRC_CFG"
    printf '\n/* iOS adjustments */\n#ifndef _EVENT_HAVE_KQUEUE\n#define _EVENT_HAVE_KQUEUE 1\n#endif\n#ifndef _EVENT_HAVE_SYS_EVENT_H\n#define _EVENT_HAVE_SYS_EVENT_H 1\n#endif\n#ifndef _EVENT_HAVE_SYS_SOCKET_H\n#define _EVENT_HAVE_SYS_SOCKET_H 1\n#endif\n#ifndef _EVENT_HAVE_NETINET_IN_H\n#define _EVENT_HAVE_NETINET_IN_H 1\n#endif\n#ifndef _EVENT_HAVE_ARPA_INET_H\n#define _EVENT_HAVE_ARPA_INET_H 1\n#endif\n'
  } > "$DST_CFG"
  echo "[ios-native] event-config: iOS-adjusted -> $DST_CFG"
else
  echo "[ios-native] WARN: android event-config.h not found; continuing without it"
  touch "$DST_CFG"
fi

# 2) 各组件编译
build_lib() { # name srcKind incs defs ... 文件列表(每行一个相对 NC 路径)
  local name="$1"; shift
  local kind="$1"; shift       # c | cxx
  local incs="$1"; shift       # ; 分隔 include 相对路径(相对 NC)
  local defs="$1"; shift
  local objdir="$OBJROOT/$name"; mkdir -p "$objdir"
  local objs=()
  local incargs=()
  # event/ygoserver 需优先命中 iOS 派生的 event2/event-config.h
  if [[ "$name" == "event" || "$name" == "ygoserver" || "$name" == "ocgcore" ]]; then
    incargs+=("-I" "$GENCFG")
  fi
  local IFS=';'
  for inc in $incs; do incargs+=("-I" "$NC/$inc"); done
  IFS=$' \t\n'
  local defargs=()
  local IFS=';'
  for d in $defs; do defargs+=("$d"); done
  IFS=$' \t\n'
  local src f o use_kind
  for src in "$@"; do
    use_kind="$kind"
    case "$src" in
      c:*) src="${src#c:}"; use_kind="c";;
      cxx:*) src="${src#cxx:}"; use_kind="cxx";;
    esac
    f="$NC/$src"
    if [[ ! -f "$f" ]]; then echo "[ios-native] MISSING $src"; continue; fi
    o="$objdir/$(echo "$src" | tr '/' '_' | tr '.' '_').o"
    if [[ "$use_kind" == "c" ]]; then
      # bash3-safe: 空数组在 set -u 下需守卫展开
      "$CC" $C_FLAGS ${defargs[@]+"${defargs[@]}"} ${incargs[@]+"${incargs[@]}"} -c "$f" -o "$o" || { echo "CC FAIL $src"; exit 1; }
    else
      "$CXX" $CXX_FLAGS ${defargs[@]+"${defargs[@]}"} ${incargs[@]+"${incargs[@]}"} -c "$f" -o "$o" || { echo "CXX FAIL $src"; exit 1; }
    fi
    objs+=("$o")
  done
  if [[ ${#objs[@]} -eq 0 ]]; then echo "[ios-native] NO OBJECTS for $name"; exit 1; fi
  "$AR" rcs "$OUT/lib$name.a" "${objs[@]}" || { echo "AR FAIL $name"; exit 1; }
  echo "[ios-native] lib$name.a ($(ls -la "$OUT/lib$name.a" | awk '{print $5}') bytes, ${#objs[@]} objs)"
}

EVENT_INCS="event/android;event;event/include;event/compat"
LUA_INCS="lua/src"
SQLITE_INCS="sqlite3"
IRR_INCS="irrlicht/include;irrlicht/source/Irrlicht;irrlicht/source/Irrlicht/zlib"
CLZMA_INCS="ygoserver/lzma"
SPM_INCS="ygoserver/spmemvfs;sqlite3"
OCG_INCS="ocgcore;lua/src"
YGO_INCS="ygoserver/spmemvfs;ygoserver;ocgcore;event/android;event/include;event;sqlite3;irrlicht/source/Irrlicht;irrlicht/include"

# lua(C,静态;iOS:system() 不可用 → l_system 空操作;补 getlocaledecpoint 宏)
build_lib lua c "$LUA_INCS" "-DLUA_USE_POSIX;-fexceptions;-Dl_system(cmd)=(0);-Dgetlocaledecpoint()='.'" \
  lua/src/lapi.c lua/src/lauxlib.c lua/src/lbaselib.c lua/src/lcode.c lua/src/lcorolib.c lua/src/lctype.c \
  lua/src/ldblib.c lua/src/ldebug.c lua/src/ldo.c lua/src/ldump.c lua/src/lfunc.c lua/src/lgc.c lua/src/linit.c \
  lua/src/liolib.c lua/src/llex.c lua/src/lmathlib.c lua/src/lmem.c lua/src/loadlib.c lua/src/lobject.c \
  lua/src/lopcodes.c lua/src/loslib.c lua/src/lparser.c lua/src/lstate.c lua/src/lstring.c lua/src/lstrlib.c \
  lua/src/ltable.c lua/src/ltablib.c lua/src/ltm.c lua/src/lua.c lua/src/lundump.c lua/src/lutf8lib.c lua/src/lvm.c lua/src/lzio.c

# sqlite3(C)
build_lib sqlite3 c "$SQLITE_INCS" "" sqlite3/sqlite3.c

# event(C,iOS:android 清单把 epoll.c 换成 kqueue.c)
build_lib event c "$EVENT_INCS" "" \
  event/event.c event/buffer.c event/bufferevent.c event/bufferevent_sock.c event/bufferevent_pair.c \
  event/listener.c event/evmap.c event/log.c event/evutil.c event/strlcpy.c event/signal.c \
  event/bufferevent_filter.c event/evthread.c event/evthread_pthread.c event/bufferevent_ratelim.c \
  event/evutil_rand.c event/event_tagging.c event/http.c event/evdns.c event/evrpc.c \
  event/kqueue.c

# irrlicht(zipreader 子集;zlib 的 .c 必须以 C 编译 → c: 前缀;premake: 关异常/RTTI)
build_lib irrlicht cxx "$IRR_INCS" "-D_IRR_STATIC_LIB_;-DNO_IRR_COMPILE_WITH_ZIP_ENCRYPTION_;-DNO_IRR_COMPILE_WITH_BZIP2_;-DNO__IRR_COMPILE_WITH_MOUNT_ARCHIVE_LOADER_;-DNO__IRR_COMPILE_WITH_PAK_ARCHIVE_LOADER_;-DNO__IRR_COMPILE_WITH_NPK_ARCHIVE_LOADER_;-DNO__IRR_COMPILE_WITH_TAR_ARCHIVE_LOADER_;-DNO__IRR_COMPILE_WITH_WAD_ARCHIVE_LOADER_;-fno-exceptions;-fno-rtti" \
  irrlicht/source/Irrlicht/os.cpp \
  c:irrlicht/source/Irrlicht/zlib/adler32.c c:irrlicht/source/Irrlicht/zlib/crc32.c c:irrlicht/source/Irrlicht/zlib/inffast.c \
  c:irrlicht/source/Irrlicht/zlib/inflate.c c:irrlicht/source/Irrlicht/zlib/inftrees.c c:irrlicht/source/Irrlicht/zlib/zutil.c \
  irrlicht/source/Irrlicht/CAttributes.cpp irrlicht/source/Irrlicht/CFileList.cpp irrlicht/source/Irrlicht/CFileSystem.cpp \
  irrlicht/source/Irrlicht/CLimitReadFile.cpp irrlicht/source/Irrlicht/CMemoryFile.cpp irrlicht/source/Irrlicht/CReadFile.cpp \
  irrlicht/source/Irrlicht/CWriteFile.cpp irrlicht/source/Irrlicht/CXMLReader.cpp irrlicht/source/Irrlicht/CXMLWriter.cpp \
  irrlicht/source/Irrlicht/CZipReader.cpp

# clzma(C)
build_lib clzma c "$CLZMA_INCS" "" \
  ygoserver/lzma/Alloc.c ygoserver/lzma/LzFind.c ygoserver/lzma/LzmaDec.c ygoserver/lzma/LzmaEnc.c ygoserver/lzma/LzmaLib.c

# cspmemvfs(C)
build_lib cspmemvfs c "$SPM_INCS" "" ygoserver/spmemvfs/spmemvfs.c

# ocgcore(C++)
build_lib ocgcore cxx "$OCG_INCS" "-frtti;-Wno-format-security;-Wno-logical-op-parentheses;-Wno-parentheses" \
  ocgcore/card.cpp ocgcore/duel.cpp ocgcore/effect.cpp ocgcore/field.cpp ocgcore/group.cpp ocgcore/interpreter.cpp \
  ocgcore/libcard.cpp ocgcore/libdebug.cpp ocgcore/libduel.cpp ocgcore/libeffect.cpp ocgcore/libgroup.cpp ocgcore/mem.cpp \
  ocgcore/ocgapi.cpp ocgcore/operations.cpp ocgcore/playerop.cpp ocgcore/processor.cpp ocgcore/scriptlib.cpp

# ygoserver(C++)
build_lib ygoserver cxx "$YGO_INCS" "-DYGOPRO_SERVER_MODE;-DSERVER_ZIP_SUPPORT;-DSERVER_PRO2_SUPPORT;-DSERVER_PRO3_SUPPORT;-DSERVER_TAG_SURRENDER_CONFIRM;-Wno-format-security;-Wno-logical-op-parentheses;-Wno-parentheses" \
  ygoserver/data_manager.cpp ygoserver/deck_manager.cpp ygoserver/game.cpp ygoserver/gframe.cpp ygoserver/netserver.cpp \
  ygoserver/replay.cpp ygoserver/serverapi.cpp ygoserver/single_duel.cpp ygoserver/tag_duel.cpp

echo "[ios-native] all libs done:"
ls -la "$OUT"/lib*.a
