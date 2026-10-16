#!/usr/bin/env bash
# 图片分拣脚本（Linux / macOS）
#
# 依赖: jq（解析 JSON）
# 可选: exiftool（读拍摄时间、宽高、GPS；比例/位置筛选必须依赖它）
#
# 用法:
#   ./sort_photos.sh -s <源目录> -d <目标目录> [选项]
#
# 选项:
#   -r <file>     规则文件（默认: 脚本同目录的 rules.json）
#   -m <mode>     copy | move | hardlink | symlink（默认 copy）
#   --flat        不保留子目录结构
#   --overwrite   目标已存在时覆盖
#   --dry-run     只列清单，不写文件
#   --log <file>  日志文件（默认: 脚本同目录的 sort_photos.log）
#   --no-log      不写日志
#   -h, --help    显示帮助

set -euo pipefail

SRC=""
DST=""
RULES="$(dirname "$0")/rules.json"
MODE="copy"
PRESERVE=1
OVERWRITE=0
DRY_RUN=0
LOG_FILE="$(dirname "$0")/sort_photos.log"
ENABLE_LOG=1

usage() {
  sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -s) SRC="$2"; shift 2 ;;
    -d) DST="$2"; shift 2 ;;
    -r) RULES="$2"; shift 2 ;;
    -m) MODE="$2"; shift 2 ;;
    --flat) PRESERVE=0; shift ;;
    --overwrite) OVERWRITE=1; shift ;;
    --dry-run) DRY_RUN=1; shift ;;
    --log) LOG_FILE="$2"; shift 2 ;;
    --no-log) ENABLE_LOG=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "未知参数: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$SRC" || -z "$DST" ]]; then
  echo "缺少必要参数。" >&2
  usage
  exit 1
fi

if [[ ! -d "$SRC" ]]; then echo "源目录不存在: $SRC" >&2; exit 1; fi
if [[ ! -f "$RULES" ]]; then echo "规则文件不存在: $RULES" >&2; exit 1; fi
if ! command -v jq >/dev/null; then echo "需要 jq，请先安装。" >&2; exit 1; fi

# ---------- 读取筛选开关 ----------
ASPECT_ENABLED=$(jq -r '.aspect_rules.enabled // false' "$RULES")
GPS_ENABLED=$(jq -r '.gps_rules.enabled // false' "$RULES")
FT_ENABLED=$(jq -r '.filename_time.enabled // false' "$RULES")
FT_MODE=$(jq -r '.filename_time.mode // "auto"' "$RULES")
FT_TEMPLATE=$(jq -r '.filename_time.template // ""' "$RULES")
FT_PRIORITY=$(jq -r '.filename_time.priority // "after_exif"' "$RULES")

HAS_EXIFTOOL=0
if command -v exiftool >/dev/null 2>&1; then HAS_EXIFTOOL=1; fi

# ---------- 决定需要读取哪些元数据 ----------
NEED_EXIF_TIME=0
NEED_EXIF_WH=0
NEED_EXIF_GPS=0

if [[ "$FT_ENABLED" != "true" || "$FT_PRIORITY" != "before_exif" ]]; then
  NEED_EXIF_TIME=1
fi
if [[ "$ASPECT_ENABLED" == "true" ]]; then
  NEED_EXIF_WH=1
fi
if [[ "$GPS_ENABLED" == "true" ]]; then
  NEED_EXIF_GPS=1
fi

NEED_EXIF_ANY=0
if (( NEED_EXIF_TIME + NEED_EXIF_WH + NEED_EXIF_GPS > 0 )); then
  NEED_EXIF_ANY=1
fi

# ---------- exiftool 检查 ----------
if (( HAS_EXIFTOOL == 0 )); then
  if [[ "$ASPECT_ENABLED" == "true" || "$GPS_ENABLED" == "true" ]]; then
    echo "✗ 启用了比例或 GPS 筛选，但未检测到 exiftool。" >&2
    echo "  请先安装 exiftool 并确保终端里执行 'exiftool -ver' 能返回版本号：" >&2
    echo "    Linux : sudo apt install libimage-exiftool-perl" >&2
    echo "    macOS : brew install exiftool" >&2
    exit 1
  fi
  if [[ "$FT_ENABLED" != "true" || "$FT_PRIORITY" != "before_exif" ]]; then
    echo "⚠ 未检测到 exiftool，且未启用「文件名优先」。"
    echo "  拍摄时间将使用文件修改时间，经过编辑、下载、同步的图片可能不准。"
    echo "  建议：安装 exiftool，或在规则编辑器中启用「文件名时间提取」并设为「文件名优先」。"
    echo ""
  fi
