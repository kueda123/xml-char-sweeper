# =======================================================
# テスト用 server.xml 生成ツール
# 意図的に「不正な文字」を混入させたファイルを作成します
# =======================================================

$fileName = "server.xml"

# --- 混入させる不正文字の定義 ---
$badChars = @{
    "ZeroWidthSpace" = [char]0x200B
    "SmartQuote_L"   = [char]0x201C  # “
    "SmartQuote_R"   = [char]0x201D  # ”
    "SmartHyphen"    = [char]0x2013  # – (En Dash: コピペでよく混入する)
    "NBSP"           = [char]0x00A0  # (No-Break Space)
    "ControlChar"    = [char]0x000B  # (Vertical Tab: XML禁止文字)
}

# --- テストデータの組み立て ---
# 一見普通に見えますが、変数部分にゴミが入ります
$xmlContent = @"
<?xml version="1.0" encoding="UTF-8"?>
<server description="new server">

    <featureManager>
        <feature$($badChars.ZeroWidthSpace)>jsp-2.3</feature> <feature>localConnector-1.0</feature>
    </featureManager>

    <httpEndpoint id=$($badChars.SmartQuote_L)defaultHttpEndpoint$($badChars.SmartQuote_R)
                  host="*"
                  httpPort="9080"
                  httpsPort="9443$($badChars.ZeroWidthSpace)" /> <applicationMonitor updateTrigger="mbean" />

    <webContainer deferServletLoad="false$($badChars.NBSP)"/>

    <logging traceSpecification="*=info" maxFileSize="20$($badChars.SmartHyphen)40" /> </server>
"@

# --- ファイル保存 ---
# server.xml として UTF-8 (BOMなし) で保存
[System.IO.File]::WriteAllText($fileName, $xmlContent, (New-Object System.Text.UTF8Encoding($false)))

Write-Host "----------------------------------------------------------------"
Write-Host "汚れたテストファイル '$fileName' を作成しました。" -ForegroundColor Yellow
Write-Host "このファイルには以下の不正文字が含まれています："
Write-Host " - スマートクォート (Word由来)"
Write-Host " - ゼロ幅スペース (Webコピペ由来)"
Write-Host " - En Dash (ハイフンに見える別の文字)"
Write-Host " - 不正な制御文字"
Write-Host "----------------------------------------------------------------"
Write-Host "同じフォルダにある 'xml-char-sweeper.bat' を実行して、"
Write-Host "これらが検知・修正されるか確認してください。"
Write-Host "----------------------------------------------------------------"