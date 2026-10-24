param(
  [string[]]$EvidenceDirs = @((Join-Path $PSScriptRoot '..\docs\evidence\2026-09-27-jobwarp'), (Join-Path $PSScriptRoot '..\docs\evidence\2026-09-28-jobwarp-outdoor'), (Join-Path $PSScriptRoot '..\docs\evidence\2026-10-24-ceo-menu-lower')),
  [string]$TemplateDir = (Join-Path $PSScriptRoot '..\Images\JobWarp\1920x1080'),
  [string[]]$Exclude = @(),   # 이 원본들은 템플릿을 뜰 때 빼고 시험에만 쓴다 (빼 둔 원본에서도 찾히는지 보는 교차 시험용)
  [switch]$TestOnly,
  [switch]$GainSim            # 폰 원본을 밝기 g 배로 줄인 모의 원본에도 폰 템플릿을 대 본다
)
# F11 퀵 조인 준비(Features\Teleport\QuickJoinPrep.ahk)가 쓰는 템플릿을 실측 스크린샷에서 떠서 Images\JobWarp\1920x1080\ 에 만들고,
# 코드와 같은 영역·옵션(*N *Trans0xFF00FF, N 은 템플릿마다 아래 $variation)으로 모든 원본에 대 보아 맞는 상태에서만 찾히는지 표로 확인한다.
# 게임에는 아무 키도 보내지 않는다.
#
# 원본: <상태>.png 는 코드가 찾는 영역을 그대로 잘라 둔 무손실 조각, <상태>.jpg 는 같은 순간의 전체 화면이다.
#   m-*, after-*, *-menu : 상호작용 메뉴 영역 JW_MENU_AREA [0,0,0.27,0.55] = 화면 (0,0) 518x594
#   ph-*, qj-*, phone-*, *-phone : 폰 영역 JW_PHONE_AREA [0.6,0.3,1,1] = 화면 (1152,324) 768x756
#   docs\evidence\2026-09-27-jobwarp : 저택 안(0927 22:51~23:15). run-*.jpg·macro-log.txt 는 그때 F11 실제 시험 기록
#   docs\evidence\2026-09-28-jobwarp-outdoor : 실외(Vinewood, Bishop's WTF?! 앞 길가, 0928 14:40~14:57). 이름 끝 --night1 은 게임 시각 새벽 5시 전
#     밤(네온 켜짐), --dawn1 은 05:20~06:30 동틀 녘, --day1 은 09:30~10:20 흐린 낮(비). 카메라는 옮기지 않았다.
#
# 0928 실외 실측으로 알게 된 것 (그래서 한 장에서 잘라 쓰던 방식을 여러 장을 겹쳐 뜨는 방식으로 바꿨다)
#   1) 메뉴 줄 간격은 37.5px 라 짝수 번째 줄은 반 픽셀 아래에 그려져 글자 가장자리 값이 전부 달라진다. 저택 안의 Register as a Boss 는
#      3번째 줄(Mansion Management·Quick GPS 다음), 실외에서는 2번째 줄이라 옛 m_boss·m_boss_sel 이 실외에서 전혀 안 맞았다(최소 N 168·143).
#      폰 목록도 줄 간격이 48.5px 라 Alone 이 1번째 줄(같은 세션에 친구가 없을 때 Random 안에 Alone 한 줄뿐)이면 반 픽셀 어긋난다.
#   2) 메뉴 제목 줄(INTERACTION MENU 등)은 완전히 불투명하다(실외 낮·밤 모두 차이 0). 선택 줄 바탕은 약 85% 불투명(바탕 = 0.15 x 뒤 배경 + 192),
#      선택 안 된 줄 바탕은 약 60% 불투명한 검정(바탕 = 0.35~0.41 x 뒤 배경)이라 뒤가 밝으면 0 에서 약 105 까지 올라간다.
#   3) 폰 화면은 3D 로 그려져 밝기가 장면에 따라 통째로 곱해진다(저택 안 1.0, 동틀 녘 약 0.87, 흐린 낮 약 0.93).
#
# 1024: MCT 앞에서 메뉴가 원본보다 10px 아래 그려져 선택 줄 글자 윗변이 반 픽셀 어긋났다(m_securo_sel 차이 100, CEO 해제가 SecuroServ·Retire 줄을 못 찾음).
#       옛 원본만으로 flat = 1 로 뜬 m_securo_sel 은 그 실측에서 16 이라, CEO 등록·해제의 선택 줄 템플릿(m_securo_sel·m_retire_sel·m_ceo_sel·m_start_org_sel)에 flat 을 켰다.
# 뜨는 방식(한 템플릿에 양성 원본 여러 장을 같은 자리로 맞춰 겹친다)
#   range   : 칸마다 원본들의 채널별 최솟값·최댓값을 보고, 폭(최대-최소)이 2 x $rangeHalf 이하인 칸만 남겨 그 가운데 값을 적는다.
#             원본마다 달라지는 칸(반 픽셀 어긋난 글자 가장자리, 뒤 배경이 비치는 칸)은 FF00FF(투명)가 된다.
#             남은 칸은 관측한 모든 원본에서 가운데 값 +-$rangeHalf 안이라 *40 이면 원본에 없던 밝기·배경에도 20 이상 여유가 남는다.
#             선택: coreFromRow = N 이면 N 번째 행부터(선택 안 된 반투명 줄)는 흰 글자 속(최소 채널 >= 230)만 남긴다. 반투명 바탕은 원본 몇 장이
#                   우연히 비슷해도 더 밝은 하늘에서는 벗어나므로(원본을 빼고 뜬 교차 시험에서 m_securo 가 낮 원본에 43) 아예 쓰지 않는다.
#                   flat = 1 이면 어느 원본에서든 주변 3x3 의 밝기 폭이 $flatMax 를 넘는 칸(글자 가장자리)을 뺀다. 반 픽셀 어긋난 줄을 섞어 뜨는
#                   템플릿(m_boss_sel, qj_alone_sel)은 원본 두세 장에서 우연히 맞은 가장자리 칸이 다른 밝기에서 틀려서(교차 시험 41) 쓴다.
#   coregap : 선택 안 된(반투명) 줄 전용. 모든 원본에서 흰 글자 속(최소 채널 >= 230)인 칸은 가운데 값으로, 모든 원본에서 주변 3x3 이
#             어두운 줄 바탕(<= 110)인 칸은 회색 $gapValue(55) 로 적고 나머지는 투명. 허용 오차 70($variation)으로 찾으면 글자 속은 약 180 이상,
#             바탕 칸은 0~125 를 받아 뒤가 하얀 하늘이어도(바탕 약 105) 맞고, 선택 줄의 밝은 바탕(192 이상)이나 흰 글자는 바탕 칸에서 떨어진다.
#             바탕 칸이 없으면 글자 속만 남아 밝은 선택 줄의 빈 자리에서도 찾혀 버리므로(CEO 상태를 해제 상태로 잘못 읽는다) 꼭 둔다.
#             *40 으로는 0~105 를 한 값으로 덮을 수 없어 이 템플릿만 70 을 쓴다(QuickJoinPrep.ahk 의 JW_VARIATION).
# 샘플 좌표는 전체 화면 좌표(x, y)이고, 두 번째 원본부터는 첫 원본에 +-3px 안에서 가장 잘 맞는 자리로 옮겨 겹친다(반 픽셀 어긋난 줄은 둘 중 한쪽).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$EvidenceDirs = @($EvidenceDirs | ForEach-Object { (Resolve-Path $_).Path })
New-Item -ItemType Directory -Force -Path $TemplateDir | Out-Null
$TemplateDir = (Resolve-Path $TemplateDir).Path
$earnTitle = Join-Path $PSScriptRoot '..\Images\Earn\1920x1080\m_title.png'   # 수익 자동화와 같이 쓰는 메뉴 제목(불투명이라 실외에서도 그대로 맞는다)
$rangeHalf = 20
$gapValue = 55
$flatMax = 90
# 폰 템플릿은 값을 $dimGain 배로 낮춘 대체(_dim)를 하나 더 둔다(QuickJoinPrep.ahk 의 JW_ALT). 코드는 둘 중 하나가 보이면 찾은 것으로 친다.
# 폰 화면 밝기는 실측 0.87~1.0 이었고, 여러 장을 겹쳐 뜬 템플릿 한 장은 선형 밝기 모의(원본 x g)로 약 0.83 까지 *40 안이다.
# 대체는 약 0.65~0.88 을 덮어, 맑은 한낮처럼 아직 못 찍은 더 어두운 폰에도 멈추지 않게 한다(-GainSim 으로 확인. 실측 아닌 모의라는 점에 주의).
$dimGain = 0.82
$dim = @{ 'ph_quickjoin_sel' = 'ph_quickjoin_sel_dim'; 'qj_random_sel' = 'qj_random_sel_dim'; 'qj_alone_sel' = 'qj_alone_sel_dim'; 'qj_yes_sel' = 'qj_yes_sel_dim' }
# 템플릿마다 ImageSearch 허용 오차. QuickJoinPrep.ahk 의 JW_VARIATION 과 같아야 한다 (없는 이름은 40)
$variation = @{ 'm_boss' = 70 }