fi

SRC_ABS="$(cd "$SRC" && pwd)"
DST_ABS="$(mkdir -p "$DST" && cd "$DST" && pwd)"
if [[ "$SRC_ABS" == "$DST_ABS" ]]; then
  echo "源目录与目标目录不能相同。" >&2; exit 1
fi

# ---------- 日志 ----------
log_line() {
  if (( ENABLE_LOG == 0 )); then return 0; fi
  local ts
  ts=$(date +'%Y-%m-%d %H:%M:%S')
  printf '%s | %-12s | %s -> %s\n' "$ts" "$1" "$2" "$3" >> "$LOG_FILE"
}
log_msg() {
  if (( ENABLE_LOG == 0 )); then return 0; fi
  local ts
  ts=$(date +'%Y-%m-%d %H:%M:%S')
  printf '%s | %-12s | %s\n' "$ts" "INFO" "$1" >> "$LOG_FILE"
}

if (( ENABLE_LOG == 1 )); then
  log_msg "================ 运行开始 ================"
  log_msg "源目录   : $SRC_ABS"
  log_msg "目标目录 : $DST_ABS"
  log_msg "规则文件 : $RULES"
  log_msg "模式     : $MODE"
  log_msg "保留结构 : $([[ $PRESERVE == 1 ]] && echo 是 || echo 否)"
  log_msg "覆盖     : $([[ $OVERWRITE == 1 ]] && echo 是 || echo 否)"
  log_msg "预演     : $([[ $DRY_RUN == 1 ]] && echo 是 || echo 否)"
  log_msg "文件名时间: $FT_ENABLED / $FT_MODE / $FT_PRIORITY"
  log_msg "比例筛选 : $ASPECT_ENABLED"
  log_msg "GPS 筛选 : $GPS_ENABLED"
  log_msg "需要 EXIF: TIME=$NEED_EXIF_TIME WH=$NEED_EXIF_WH GPS=$NEED_EXIF_GPS"
fi

# ---------- 加载规则 ----------
WEEKLY_LINES=()
while IFS= read -r line; do WEEKLY_LINES+=("$line"); done < <(
  jq -r '.weekly_rules[]? | "\(.days | join(","))|\(.start)|\(.end)"' "$RULES")

