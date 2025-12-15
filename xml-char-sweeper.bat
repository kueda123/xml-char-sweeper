<# :
@echo off
cd /d "%‾dp0"
set "REAL_SCRIPT=%‾f0"

REM ----------------------------------------------------------------------
REM  XML Char Sweeper
REM  PowerShellをBypassモードで呼び出し、自分自身をShift-JISとして読み込む
REM ----------------------------------------------------------------------
powershell -NoProfile -ExecutionPolicy Bypass -Command "Invoke-Expression ([System.IO.File]::ReadAllText('%REAL_SCRIPT%', [System.Text.Encoding]::Default))"
exit /b
#>

# ==============================================================================
#  これより下は PowerShell スクリプトとして実行されます
# ==============================================================================

# --- 設定 ---
$inputPath  = "server.xml"
$outputPath = "server.cleaned.xml"

# --- コンソール出力設定 ---
[Console]::OutputEncoding = [System.Text.Encoding]::Default

Write-Host "========================================================" -ForegroundColor Cyan
Write-Host " XML Char Sweeper (server.xml Cleaning Tool)" -ForegroundColor Cyan
Write-Host "========================================================"
Write-Host "対象ファイル: $inputPath"

# --- ファイル存在チェック ---
if (-not (Test-Path $inputPath)) {
    Write-Host "`n[Error] $inputPath が見つかりません。" -ForegroundColor Red
    Write-Host "このバッチファイルを server.xml と同じ場所に置いてください。"
    Read-Host "Enterキーを押して終了してください"
    exit
}

# --- 定義マップ (Hex -> 置換後文字列, 表示名) ---
$def = @{
    # === [1] 空白・制御文字系 ===
    ([char]0x00A0) = @{ Replace = " "; Name = "NBSP (No-Break Space)" }
    ([char]0x3000) = @{ Replace = " "; Name = "全角スペース" }
    ([char]0x200B) = @{ Replace = "";  Name = "ゼロ幅スペース" }
    ([char]0x202F) = @{ Replace = " "; Name = "Narrow NBSP" }
    ([char]0x205F) = @{ Replace = " "; Name = "Medium Math Space" }
    ([char]0x2060) = @{ Replace = "";  Name = "Word Joiner" }
    ([char]0xFEFF) = @{ Replace = "";  Name = "BOM (Zero Width No-Break Space)" }
    ([char]0x2002) = @{ Replace = " "; Name = "En Space" }
    ([char]0x2003) = @{ Replace = " "; Name = "Em Space" }
    ([char]0x2004) = @{ Replace = " "; Name = "1/3 Em Space" }
    ([char]0x2005) = @{ Replace = " "; Name = "1/4 Em Space" }
    ([char]0x2006) = @{ Replace = " "; Name = "1/6 Em Space" }
    ([char]0x2009) = @{ Replace = " "; Name = "Thin Space" }
    ([char]0x200A) = @{ Replace = "";  Name = "Hair Space" }
    
    # === [2] 改行・区切り系 ===
    ([char]0x2028) = @{ Replace = "";  Name = "Line Separator (行区切り)" }
    ([char]0x2029) = @{ Replace = "";  Name = "Paragraph Separator (段落区切り)" }
    ([char]0x0085) = @{ Replace = "";  Name = "Next Line (NEL)" }
    
    # === [3] 結合子・方向制御系 ===
    ([char]0x200C) = @{ Replace = "";  Name = "ゼロ幅非接合子 (ZWNJ)" }
    ([char]0x200D) = @{ Replace = "";  Name = "ゼロ幅接合子 (ZWJ)" }
    ([char]0x200E) = @{ Replace = "";  Name = "LTR Mark" }
    ([char]0x200F) = @{ Replace = "";  Name = "RTL Mark" }
    ([char]0x202E) = @{ Replace = "";  Name = "RTL Override" }
    
    # === [4] スマートクォート (Word/Wiki由来) ===
    ([char]0x2018) = @{ Replace = "'"; Name = "左シングルクォート" }
    ([char]0x2019) = @{ Replace = "'"; Name = "右シングルクォート" }
    ([char]0x201A) = @{ Replace = ","; Name = "Single Low-9 Quote" }
    ([char]0x201B) = @{ Replace = "'"; Name = "Single High-Reversed-9 Quote" }
    ([char]0x201C) = @{ Replace = '"'; Name = "左ダブルクォート" }
    ([char]0x201D) = @{ Replace = '"'; Name = "右ダブルクォート" }
    ([char]0x201E) = @{ Replace = '"'; Name = "Double Low-9 Quote" }
    ([char]0x00B4) = @{ Replace = "'"; Name = "Acute Accent" }
    ([char]0x0060) = @{ Replace = "'"; Name = "Grave Accent" }

    # === [5] ハイフン・ダッシュ類 (コピペ事故の主原因) ===
    ([char]0x2010) = @{ Replace = "-"; Name = "Hyphen (U+2010)" }
    ([char]0x2011) = @{ Replace = "-"; Name = "Non-Breaking Hyphen" }
    ([char]0x2012) = @{ Replace = "-"; Name = "Figure Dash" }
    ([char]0x2013) = @{ Replace = "-"; Name = "En Dash" }
    ([char]0x2014) = @{ Replace = "-"; Name = "Em Dash" }
    ([char]0x2212) = @{ Replace = "-"; Name = "Minus Sign" }
}