$menuArea = @(0, 0, 518, 594)
$phoneArea = @(1152, 324, 768, 756)
function Get-Area([string]$state) {
  if ($state -match '^(ph-|qj-|phone-)' -or $state -like '*-phone') { return $phoneArea }
  return $menuArea
}
function Find-Source([string]$state) {
  foreach ($d in $EvidenceDirs) { $p = Join-Path $d "$state.png"; if (Test-Path $p) { return $p } }
  throw "원본 없음: $state"
}

Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System; using System.Drawing; using System.Drawing.Imaging; using System.Runtime.InteropServices; using System.Collections.Generic; using System.Threading.Tasks;
public static class JWT {
  public static int[] Load(string path, out int w, out int h) {
    using (var src = new Bitmap(path)) {
      w = src.Width; h = src.Height;
      var data = src.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
      var px = new int[w * h];
      for (int y = 0; y < h; y++) Marshal.Copy(data.Scan0 + y * data.Stride, px, y * w, w);
      src.UnlockBits(data);
      return px;
    }
  }
  public static void Save(int[] px, int w, int h, string path) {
    using (var b = new Bitmap(w, h, PixelFormat.Format24bppRgb)) {
      for (int y = 0; y < h; y++) for (int x = 0; x < w; x++) b.SetPixel(x, y, Color.FromArgb(px[y * w + x] & 0xFFFFFF | unchecked((int)0xFF000000)));
      b.Save(path, ImageFormat.Png);
    }
  }
  static int C(int p, int sh) { return (p >> sh) & 255; }
  // 두 번째 원본부터 첫 원본에 +-r 안에서 가장 잘 맞는(절댓값 차 합이 가장 작은) 자리
  public static void Align(int[] a, int aw, int ax, int ay, int[] b, int bw, int bh, int bx0, int by0, int w, int h, int r, out int bx, out int by) {
    long best = long.MaxValue; bx = bx0; by = by0;
    for (int dy = -r; dy <= r; dy++) for (int dx = -r; dx <= r; dx++) {
      int x = bx0 + dx, y = by0 + dy;
      if (x < 0 || y < 0 || x + w > bw || y + h > bh) continue;
      long s = 0;
      for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) {
        int p = a[(ay + j) * aw + ax + i], q = b[(y + j) * bw + x + i];
        s += Math.Abs(C(p, 16) - C(q, 16)) + Math.Abs(C(p, 8) - C(q, 8)) + Math.Abs(C(p, 0) - C(q, 0));
      }
      if (s < best) { best = s; bx = x; by = y; }
    }
  }
  static int Pack(int r, int g, int b) { int v = (r << 16) | (g << 8) | b; return v == 0xFF00FF ? 0xFE00FE : v; }
  // 밝기를 g 배로 (tpl 이면 투명 칸은 그대로 둔다)
  public static int[] Scale(int[] px, double g, bool tpl) {
    var r = new int[px.Length];
    for (int i = 0; i < px.Length; i++) {
      int p = px[i] & 0xFFFFFF;
      if (tpl && p == 0xFF00FF) { r[i] = p; continue; }
      int a = Math.Min(255, (int)Math.Round(C(p, 16) * g)), b = Math.Min(255, (int)Math.Round(C(p, 8) * g)), c = Math.Min(255, (int)Math.Round(C(p, 0) * g));
      r[i] = tpl ? Pack(a, b, c) : (a << 16) | (b << 8) | c;
    }
    return r;
  }
  public static int[] ScaleTpl(int[] px, double g) { return Scale(px, g, true); }
  // mode 0 = range, 1 = coregap. 샘플 k 는 hay[k] 의 (xs[k], ys[k]) 에서 w x h
  public static int[] Build(int mode, int[][] hay, int[] hw, int[] xs, int[] ys, int w, int h, int half, int coreMin, int gapMax, int gapValue, int coreFromRow, int flatMax, out int kept, out int core, out int gap) {
    var t = new int[w * h]; kept = 0; core = 0; gap = 0;
    for (int j = 0; j < h; j++) for (int i = 0; i < w; i++) {
      int[] mn = { 255, 255, 255 }, mx = { 0, 0, 0 }; int minCh = 255; bool dark = true, flat = true;
      for (int k = 0; k < hay.Length; k++) {
        int p = hay[k][(ys[k] + j) * hw[k] + xs[k] + i];
        for (int c = 0; c < 3; c++) { int v = C(p, 16 - 8 * c); if (v < mn[c]) mn[c] = v; if (v > mx[c]) mx[c] = v; if (v < minCh) minCh = v; }
        int[] ln = { 255, 255, 255 }, lx = { 0, 0, 0 };
        for (int dj = -1; dj <= 1; dj++) for (int di = -1; di <= 1; di++) {
          int y = ys[k] + j + dj, x = xs[k] + i + di, hk = hay[k].Length / hw[k];
          if (y < 0 || x < 0 || y >= hk || x >= hw[k]) continue;
          int q = hay[k][y * hw[k] + x];
          if (C(q, 16) > gapMax || C(q, 8) > gapMax || C(q, 0) > gapMax) dark = false;
          for (int c = 0; c < 3; c++) { int v = C(q, 16 - 8 * c); if (v < ln[c]) ln[c] = v; if (v > lx[c]) lx[c] = v; }
        }
        for (int c = 0; c < 3; c++) if (lx[c] - ln[c] > flatMax) flat = false;
      }
      int val = 0xFF00FF;
      if (mode == 0) {
        bool inRange = mx[0] - mn[0] <= 2 * half && mx[1] - mn[1] <= 2 * half && mx[2] - mn[2] <= 2 * half;
        bool ok = j >= coreFromRow ? (minCh >= coreMin && inRange) : (inRange && (flatMax >= 256 || flat));
        if (ok) { val = Pack((mn[0] + mx[0] + 1) / 2, (mn[1] + mx[1] + 1) / 2, (mn[2] + mx[2] + 1) / 2); if (j >= coreFromRow) core++; }
      } else {
        if (minCh >= coreMin) { val = Pack((mn[0] + mx[0] + 1) / 2, (mn[1] + mx[1] + 1) / 2, (mn[2] + mx[2] + 1) / 2); core++; }
        else if (dark) { val = Pack(gapValue, gapValue, gapValue); gap++; }
      }
      t[j * w + i] = val; if (val != 0xFF00FF) kept++;
    }
    return t;
  }
  // ImageSearch *n *TransFF00FF 규칙(투명 칸은 건너뛰고 나머지는 R·G·B 가 각각 +-n 안)으로 찾히는 가장 작은 n. 자리마다 칸 차이의 최댓값을 재고 그 최솟값
  public static int MinVar(int[] hay, int hw, int hh, int[] nd, int nw, int nh, out int bx, out int by) {
    var idx = new List<int>(); var off = new List<int>();
    for (int j = 0; j < nh; j++) for (int i = 0; i < nw; i++) if ((nd[j * nw + i] & 0xFFFFFF) != 0xFF00FF) { idx.Add(j * nw + i); off.Add(j * hw + i); }
    int[] ix = idx.ToArray(), of = off.ToArray();
    int best = 256; bx = -1; by = -1;
    for (int y = 0; y + nh <= hh; y++)
      for (int x = 0; x + nw <= hw; x++) {
        int b = y * hw + x, m = 0;
        for (int k = 0; k < ix.Length; k++) {
          int s = hay[b + of[k]], n = nd[ix[k]];
          int d = Math.Max(Math.Abs(C(s, 16) - C(n, 16)), Math.Max(Math.Abs(C(s, 8) - C(n, 8)), Math.Abs(C(s, 0) - C(n, 0))));
          if (d > m) { m = d; if (m >= best) break; }
        }
        if (m < best) { best = m; bx = x; by = y; if (best == 0) return 0; }
      }
    return best;
  }
  public static int[] MinVarAll(int[][] hay, int[] hw, int[] hh, int[][] nd, int[] nw, int[] nh, int[] pa, int[] pb, int[] ox, int[] oy) {
    var r = new int[pa.Length];
    Parallel.For(0, pa.Length, k => { int bx, by; r[k] = MinVar(hay[pa[k]], hw[pa[k]], hh[pa[k]], nd[pb[k]], nw[pb[k]], nh[pb[k]], out bx, out by); ox[k] = bx; oy[k] = by; });
    return r;
  }
}
'@