DATE_LINES=()
while IFS= read -r line; do DATE_LINES+=("$line"); done < <(
  jq -r '.date_rules[]? |
    "\(.start_date)|\(.end_date // .start_date)|\(.type)|\(.start_time // "")|\(.end_time // "")"' "$RULES")

ASPECT_MODE=$(jq -r '.aspect_rules.mode // "whitelist"' "$RULES")
ASPECT_TOL=$(jq -r '.aspect_rules.tolerance // 0.02' "$RULES")
ASPECT_LINES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && ASPECT_LINES+=("$line")
done < <(jq -r '.aspect_rules.ratios[]? | "\(.name)|\(.w)|\(.h)"' "$RULES")

GPS_MODE=$(jq -r '.gps_rules.mode // "whitelist"' "$RULES")
GPS_LINES=()
while IFS= read -r line; do
  [[ -n "$line" ]] && GPS_LINES+=("$line")
done < <(jq -r '.gps_rules.points[]? | "\(.name)|\(.lat)|\(.lon)|\(.radius_m)"' "$RULES")

echo "已加载规则：周规则 ${#WEEKLY_LINES[@]} 条，日期规则 ${#DATE_LINES[@]} 条，"\
"比例 ${#ASPECT_LINES[@]} 条，GPS ${#GPS_LINES[@]} 条"

# ---------- 工具函数 ----------
to_min() { local t="$1"; local h="${t%%:*}"; local m="${t##*:}"; echo $(( 10#$h * 60 + 10#$m )); }

in_range() {
  local cur="$1" s="$2" e="$3"
  if (( s <= e )); then
    if (( cur >= s && cur < e )); then return 0; else return 1; fi
  else
    if (( cur >= s || cur < e )); then return 0; else return 1; fi
  fi
}

day_of_week() {
  local d="$1" u=""
  if u=$(date -d "$d" +%u 2>/dev/null); then
    :
  elif u=$(date -j -f "%Y-%m-%d" "$d" +%u 2>/dev/null); then
    :
  else
    return 1
  fi
  printf '%s' "$(( 10#$u - 1 ))"
}

is_work_time() {
  local dt="$1"
  local d="${dt%% *}"
  local hm="${dt#* }"; hm="${hm:0:5}"
  local cur=$(( 10#${hm:0:2} * 60 + 10#${hm:3:2} ))

  local decision="" start_s end_s typ st_s et_s
  for line in "${DATE_LINES[@]}"; do
    IFS='|' read -r start_s end_s typ st_s et_s <<<"$line"
    if [[ "$d" < "$start_s" || "$d" > "$end_s" ]]; then continue; fi
    if [[ -z "$st_s" && -z "$et_s" ]]; then
      decision="$typ"
    else
      local s e
      s=$(to_min "$st_s"); e=$(to_min "$et_s")
      if in_range "$cur" "$s" "$e"; then decision="$typ"; fi
    fi
  done
  if [[ -n "$decision" ]]; then
    if [[ "$decision" == "work" ]]; then return 0; else return 1; fi
  fi

  local wd
  if ! wd=$(day_of_week "$d"); then
    return 1
  fi

  local days start end
  for line in "${WEEKLY_LINES[@]}"; do
    IFS='|' read -r days start end <<<"$line"
    if [[ ",$days," != *",$wd,"* ]]; then continue; fi
    local s e
    s=$(to_min "$start"); e=$(to_min "$end")
    if in_range "$cur" "$s" "$e"; then return 0; fi
  done
  return 1
}

haversine_m() {
  awk -v lat1="$1" -v lon1="$2" -v lat2="$3" -v lon2="$4" 'BEGIN {
    pi = 3.14159265358979
    R = 6371000
    dlat = (lat2 - lat1) * pi / 180
    dlon = (lon2 - lon1) * pi / 180
    a = sin(dlat/2)^2 + cos(lat1*pi/180) * cos(lat2*pi/180) * sin(dlon/2)^2
    c = 2 * atan2(sqrt(a), sqrt(1-a))
    print R * c
  }'
}

match_aspect() {
  local w="$1" h="$2"
  local hit="no"

  if [[ -n "$w" && -n "$h" && "$h" != "0" ]]; then
    local actual
    actual=$(awk -v w="$w" -v h="$h" 'BEGIN { print w/h }')
    local rname rw rh target
    for line in "${ASPECT_LINES[@]}"; do
      IFS='|' read -r rname rw rh <<<"$line"
      target=$(awk -v w="$rw" -v h="$rh" 'BEGIN { print w/h }')
      if awk -v a="$actual" -v t="$target" -v tol="$ASPECT_TOL" 'BEGIN {
        d = (a > t) ? (a - t) : (t - a)
        exit (d / t <= tol) ? 0 : 1
      }'; then
        hit="yes"
        break
      fi
    done
  fi

  if [[ "$ASPECT_MODE" == "whitelist" ]]; then
    if [[ "$hit" == "yes" ]]; then return 0; else return 1; fi
  else
    if [[ "$hit" == "yes" ]]; then return 1; else return 0; fi
  fi
}

match_gps() {
  local lat="$1" lon="$2"
  local hit="no"

  if [[ -n "$lat" && -n "$lon" ]]; then
    local pname plat plon prad dist
    for line in "${GPS_LINES[@]}"; do
      IFS='|' read -r pname plat plon prad <<<"$line"
      dist=$(haversine_m "$lat" "$lon" "$plat" "$plon")
      if awk -v d="$dist" -v r="$prad" 'BEGIN { exit (d <= r) ? 0 : 1 }'; then
        hit="yes"
        break
      fi
    done
  fi

  if [[ "$GPS_MODE" == "whitelist" ]]; then
    if [[ "$hit" == "yes" ]]; then return 0; else return 1; fi
  else
    if [[ "$hit" == "yes" ]]; then return 1; else return 0; fi
  fi
}

# ---------- 文件名时间提取 ----------

template_to_regex_and_order() {
  local tpl="$1"
  local regex="" order=""
  local i=0 n=${#tpl}
  while (( i < n )); do
    local c="${tpl:i:1}"
    if [[ "$c" == "%" ]] && (( i+1 < n )); then
      local nxt="${tpl:i+1:1}"
      case "$nxt" in
        Y) regex+='([0-9]{4})'; order+="Y" ;;
        m) regex+='([0-9]{2})'; order+="m" ;;
        d) regex+='([0-9]{2})'; order+="d" ;;
        H) regex+='([0-9]{2})'; order+="H" ;;
        M) regex+='([0-9]{2})'; order+="M" ;;
        S) regex+='([0-9]{2})'; order+="S" ;;
        *) regex+='%' ;;
      esac
      i=$((i+2))
    elif [[ "$c" == "*" ]]; then
      regex+='.*'
      i=$((i+1))
    else
      case "$c" in
        '.'|'+'|'('|')'|'['|']'|'{'|'}'|'^'|'$'|'|'|'?'|'\')
          regex+="\\$c" ;;
        *) regex+="$c" ;;
      esac
      i=$((i+1))
    fi
  done
  printf '%s|%s' "$regex" "$order"
}