# --- 処理準備 ---
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$lines = [System.IO.File]::ReadAllLines($inputPath, $utf8NoBom)

# 正規表現の組み立て
$pattern = ($def.Keys | ForEach-Object { [regex]::Escape($_) }) -join '|'
# XML禁止制御文字 (0x00-0x08, 0x0B, 0x0C, 0x0E-0x1F) も検出対象に追加
$xmlInvalidPattern = "[¥x00-¥x08¥x0B¥x0C¥x0E-¥x1F]"
$regex = [System.Text.RegularExpressions.Regex]::new("$pattern|$xmlInvalidPattern", [System.Text.RegularExpressions.RegexOptions]::Compiled)

$stats = @{}

# コールバック関数
$callback = {
    param($match)
    $char = [char]$match.Value
    
    # 統計用カウント
    if (-not $stats.ContainsKey($char)) { $stats[$char] = 0 }
    $stats[$char]++
    
    # 定義済みなら置換文字を返す、未定義(制御文字等)なら削除(空文字)
    if ($def.ContainsKey($char)) {
        return $def[$char].Replace
    } else {
        return "" 
    }
}

$processedLines = New-Object System.Collections.Generic.List[string]
$dirtyLineCount = 0

# --- メインループ ---
Write-Host "チェック中..."
for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($regex.IsMatch($line)) {
        $dirtyLineCount++
        $line = $regex.Replace($line, $callback)
    }
    $processedLines.Add($line)
}

# --- 結果出力 ---
if ($stats.Count -gt 0) {
    Write-Host "`n[!] 警告: 不要な文字が検出されました。" -ForegroundColor Yellow
    Write-Host "--------------------------------------------------------"
    Write-Host ("{0,-40} | {1,5} | {2}" -f "文字種別", "件数", "Hex")
    Write-Host "--------------------------------------------------------"
    
    foreach ($key in $stats.Keys) {
        $hex = "0x{0:X4}" -f [int]$key
        $name = if ($def.ContainsKey($key)) { $def[$key].Name } else { "不正な制御文字 (XML禁止)" }
        Write-Host ("{0,-40} | {1,5} | {2}" -f $name, $stats[$key], $hex)
    }
    Write-Host "--------------------------------------------------------"
    Write-Host "影響を受けた行数: $dirtyLineCount 行"
    
    # 保存処理
    [System.IO.File]::WriteAllLines($outputPath, $processedLines, $utf8NoBom)
    Write-Host "`n[Save] クリーニングされたファイルを保存しました: $outputPath" -ForegroundColor Cyan
    
    # 簡易XMLチェック
    Write-Host "XML構文チェックを実施中..."
    try {
        [xml]$check = Get-Content $outputPath -Encoding UTF8
        Write-Host "[OK] XMLとして正常に読み込めました。" -ForegroundColor Green
    } catch {
        Write-Host "[Warning] 文字は除去しましたが、XMLタグ構造にエラーがある可能性があります。" -ForegroundColor Red
        Write-Host "エラー詳細: $($_.Exception.Message)"
    }
}
else {
    Write-Host "`n[OK] 修正箇所は見つかりませんでした。" -ForegroundColor Green
    if (Test-Path $outputPath) { Remove-Item $outputPath }
}

Write-Host "`n完了。"
Read-Host "Enterキーを押して終了してください"