# 이름, 방식, 가로, 세로, 양성 원본 목록(상태 이름, 전체 화면 x, y). 첫 원본이 기준 자리다.
$night = '--night1'; $day = '--day1'; $dawn = '--dawn1'
$items = @(
  @('m_boss', 'coregap', 184, 27, @(   # 선택 안 된 Register as a Boss. 저택 안 3번째 줄, 실외 2번째 줄(반 픽셀 어긋남)
      @('m-main-free', 38, 233), @('m-main-free-quickgps-sel', 38, 233), @('m-main-free-after-retire', 38, 233), @('m-main-free-final', 38, 233),
      @("m-main-free-quickgps-sel$night", 38, 196), @("m-main-free-after-retire$night", 38, 196),
      @("m-main-free-quickgps-sel$day", 38, 196), @("m-main-free-after-retire$day", 38, 196))),
  @('m_boss_sel', 'range', 184, 27, @(
      @('m-main-free-boss-sel', 38, 233), @("m-main-free-boss-sel$night", 38, 196), @("m-main-free-boss-sel$day", 38, 196)), @{ flat = 1 }),
  # 제목 REGISTER AS A BOSS + 선택된 SecuroServ CEO. "SecuroServ CEO" 선택 줄은 보스 메인 메뉴 맨 위와 글자·자리가 같아 제목 줄까지 같이 뜬다
  @('m_ceo_sel', 'range', 214, 58, @(@('m-register-boss-ceo-sel', 37, 123), @("m-register-boss-ceo-sel$night", 37, 123), @("m-register-boss-ceo-sel$day", 37, 123)), @{ flat = 1 }),
  @('m_start_org_sel', 'range', 208, 27, @(@('m-securoserv-start-org-sel', 38, 158), @("m-securoserv-start-org-sel$night", 38, 158), @("m-securoserv-start-org-sel$day", 38, 158)), @{ flat = 1 }),
  # 제목 INTERACTION MENU + SecuroServ CEO(맨 위 줄). 선택·비선택 모두 제목 줄은 불투명이라 그대로 남는다
  @('m_securo_sel', 'range', 214, 58, @(@('m-main-ceo-securo-sel', 37, 123), @('m-main-ceo-securo-sel-2', 37, 123), @("m-main-ceo-securo-sel$night", 37, 123), @("m-main-ceo-securo-sel$day", 37, 123),
      @('m-main-ceo-securo-sel--lower1', 37, 133)), @{ flat = 1 }),   # 1024 MCT 앞: 메뉴가 10px 아래(37,133)에 그려져 글자 윗변이 반 픽셀 어긋났다(85 에서 10칸 초과)
  @('m_securo', 'range', 214, 58, @(@('m-main-ceo-securo', 37, 123), @("m-main-ceo-securo$night", 37, 123), @("m-main-ceo-securo$day", 37, 123)), @{ coreFromRow = 29 }),   # 위 29행은 불투명 제목 줄, 그 아래 선택 안 된 줄은 흰 글자 속만
  @('m_retire_sel', 'range', 80, 22, @(@('m-ceo-menu-retire-sel', 38, 383), @("m-ceo-menu-retire-sel$night", 38, 383), @("m-ceo-menu-retire-sel$day", 38, 383)), @{ flat = 1 }),   # SECUROSERV CEO 하위 메뉴 맨 아래(7번째) 줄
  @('m_sub_boss', 'range', 214, 21, @(@('m-register-boss-ceo-sel', 37, 123), @("m-register-boss-ceo-sel$night", 37, 123), @("m-register-boss-ceo-sel$day", 37, 123))),   # 하위 메뉴 제목 REGISTER AS A BOSS
  # 하위 메뉴 제목 SECUROSERV. SECUROSERV CEO(보스 메뉴 하위) 도 앞 글자가 같아 함께 잡는다
  @('m_sub_securo', 'range', 140, 21, @(@('m-securoserv-start-org-sel', 37, 123), @('m-ceo-menu-hire-sel', 37, 123), @("m-securoserv-start-org-sel$night", 37, 123), @("m-ceo-menu-hire-sel$day", 37, 123))),
  # 폰 홈 2쪽 첫 칸 Quick Join, 골라지면 아이콘이 커지고 테두리가 빛난다
  @('ph_quickjoin_sel', 'range', 60, 60, @(@('ph-home2-quickjoin-sel', 1636, 783), @('ph-home2-quickjoin-sel-from-row3', 1636, 783), @('ph-home2-quickjoin-sel-after-back', 1636, 783),
      @("ph-home2-quickjoin-sel$dawn", 1636, 783), @("ph-home2-quickjoin-sel-after-back$dawn", 1636, 783), @("ph-home2-quickjoin-sel$day", 1636, 783), @("ph-home2-quickjoin-sel-after-back$day", 1636, 783))),
  @('qj_random_sel', 'range', 78, 30, @(@('qj-list-random-sel', 1618, 966), @("qj-list-random-sel$dawn", 1618, 966), @("qj-list-random-sel$day", 1618, 966))),   # Quick Join 목록 맨 아래 줄
  # Random 안의 Alone. 저택 안은 Friends in Session 다음 2번째 줄, 실외(세션에 친구 없음)는 Alone 한 줄뿐이라 1번째 줄(반 픽셀 어긋남)
  @('qj_alone_sel', 'range', 56, 30, @(@('qj-random-alone-sel', 1618, 820), @("qj-random-alone-only-sel$dawn", 1618, 772), @("qj-random-alone-only-sel$day", 1618, 772)), @{ flat = 1 }),
  @('qj_yes_sel', 'range', 162, 34, @(@('qj-yes-sel', 1618, 772), @("qj-yes-sel$dawn", 1618, 772), @("qj-yes-sel$day", 1618, 772)))   # 폰 안의 확인 줄 "Are you sure?"
)

