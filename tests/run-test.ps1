# PowerShell & SQLite データ同期システム
# テスト実行スクリプト

param(
    [string]$TestPath = "",
    [ValidateSet("All", "Unit", "Integration", "Foundation", "Infrastructure", "Process")]
    [string]$TestType = "All",
    [ValidateSet("NUnitXml", "HTML", "Text", "Console")]
    [string]$OutputFormat = "Console",
    [string]$OutputPath = "",
    [switch]$ShowCoverage,
    [switch]$Detailed,
    [switch]$SkipSlowTests,
    [int]$TimeoutMinutes = 30
)

# スクリプトの場所を基準にプロジェクトルートを設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.FullName
$TestsRoot = $PSScriptRoot

# 必要なモジュールの確認とインストール
function Install-RequiredModules {
    $requiredModules = @("Pester")
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable -Name $module)) {
            Write-Host "必要なモジュール '$module' をインストール中..." -ForegroundColor Yellow
            try {
                Install-Module -Name $module -Force -Scope CurrentUser -AllowClobber
                Write-Host "✓ $module をインストールしました" -ForegroundColor Green
            }
            catch {
                Write-Error "モジュール '$module' のインストールに失敗しました: $($_.Exception.Message)"
                exit 1
            }
        }
    }
}

# Pesterの設定
function Initialize-PesterConfiguration {
    param(
        [string]$TestType,
        [string]$OutputFormat,
        [string]$OutputPath,
        [bool]$ShowCoverage,
        [bool]$SkipSlowTests,
        [int]$TimeoutMinutes
    )
    
    # Pester 5.x の設定
    $config = New-PesterConfiguration
    
    # 実行対象の設定
    switch ($TestType) {
        "Unit" {
            $config.Run.Path = @(
                (Join-Path $TestsRoot "Utils"),
                (Join-Path $TestsRoot "Process")
            )
        }
        "Integration" {
            $config.Run.Path = Join-Path $TestsRoot "Integration"
        }
        "Foundation" {
            $config.Run.Path = Join-Path $TestsRoot "Utils" "Foundation"
        }
        "Infrastructure" {
            $config.Run.Path = Join-Path $TestsRoot "Utils" "Infrastructure"
        }
        "Process" {
            $config.Run.Path = Join-Path $TestsRoot "Process"
        }
        default {
            $config.Run.Path = $TestsRoot
        }
    }
    
    # 出力設定
    $config.Output.Verbosity = if ($Detailed) { "Detailed" } else { "Normal" }
    
    # タイムアウト設定
    # $config.Run.Timeout = [TimeSpan]::FromMinutes($TimeoutMinutes)
    
    # 並列実行の設定
    $config.Run.PassThru = $true
    
    # タグベースのフィルタリング
    if ($SkipSlowTests) {
        $config.Filter.ExcludeTag = @("Slow", "Performance")
    }
    
    # 出力形式の設定
    switch ($OutputFormat) {
        "NUnitXml" {
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $OutputPath = Join-Path $TestsRoot "TestResults.xml"
            }
            $config.TestResult.Enabled = $true
            $config.TestResult.OutputFormat = "NUnitXml"
            $config.TestResult.OutputPath = $OutputPath
        }
        "HTML" {
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $OutputPath = Join-Path $TestsRoot "TestResults.html"
            }
            # HTML出力は別途処理
        }
        "Text" {
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $OutputPath = Join-Path $TestsRoot "TestResults.txt"
            }
            # テキスト出力は別途処理
        }
    }
    
    # カバレッジ設定
    if ($ShowCoverage) {
        $config.CodeCoverage.Enabled = $true
        $config.CodeCoverage.Path = @(
            (Join-Path $ProjectRoot "scripts" "modules" "Utils" "*.psm1"),
            (Join-Path $ProjectRoot "scripts" "modules" "Process" "*.psm1")
        )
        $config.CodeCoverage.OutputFormat = "JaCoCo"
        $config.CodeCoverage.OutputPath = Join-Path $TestsRoot "Coverage.xml"
    }
    
    return $config
}