extract_from_filename_template() {
  local base="$1" tpl="$2"
  local rgx_order rgx order
  rgx_order="$(template_to_regex_and_order "$tpl")"
  rgx="${rgx_order%|*}"
  order="${rgx_order#*|}"

  if [[ "$base" =~ $rgx ]]; then
    local y="" mo="01" d="01" h="00" mi="00" s="00"
    local idx=1 i fld val
    for (( i=0; i<${#order}; i++ )); do
      fld="${order:i:1}"
      val="${BASH_REMATCH[$idx]}"
      case "$fld" in
        Y) y="$val" ;;
        m) mo="$val" ;;
        d) d="$val" ;;
        H) h="$val" ;;
        M) mi="$val" ;;
        S) s="$val" ;;
      esac
      idx=$((idx+1))
    done
    [[ -z "$y" ]] && return 1
    printf '%04d-%02d-%02d %02d:%02d:%02d' \
      "$((10#$y))" "$((10#$mo))" "$((10#$d))" \
      "$((10#$h))" "$((10#$mi))" "$((10#$s))"
    return 0
  fi
  return 1
}

extract_from_filename_auto() {
  local base="$1"

  if [[ "$base" =~ (20[0-9]{2})[-_\.]?([01][0-9])[-_\.]?([0-3][0-9])[T\ _-]?([0-2][0-9])[-_:\.]?([0-5][0-9])[-_:\.]?([0-5][0-9]) ]]; then
    printf '%s-%s-%s %s:%s:%s' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}" \
      "${BASH_REMATCH[4]}" "${BASH_REMATCH[5]}" "${BASH_REMATCH[6]}"
    return 0
  fi

  if [[ "$base" =~ (20[0-9]{2})[-_\.]?([01][0-9])[-_\.]?([0-3][0-9]) ]]; then
    printf '%s-%s-%s 00:00:00' \
      "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "${BASH_REMATCH[3]}"
    return 0
  fi

  if [[ "$base" =~ (1[0-9]{12}) ]]; then
    local ms="${BASH_REMATCH[1]}"
    local sec=$(( ms / 1000 ))
    local dt=""
    if dt=$(date -d "@$sec" +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
      printf '%s' "$dt"; return 0
    elif dt=$(date -r "$sec" +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
      printf '%s' "$dt"; return 0
    fi
  fi

  if [[ "$base" =~ (1[0-9]{9}) ]]; then
    local sec="${BASH_REMATCH[1]}"
    local dt=""
    if dt=$(date -d "@$sec" +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
      printf '%s' "$dt"; return 0
    elif dt=$(date -r "$sec" +"%Y-%m-%d %H:%M:%S" 2>/dev/null); then
      printf '%s' "$dt"; return 0
    fi
  fi

  return 1
}

extract_datetime_from_filename() {
  local f="$1"
  local base
  base="$(basename "$f")"
  if [[ "$FT_MODE" == "template" && -n "$FT_TEMPLATE" ]]; then
    extract_from_filename_template "$base" "$FT_TEMPLATE"
  else
    extract_from_filename_auto "$base"
  fi
}

# ---------- 扫描 ----------
EXT_REGEX='\.(jpg|jpeg|png|heic|heif|webp|bmp|gif|tif|tiff|cr2|cr3|nef|arw|dng|raf|orf|rw2|pef|srw)$'

echo "扫描目录: $SRC_ABS"
mapfile -d '' FILES < <(find "$SRC_ABS" -type d -path "$DST_ABS" -prune -o \
                        -type f -regextype posix-extended -iregex ".*${EXT_REGEX}" -print0)
echo "找到 ${#FILES[@]} 张图片"
if (( ${#FILES[@]} == 0 )); then
  echo "没有找到图片。"
  log_msg "没有找到图片。"
  exit 0
fi

total=${#FILES[@]}

# ---------- 按需读取元数据（exiftool -@ 单次调用） ----------
declare -A IMG_DT IMG_W IMG_H IMG_LAT IMG_LON

if (( NEED_EXIF_ANY == 1 )); then
  echo "读取图片元数据（exiftool -@ 单次调用）..."

  EXIF_TAGS=()
  (( NEED_EXIF_TIME == 1 )) && EXIF_TAGS+=(-DateTimeOriginal -CreateDate)
  (( NEED_EXIF_WH == 1 ))   && EXIF_TAGS+=(-ImageWidth -ImageHeight -Orientation)
  (( NEED_EXIF_GPS == 1 ))  && EXIF_TAGS+=(-GPSLatitude -GPSLongitude)

  # 把文件列表以 \0 分隔写入临时文件，再转成 \n 分隔喂给 exiftool -@ -
  # 文件名含换行符的场景极少见，这里不做特殊处理
  FILELIST="$(mktemp)"
  trap 'rm -f "$FILELIST"' EXIT
  printf '%s\0' "${FILES[@]}" | tr '\0' '\n' > "$FILELIST"

  while IFS=$'\t' read -r src dt w h lat lon; do
    [[ -z "$src" ]] && continue
    if (( NEED_EXIF_TIME == 1 )); then
      IMG_DT["$src"]="$dt"
    fi
    if (( NEED_EXIF_WH == 1 )); then
      IMG_W["$src"]="$w"
      IMG_H["$src"]="$h"
    fi
    if (( NEED_EXIF_GPS == 1 )); then
      IMG_LAT["$src"]="$lat"
      IMG_LON["$src"]="$lon"
    fi
  done < <(
    exiftool -j -q -q -m -n \
      "${EXIF_TAGS[@]}" \
      -@ "$FILELIST" 2>/dev/null | \
    jq -r '
      .[] |
      . as $item |
      ($item.DateTimeOriginal // $item.CreateDate // "") as $rawdt |
      # 归一化时间：YYYY:MM:DD HH:MM:SS -> YYYY-MM-DD HH:MM:SS
      ($rawdt
        | if test("^[0-9]{4}:[0-9]{2}:[0-9]{2} ")
          then (.[0:4] + "-" + .[5:7] + "-" + .[8:10] + .[10:19])
          else (.[0:19])
          end
      ) as $dt |
      ($item.ImageWidth // "") as $w0 |
      ($item.ImageHeight // "") as $h0 |
      ($item.Orientation // 1) as $orient |
      # Orientation=6 或 8 时交换宽高
      (if ($orient == 6 or $orient == 8) then $h0 else $w0 end) as $w |
      (if ($orient == 6 or $orient == 8) then $w0 else $h0 end) as $h |
      ($item.GPSLatitude // "" | tostring) as $lat |
      ($item.GPSLongitude // "" | tostring) as $lon |
      [
        $item.SourceFile,
        $dt,
        ($w | tostring),
        ($h | tostring),
        $lat,
        $lon
      ] | @tsv
    '
  )

  printf "  元数据读取完成\n"
else
  echo "无需读取 EXIF（文件名优先且未启用比例/GPS 筛选）"
fi

# ---------- 时间取值 ----------
get_datetime() {
  local f="$1"
  local dt="" fname_dt=""

  if [[ "$FT_ENABLED" == "true" && "$FT_PRIORITY" == "before_exif" ]]; then
    if fname_dt=$(extract_datetime_from_filename "$f"); then
      if [[ -n "$fname_dt" ]]; then
        printf '%s' "$fname_dt"
        return
      fi
    fi
  fi

  dt="${IMG_DT[$f]:-}"
  if [[ -n "$dt" ]]; then
    printf '%s' "$dt"
    return
  fi

  if [[ "$FT_ENABLED" == "true" && "$FT_PRIORITY" == "after_exif" ]]; then
    if fname_dt=$(extract_datetime_from_filename "$f"); then
      if [[ -n "$fname_dt" ]]; then
        printf '%s' "$fname_dt"
        return
      fi
    fi
  fi

  dt=$(date -r "$f" +"%Y-%m-%d %H:%M:%S" 2>/dev/null || \
       stat -c '%y' "$f" 2>/dev/null | cut -d'.' -f1)
  printf '%s' "$dt"
}

unique_target() {
  local t="$1"
  if [[ ! -e "$t" ]]; then printf '%s' "$t"; return; fi
  local dir base ext stem i
  dir="$(dirname "$t")"; base="$(basename "$t")"
  ext=""; stem="$base"
  if [[ "$base" == *.* ]]; then stem="${base%.*}"; ext=".${base##*.}"; fi
  i=1
  while :; do
    local cand="$dir/${stem}_$i$ext"
    if [[ ! -e "$cand" ]]; then printf '%s' "$cand"; return; fi
    i=$((i+1))
  done
}

# ---------- 主循环 ----------
n_work=0; n_off=0; n_skip=0; n_fail=0
n_aspect=0; n_gps=0
idx=0

for f in "${FILES[@]}"; do
  idx=$((idx+1))

  dt="$(get_datetime "$f")"
  if [[ -z "$dt" ]]; then
    n_fail=$((n_fail+1))
    log_line "FAIL" "$f" "(无法读取时间)"
    continue
  fi

  if is_work_time "$dt"; then
    n_work=$((n_work+1))
    continue
  fi

  if [[ "$ASPECT_ENABLED" == "true" ]]; then
    if ! match_aspect "${IMG_W[$f]:-}" "${IMG_H[$f]:-}"; then
      n_aspect=$((n_aspect+1))
      log_line "SKIP-ASPECT" "$f" "(${IMG_W[$f]:-?}x${IMG_H[$f]:-?})"
      continue
    fi
  fi

  if [[ "$GPS_ENABLED" == "true" ]]; then
    if ! match_gps "${IMG_LAT[$f]:-}" "${IMG_LON[$f]:-}"; then
      n_gps=$((n_gps+1))
      log_line "SKIP-GPS" "$f" "(${IMG_LAT[$f]:-?},${IMG_LON[$f]:-?})"
      continue
    fi
  fi

  n_off=$((n_off+1))

  rel="${f#$SRC_ABS/}"
  if (( PRESERVE == 1 )); then
    target="$DST_ABS/$rel"
  else
    target="$DST_ABS/$(basename "$f")"
  fi

  if [[ -e "$target" ]]; then
    if (( OVERWRITE == 1 )); then
      rm -f -- "$target"
      log_line "OVERWRITE" "$f" "$target"
    elif (( PRESERVE == 1 )); then
      n_skip=$((n_skip+1))
      log_line "SKIP-EXISTS" "$f" "$target"
      continue
    else
      target="$(unique_target "$target")"
    fi
  fi

  if (( DRY_RUN == 1 )); then
    echo "[DRY] $dt  $f"
    log_line "DRY-$MODE" "$f" "$target"
    continue
  fi

  mkdir -p -- "$(dirname "$target")"

  case "$MODE" in
    copy)
      cp -p -- "$f" "$target"
      log_line "COPY" "$f" "$target"
      ;;
    move)
      mv -- "$f" "$target"
      log_line "MOVE" "$f" "$target"
      ;;
    hardlink)
      if ln -- "$f" "$target" 2>/dev/null; then
        log_line "HARDLINK" "$f" "$target"
      else
        cp -p -- "$f" "$target"
        log_line "COPY(fallback)" "$f" "$target"
      fi
      ;;
    symlink)
      if ln -s -- "$f" "$target" 2>/dev/null; then
        log_line "SYMLINK" "$f" "$target"
      else
        cp -p -- "$f" "$target"
        log_line "COPY(fallback)" "$f" "$target"
      fi
      ;;
    *)
      echo "未知模式: $MODE" >&2; exit 1
      ;;
  esac

  if (( idx % 100 == 0 )); then
    echo "进度 $idx/$total"
  fi
done

# ---------- 汇总 ----------
echo "=============================================="
echo "图片总数        : $total"
echo "工作时间（排除）: $n_work"
echo "比例不符（跳过）: $n_aspect"
echo "位置不符（跳过）: $n_gps"
echo "非工作时间（输出）: $n_off"
echo "已存在跳过      : $n_skip"
echo "失败            : $n_fail"
echo "输出目录        : $DST_ABS"

if (( ENABLE_LOG == 1 )); then
  log_msg "图片总数        : $total"
  log_msg "工作时间（排除）: $n_work"
  log_msg "比例不符（跳过）: $n_aspect"
  log_msg "位置不符（跳过）: $n_gps"
  log_msg "非工作时间（输出）: $n_off"
  log_msg "已存在跳过      : $n_skip"
  log_msg "失败            : $n_fail"
  log_msg "输出目录        : $DST_ABS"
  log_msg "================ 运行结束 ================"
fi