$cache = @{}
function Get-Px([string]$state) {
  if (-not $cache.ContainsKey($state)) { $w = 0; $h = 0; $px = [JWT]::Load((Find-Source $state), [ref]$w, [ref]$h); $cache[$state] = @{ px = $px; w = $w; h = $h } }
  return $cache[$state]
}

if (-not $TestOnly) {
  foreach ($item in $items) {
    $name = $item[0]; $mode = if ($item[1] -eq 'coregap') { 1 } else { 0 }; $w = [int]$item[2]; $h = [int]$item[3]
    $opt = if ($item.Count -gt 5) { $item[5] } else { @{} }
    $coreFromRow = if ($opt.ContainsKey('coreFromRow')) { [int]$opt.coreFromRow } else { $h }
    $flat = if ($opt.ContainsKey('flat')) { $flatMax } else { 256 }
    $samples = @($item[4] | Where-Object { $_[0] -notin $Exclude })
    if ($samples.Count -lt 1) { throw "$name : 뜰 원본이 없음" }
    $hays = @(); $hws = @(); $xs = @(); $ys = @()
    foreach ($s in $samples) {
      $a = Get-Area $s[0]; $p = Get-Px $s[0]
      $x0 = [int]$s[1] - $a[0]; $y0 = [int]$s[2] - $a[1]
      if ($hays.Count -gt 0) {
        $bx = 0; $by = 0
        [JWT]::Align($hays[0], $hws[0], $xs[0], $ys[0], $p.px, $p.w, $p.h, $x0, $y0, $w, $h, 3, [ref]$bx, [ref]$by)
        $x0 = $bx; $y0 = $by
      }
      $hays += , $p.px; $hws += $p.w; $xs += $x0; $ys += $y0
    }
    $kept = 0; $core = 0; $gap = 0
    $t = [JWT]::Build($mode, [int[][]]$hays, [int[]]$hws, [int[]]$xs, [int[]]$ys, $w, $h, $rangeHalf, 230, 110, $gapValue, $coreFromRow, $flat, [ref]$kept, [ref]$core, [ref]$gap)
    [JWT]::Save($t, $w, $h, (Join-Path $TemplateDir "$name.png"))
    if ($dim.ContainsKey($name)) { [JWT]::Save([JWT]::ScaleTpl($t, $dimGain), $w, $h, (Join-Path $TemplateDir "$($dim[$name]).png")) }
    $at =($samples | ForEach-Object -Begin { $k = 0 } -Process { $a = Get-Area $_[0]; '{0}+{1}' -f ($xs[$k] + $a[0]), ($ys[$k] + $a[1]); $k++ }) -join ' '
    $detail = if ($mode -eq 1) { "글자 속 $core, 바탕 $gap" } elseif ($coreFromRow -lt $h) { "남은 칸 $kept, 그중 $coreFromRow 행 아래 글자 속 $core" } elseif ($flat -lt 256) { "남은 칸 $kept, 가장자리 뺌" } else { "남은 칸 $kept" }
    '{0,-17} {1,-7} {2}x{3} 원본 {4}장, {5}/{6} 칸 ({7}) 자리 {8}' -f $name, $item[1], $w, $h, $samples.Count, $kept, ($w * $h), $detail, $at
  }
  "템플릿 $($items.Count)개와 폰 밝기 대체(_dim) $($dim.Count)개: $TemplateDir"
}