# HTML レポートの生成
function New-HtmlReport {
    param(
        [Parameter(Mandatory = $true)]
        $TestResult,
        [string]$OutputPath
    )
    
    $htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>PowerShell & SQLite データ同期システム - テスト結果</title>
    <meta charset="utf-8">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; }
        .header { background-color: #f0f0f0; padding: 20px; border-radius: 5px; }
        .summary { margin: 20px 0; }
        .passed { color: green; }
        .failed { color: red; }
        .skipped { color: orange; }
        .test-details { margin-top: 20px; }
        .test-container { border: 1px solid #ddd; margin: 10px 0; padding: 15px; border-radius: 5px; }
        .test-name { font-weight: bold; }
        .test-time { color: #666; font-size: 0.9em; }
        .error-message { background-color: #ffebee; padding: 10px; margin: 10px 0; border-left: 4px solid #f44336; }
        table { border-collapse: collapse; width: 100%; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="header">
        <h1>PowerShell & SQLite データ同期システム</h1>
        <h2>テスト実行結果</h2>
        <p>実行日時: $(Get-Date -Format "yyyy年MM月dd日 HH:mm:ss")</p>
    </div>
    
    <div class="summary">
        <h3>実行サマリー</h3>
        <table>
            <tr><th>項目</th><th>件数</th></tr>
            <tr><td>総テスト数</td><td>$($TestResult.TotalCount)</td></tr>
            <tr><td class="passed">成功</td><td>$($TestResult.PassedCount)</td></tr>
            <tr><td class="failed">失敗</td><td>$($TestResult.FailedCount)</td></tr>
            <tr><td class="skipped">スキップ</td><td>$($TestResult.SkippedCount)</td></tr>
            <tr><td>実行時間</td><td>$($TestResult.Time)</td></tr>
        </table>
    </div>
"@

    if ($TestResult.Failed.Count -gt 0) {
        $htmlContent += @"
    <div class="test-details">
        <h3>失敗したテスト</h3>
"@
        foreach ($failedTest in $TestResult.Failed) {
            $htmlContent += @"
        <div class="test-container">
            <div class="test-name">$($failedTest.Name)</div>
            <div class="test-time">実行時間: $($failedTest.Time)</div>
            <div class="error-message">
                <strong>エラーメッセージ:</strong><br>
                $($failedTest.ErrorRecord.Exception.Message -replace "`n", "<br>")
            </div>
        </div>
"@
        }
        $htmlContent += "</div>"
    }

    $htmlContent += @"
    <div class="test-details">
        <h3>すべてのテスト結果</h3>
        <table>
            <tr>
                <th>テスト名</th>
                <th>結果</th>
                <th>実行時間</th>
                <th>詳細</th>
            </tr>
"@
    
    foreach ($test in $TestResult.Tests) {
        $statusClass = switch ($test.Result) {
            "Passed" { "passed" }
            "Failed" { "failed" }
            "Skipped" { "skipped" }
            default { "" }
        }
        
        $details = if ($test.Result -eq "Failed") {
            $test.ErrorRecord.Exception.Message
        }
        else {
            ""
        }
        
        $htmlContent += @"
            <tr>
                <td>$($test.Name)</td>
                <td class="$statusClass">$($test.Result)</td>
                <td>$($test.Time)</td>
                <td>$details</td>
            </tr>
"@
    }
    
    $htmlContent += @"
        </table>
    </div>
</body>
</html>
"@
    
    $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "HTMLレポートを生成しました: $OutputPath" -ForegroundColor Green
}

# メイン処理
function Invoke-TestExecution {
    Write-Host "=== PowerShell & SQLite データ同期システム テスト実行 ===" -ForegroundColor Cyan
    Write-Host "プロジェクトルート: $ProjectRoot" -ForegroundColor Gray
    Write-Host "テストルート: $TestsRoot" -ForegroundColor Gray
    Write-Host ""
    
    # 必要なモジュールのインストール
    Install-RequiredModules
    
    # Pesterモジュールのインポート
    Import-Module Pester -Force
    
    # 特定のテストパスが指定された場合
    if (-not [string]::IsNullOrEmpty($TestPath)) {
        $fullTestPath = if ([System.IO.Path]::IsPathRooted($TestPath)) {
            $TestPath
        }
        else {
            Join-Path $TestsRoot $TestPath
        }
        
        if (-not (Test-Path $fullTestPath)) {
            Write-Error "指定されたテストパスが見つかりません: $fullTestPath"
            exit 1
        }
        
        Write-Host "特定のテストを実行中: $fullTestPath" -ForegroundColor Yellow
        $config = New-PesterConfiguration
        $config.Run.Path = $fullTestPath
        $config.Output.Verbosity = if ($Detailed) { "Detailed" } else { "Normal" }
        $config.Run.PassThru = $true
    }
    else {
        Write-Host "テストタイプ: $TestType" -ForegroundColor Yellow
        $config = Initialize-PesterConfiguration -TestType $TestType -OutputFormat $OutputFormat -OutputPath $OutputPath -ShowCoverage $ShowCoverage -SkipSlowTests $SkipSlowTests -TimeoutMinutes $TimeoutMinutes
    }
    
    # テスト実行
    Write-Host "テスト実行を開始します..." -ForegroundColor Green
    $startTime = Get-Date
    
    try {
        $result = Invoke-Pester -Configuration $config
        
        $endTime = Get-Date
        $totalDuration = $endTime - $startTime
        
        # 結果の表示
        Write-Host ""
        Write-Host "=== テスト実行完了 ===" -ForegroundColor Cyan
        Write-Host "総実行時間: $($totalDuration.TotalSeconds) 秒" -ForegroundColor Gray
        Write-Host "総テスト数: $($result.TotalCount)" -ForegroundColor White
        Write-Host "成功: $($result.PassedCount)" -ForegroundColor Green
        Write-Host "失敗: $($result.FailedCount)" -ForegroundColor Red
        Write-Host "スキップ: $($result.SkippedCount)" -ForegroundColor Yellow
        
        # HTML レポートの生成
        if ($OutputFormat -eq "HTML") {
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $OutputPath = Join-Path $TestsRoot "TestResults.html"
            }
            New-HtmlReport -TestResult $result -OutputPath $OutputPath
        }
        
        # テキスト レポートの生成
        if ($OutputFormat -eq "Text") {
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $OutputPath = Join-Path $TestsRoot "TestResults.txt"
            }
            
            $textReport = @"
PowerShell & SQLite データ同期システム テスト結果
実行日時: $(Get-Date -Format "yyyy年MM月dd日 HH:mm:ss")
総実行時間: $($totalDuration.TotalSeconds) 秒

=== サマリー ===
総テスト数: $($result.TotalCount)
成功: $($result.PassedCount)
失敗: $($result.FailedCount)
スキップ: $($result.SkippedCount)

=== 失敗したテスト ===
"@
            
            foreach ($failedTest in $result.Failed) {
                $textReport += "`n- $($failedTest.Name)"
                $textReport += "`n  エラー: $($failedTest.ErrorRecord.Exception.Message)"
                $textReport += "`n"
            }
            
            $textReport | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host "テキストレポートを生成しました: $OutputPath" -ForegroundColor Green
        }
        
        # カバレッジ情報の表示
        if ($ShowCoverage -and $result.CodeCoverage) {
            Write-Host ""
            Write-Host "=== コードカバレッジ ===" -ForegroundColor Cyan
            Write-Host "カバレッジ率: $($result.CodeCoverage.CoveragePercent)%" -ForegroundColor White
            Write-Host "実行された行: $($result.CodeCoverage.ExecutedLines)" -ForegroundColor Green
            Write-Host "総行数: $($result.CodeCoverage.TotalLines)" -ForegroundColor White
            
            if ($result.CodeCoverage.MissedLines.Count -gt 0) {
                Write-Host "未実行の行があります:" -ForegroundColor Yellow
                foreach ($missedLine in $result.CodeCoverage.MissedLines | Select-Object -First 10) {
                    Write-Host "  $($missedLine.File):$($missedLine.Line)" -ForegroundColor Yellow
                }
                if ($result.CodeCoverage.MissedLines.Count -gt 10) {
                    Write-Host "  ... 他 $($result.CodeCoverage.MissedLines.Count - 10) 行" -ForegroundColor Yellow
                }
            }
        }
        
        # 終了コードの設定
        if ($result.FailedCount -gt 0) {
            Write-Host ""
            Write-Host "テストが失敗しました。詳細を確認してください。" -ForegroundColor Red
            exit 1
        }
        else {
            Write-Host ""
            Write-Host "すべてのテストが成功しました！" -ForegroundColor Green
            exit 0
        }
    }
    catch {
        Write-Error "テスト実行中にエラーが発生しました: $($_.Exception.Message)"
        Write-Host "スタックトレース: $($_.ScriptStackTrace)" -ForegroundColor Red
        exit 1
    }
}

# ヘルプの表示
function Show-Help {
    Write-Host @"
PowerShell & SQLite データ同期システム テスト実行スクリプト

使用方法:
  pwsh ./tests/run-test.ps1 [オプション]

オプション:
  -TestPath <パス>          特定のテストファイルまたはディレクトリを実行
  -TestType <タイプ>        実行するテストタイプ (All, Unit, Integration, Foundation, Infrastructure, Process)
  -OutputFormat <形式>      出力形式 (Console, NUnitXml, HTML, Text)
  -OutputPath <パス>        出力ファイルのパス
  -ShowCoverage            コードカバレッジを表示
  -Detailed               詳細な出力を表示
  -SkipSlowTests          時間のかかるテストをスキップ
  -TimeoutMinutes <分>     テストのタイムアウト時間（デフォルト: 30分）

使用例:
  # すべてのテストを実行
  pwsh ./tests/run-test.ps1

  # ユニットテストのみ実行
  pwsh ./tests/run-test.ps1 -TestType Unit

  # 特定のテストファイルを実行
  pwsh ./tests/run-test.ps1 -TestPath "Utils\Foundation\CoreUtils.Tests.ps1"

  # カバレッジとHTMLレポート付きで実行
  pwsh ./tests/run-test.ps1 -ShowCoverage -OutputFormat HTML

  # 統合テストのみ実行
  pwsh ./tests/run-test.ps1 -TestType Integration

  # 詳細出力で実行
  pwsh ./tests/run-test.ps1 -Detailed
"@
}

# ヘルプが要求された場合
if ($args -contains "-h" -or $args -contains "-help" -or $args -contains "--help") {
    Show-Help
    exit 0
}

# メイン処理の実行
Invoke-TestExecution