# --- 오프라인 시험: 원본 x 템플릿마다 찾히는 최소 허용 오차 N 을 재서, 코드가 쓰는 허용 오차 이하인지(찾힘) 기대와 대 본다 ---
# 상태마다 찾혀야 하는 템플릿. 여기 없는 템플릿은 그 상태에서 안 찾혀야 한다 (실내·실외 원본 폴더에 같은 이름이 없게 실외는 --night1 등을 붙였다)
$expect = [ordered]@{
  '0-start-freemode-menu'           = @()
  'm-main-free'                     = @('m_title', 'm_boss')
  'm-main-free-quickgps-sel'        = @('m_title', 'm_boss')
  'm-main-free-boss-row-hidden'     = @('m_title')                       # 앉았다 일어나는 동안 Register as a Boss 줄이 잠깐 빠졌다(11줄)
  'm-main-free-boss-sel'            = @('m_title', 'm_boss_sel')
  'm-register-boss-ceo-sel'         = @('m_sub_boss', 'm_ceo_sel')
  'm-securoserv-start-org-sel'      = @('m_sub_securo', 'm_start_org_sel')
  'after-start-org'                 = @()
  'm-main-ceo-securo-sel'           = @('m_title', 'm_securo_sel')
  'm-main-ceo-securo-sel-2'         = @('m_title', 'm_securo_sel')
  'm-main-ceo-securo'               = @('m_title', 'm_securo')
  'm-ceo-menu-hire-sel'             = @('m_sub_securo')
  'm-ceo-menu-retire-sel'           = @('m_sub_securo', 'm_retire_sel')
  'after-retire-you-quit'           = @()
  'm-main-free-after-retire'        = @('m_title', 'm_boss')
  'm-main-free-final'               = @('m_title', 'm_boss')              # F11 실제 시험 뒤 손으로 Retire 한 마지막 상태(23:15)
  'm-mansion-mgmt-sub'              = @()
  '0-start-freemode-phone'          = @()
  'ph-home1-joblist-sel'            = @()
  'ph-home1-vinewood-sel'           = @()
  'ph-home1-contacts-sel'           = @()
  'ph-home1-securoserv-sel'         = @()
  'ph-home2-quickjoin-sel'          = @('ph_quickjoin_sel')
  'ph-home2-quickjoin-sel-from-row3' = @('ph_quickjoin_sel')
  'ph-home2-quickjoin-sel-after-back' = @('ph_quickjoin_sel')
  'ph-home2-settings-sel'           = @()
  'qj-list-series-sel'              = @()
  'qj-list-random-sel'              = @('qj_random_sel')
  'qj-random-friends-sel'           = @()
  'qj-random-alone-sel'             = @('qj_alone_sel')
  'qj-yes-sel'                      = @('qj_yes_sel')
  'phone-closed'                    = @()
}
# 실외(0928). 같은 상태를 밤·낮(폰은 동틀 녘·낮) 두 번 찍었다
# 1024 22:56 MCT 앞 실측(GDI 원본 크기). m_title 은 여기서 79 라 이 표의 40 으로는 안 찾힌다. 수익 자동화는 m_title 을 85 로 찾아
# (EarnCore.ahk EarnSeen) 메뉴는 열렸지만 여유가 6 뿐이다. m_title 은 Earn 템플릿이라 이 스크립트가 뜨지 않는다
$expect['m-main-ceo-securo-sel--lower1'] = @('m_securo_sel')
foreach ($t in $night, $day) {
  $expect["m-main-free-quickgps-sel$t"] = @('m_title', 'm_boss')         # 실외 해제 상태: Quick GPS 다음 2번째 줄이 Register as a Boss
  $expect["m-main-free-boss-sel$t"] = @('m_title', 'm_boss_sel')
  $expect["m-register-boss-ceo-sel$t"] = @('m_sub_boss', 'm_ceo_sel')
  $expect["m-securoserv-start-org-sel$t"] = @('m_sub_securo', 'm_start_org_sel')
  $expect["after-start-org$t"] = @()                                     # CEO 등록 직후 메뉴가 닫히고 CEO 안내가 뜬 화면
  $expect["m-main-ceo-securo-sel$t"] = @('m_title', 'm_securo_sel')
  $expect["m-main-ceo-securo$t"] = @('m_title', 'm_securo')
  $expect["m-ceo-menu-hire-sel$t"] = @('m_sub_securo')
  $expect["m-ceo-menu-retire-sel$t"] = @('m_sub_securo', 'm_retire_sel')
  $expect["after-retire-you-quit$t"] = @()
  $expect["m-main-free-after-retire$t"] = @('m_title', 'm_boss')
}
foreach ($t in $dawn, $day) {
  $expect["ph-home1-joblist-sel$t"] = @()                                # 폰을 열면 1쪽 Job List 가 골라져 있다
  $expect["ph-home1-vinewood-sel$t"] = @()
  $expect["ph-home2-quickjoin-sel$t"] = @('ph_quickjoin_sel')
  $expect["qj-list-series-sel$t"] = @()
  $expect["qj-list-random-sel$t"] = @('qj_random_sel')
  $expect["qj-random-alone-only-sel$t"] = @('qj_alone_sel')             # 세션에 친구가 없으면 Random 안은 Alone 한 줄뿐
  $expect["qj-yes-sel$t"] = @('qj_yes_sel')
  $expect["qj-after-no-back$t"] = @()                                    # 확인 줄에서 Backspace: Quick Join 목록 맨 위(Series Modes)
  $expect["ph-home2-quickjoin-sel-after-back$t"] = @('ph_quickjoin_sel')
  $expect["phone-closed$t"] = @()
}
$expect["ph-home2-settings-sel$dawn"] = @()
# 맑은 낮(--sun1) 폰 원본은 템플릿을 뜨는 데 쓰지 않고 시험에만 쓴다(뜬 원본 밖의 밝기에서도 찾히는지 보는 교차 시험)
$sun = '--sun1'
foreach ($s in 'ph-home1-joblist-sel', 'ph-home1-vinewood-sel', 'qj-list-series-sel', 'qj-after-no-back') { $expect["$s$sun"] = @() }
$expect["ph-home2-quickjoin-sel$sun"] = @('ph_quickjoin_sel')
$expect["ph-home2-quickjoin-sel-after-back$sun"] = @('ph_quickjoin_sel')
$expect["qj-list-random-sel$sun"] = @('qj_random_sel')
$expect["qj-random-alone-only-sel$sun"] = @('qj_alone_sel')
$expect["qj-yes-sel$sun"] = @('qj_yes_sel')

$menuNames = @('m_title', 'm_sub_boss', 'm_sub_securo', 'm_boss', 'm_boss_sel', 'm_ceo_sel', 'm_start_org_sel', 'm_securo', 'm_securo_sel', 'm_retire_sel')
$phoneNames = @('ph_quickjoin_sel', 'qj_random_sel', 'qj_alone_sel', 'qj_yes_sel')
# 실제로 대 보는 파일: 폰은 _dim 대체까지. 표의 폰 칸은 코드처럼 둘 중 작은 N(둘 중 하나라도 보이면 찾힘)
$files = @($menuNames + $phoneNames + @($phoneNames | ForEach-Object { $dim[$_] }))
$tpx = @(); $tw = @(); $th = @()
foreach ($n in $files) {
  $p = if ($n -eq 'm_title') { $earnTitle } else { Join-Path $TemplateDir "$n.png" }
  $w = 0; $h = 0; $tpx += , [JWT]::Load($p, [ref]$w, [ref]$h); $tw += $w; $th += $h
}
function Get-Var([string]$n) { if ($variation.ContainsKey($n)) { return $variation[$n] } return 40 }
# 원본 묶음(메뉴 조각·폰 조각)마다 템플릿 파일 전부의 최소 N 을 재서, 이름마다(대체 포함) 가장 작은 값으로 돌려준다
function Measure-All($stateList, $pxList, $wList, $hList) {
  $pa = New-Object System.Collections.Generic.List[int]; $pb = New-Object System.Collections.Generic.List[int]
  for ($i = 0; $i -lt $stateList.Count; $i++) {
    $isMenu = (Get-Area $stateList[$i])[0] -eq 0
    for ($j = 0; $j -lt $files.Count; $j++) { if (($files[$j] -in $menuNames) -eq $isMenu) { $pa.Add($i); $pb.Add($j) } }
  }
  $ox = New-Object int[] $pa.Count; $oy = New-Object int[] $pa.Count
  $mv = [JWT]::MinVarAll([int[][]]$pxList, [int[]]$wList, [int[]]$hList, [int[][]]$tpx, [int[]]$tw, [int[]]$th, $pa.ToArray(), $pb.ToArray(), $ox, $oy)
  $cell = @{}
  for ($k = 0; $k -lt $pa.Count; $k++) {
    $n = $files[$pb[$k]]; foreach ($base in $dim.Keys) { if ($dim[$base] -eq $n) { $n = $base } }
    $key = "$($pa[$k]),$n"
    if (-not $cell.ContainsKey($key) -or $mv[$k] -lt $cell[$key]) { $cell[$key] = $mv[$k] }
  }
  return $cell
}
$states = @($expect.Keys)
$hays = @(); $hw = @(); $hh = @()
foreach ($s in $states) { $p = Get-Px $s; $hays += , $p.px; $hw += $p.w; $hh += $p.h }
$cell = Measure-All $states $hays $hw $hh

# 표: 칸 값은 찾히는 최소 N. + 는 찾힘(기대대로), * 는 기대와 다름(찾혀야 하는데 N 이 허용 오차보다 크거나, 안 찾혀야 하는데 N 이 허용 오차 이하)
$fail = 0; $total = 0; $posMax = @{}; $negMin = @{}
foreach ($grp in @(@{ names = $menuNames; menu = $true }, @{ names = $phoneNames; menu = $false })) {
  $hdr = '{0,-44}' -f '상태 \ 템플릿(허용 오차)'
  foreach ($n in $grp.names) { $hdr += ' {0,15}' -f "$n($(Get-Var $n))" }
  $hdr
  for ($i = 0; $i -lt $states.Count; $i++) {
    if ((((Get-Area $states[$i])[0] -eq 0)) -ne $grp.menu) { continue }
    $line = '{0,-44}' -f $states[$i]
    foreach ($n in $grp.names) {
      $v = Get-Var $n; $n0 = $cell["$i,$n"]; $want = $expect[$states[$i]] -contains $n; $found = $n0 -le $v; $total++
      if ($want) { if (-not $posMax.ContainsKey($n) -or $n0 -gt $posMax[$n]) { $posMax[$n] = $n0 } }
      else { if (-not $negMin.ContainsKey($n) -or $n0 -lt $negMin[$n]) { $negMin[$n] = $n0 } }
      $mark = if ($found -ne $want) { $fail++; '*' } elseif ($want) { '+' } else { ' ' }
      $line += ' {0,15}' -f "$n0$mark"
    }
    $line
  }
  ''
}
'템플릿별 여유: 찾혀야 할 원본의 최대 N / 허용 오차 / 안 찾혀야 할 원본의 최소 N (폰은 _dim 대체와 둘 중 작은 N)'
foreach ($n in $menuNames + $phoneNames) { '  {0,-17} {1,4} / {2,3} / {3,4}' -f $n, $posMax[$n], (Get-Var $n), $negMin[$n] }

if ($GainSim) {
  # 폰 화면 밝기 모의: 폰 원본 전부(실내·실외)를 g 배로 줄여 같은 표를 다시 잰다. 실측이 아니라 선형 밝기 모델(0.87~1.0 실측에서 채널·값에 상관없이 거의 일정한 배율)이다
  ''
  '폰 밝기 모의(원본 x g): 템플릿마다 찾혀야 할 원본의 최대 N / 안 찾혀야 할 원본의 최소 N, 기대와 다르면 *'
  $ph = @($states | Where-Object { (Get-Area $_)[0] -ne 0 })
  foreach ($g in 1.1, 1.0, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65) {
    $sp = @(); $sw = @(); $sh = @()
    foreach ($s in $ph) { $p = Get-Px $s; $sp += , [JWT]::Scale($p.px, $g, $false); $sw += $p.w; $sh += $p.h }
    $c2 = Measure-All $ph $sp $sw $sh
    $line = '  g={0,-5}' -f $g
    foreach ($n in $phoneNames) {
      $pm = 0; $nm = 999
      for ($i = 0; $i -lt $ph.Count; $i++) { $n0 = $c2["$i,$n"]; if ($expect[$ph[$i]] -contains $n) { $pm = [Math]::Max($pm, $n0) } else { $nm = [Math]::Min($nm, $n0) } }
      $bad = if ($pm -gt (Get-Var $n) -or $nm -le (Get-Var $n)) { '*' } else { ' ' }
      $line += ' {0,-17} {1,3} / {2,3}{3} |' -f $n, $pm, $nm, $bad
    }
    $line
  }
}
if ($fail) { "FAIL: $fail / $total 칸이 기대와 다름 (* 표시)"; exit 1 }
"PASS: 원본 $($states.Count)장 x 템플릿 $total 칸이 전부 기대대로 (찾혀야 할 곳에서만 찾힘, + 는 찾힘)"
