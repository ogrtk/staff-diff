#!/usr/bin/env pwsh
# -*- coding: utf-8 -*-
<#
.SYNOPSIS
PowerShell & SQLite Data Management System Test Runner

.DESCRIPTION
Pesterフレームワークを使用してすべてのモジュールとメインスクリプトのテストを実行します。
テスト結果はHTMLレポートとして出力され、カバレッジ情報も含まれます。

.PARAMETER TestPath
実行するテストファイルのパス。指定しない場合はすべてのテストを実行

.PARAMETER OutputFormat
出力形式。NUnitXml, JUnitXml, HTML, Console から選択可能

.PARAMETER ShowCoverage
カバレッジ情報を表示するかどうか

.PARAMETER Layer
特定のレイヤーのテストのみを実行。Foundation, Infrastructure, DataAccess, DataProcessing から選択

.EXAMPLE
.\run-test.ps1
すべてのテストを実行

.EXAMPLE
.\run-test.ps1 -TestPath "Utils\Foundation\CoreUtils.Tests.ps1"
特定のテストファイルのみを実行

.EXAMPLE
.\run-test.ps1 -Layer "Foundation"
Foundation層のテストのみを実行

.EXAMPLE
.\run-test.ps1 -OutputFormat "HTML" -ShowCoverage
HTMLレポートでカバレッジを含めてテストを実行
#>

[CmdletBinding()]
param(
    [string]$TestPath = $null,

    [ValidateSet("NUnitXml", "JUnitXml", "HTML", "Console")]
    [string]$OutputFormat = "Console",

    [switch]$ShowCoverage,

    [ValidateSet("Foundation", "Infrastructure", "DataAccess", "DataProcessing")]
    [string]$Layer = $null
)

# UTF-8 encoding setup for Japanese text
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
}
else {
    $OutputEncoding = [System.Text.UTF8Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
}

# Set console to display UTF-8 properly
if ($env:LANG -notlike "*UTF-8*") {
    $env:LANG = "en_US.UTF-8"
}

# Pester module availability check and installation
if (-not (Get-Module -ListAvailable -Name Pester)) {
    Write-Host "Pester module not found. Installing..." -ForegroundColor Yellow
    try {
        Install-Module -Name Pester -Force -SkipPublisherCheck -Scope CurrentUser
        Write-Host "Pester module installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install Pester module: $($_.Exception.Message)"
        exit 1
    }
}

# Import Pester module
Import-Module Pester -Force

# HTML conversion function
function Convert-TestResultToHtml {
    param(
        [Parameter(Mandatory = $true)]
        [string]$XmlPath,

        [Parameter(Mandatory = $true)]
        [string]$HtmlPath,

        [Parameter(Mandatory = $true)]
        [object]$TestResult
    )
    
    try {
        # Read XML content
        if (-not (Test-Path $XmlPath)) {
            throw "XML file not found: $XmlPath"
        }
        
        # [xml]$xmlContent = Get-Content $XmlPath -Raw -Encoding UTF8
        
        # Generate HTML content
        $htmlContent = @"
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>PowerShell Test Results</title>
    <style>
        body { font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; margin: 20px; background-color: #f5f5f5; }
        .header { background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); color: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; }
        .summary { background: white; padding: 20px; border-radius: 8px; margin-bottom: 20px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .test-section { background: white; margin-bottom: 20px; border-radius: 8px; overflow: hidden; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .section-header { background: #f8f9fa; padding: 15px; border-bottom: 1px solid #dee2e6; font-weight: bold; }
        .test-case { padding: 10px 15px; border-bottom: 1px solid #f0f0f0; }
        .test-case:last-child { border-bottom: none; }
        .passed { color: #28a745; }
        .failed { color: #dc3545; }
        .skipped { color: #ffc107; }
        .stats { display: flex; gap: 20px; }
        .stat-item { text-align: center; }
        .stat-number { font-size: 2em; font-weight: bold; }
        .duration { color: #6c757d; font-size: 0.9em; }
        .error-details { background: #f8f9fa; padding: 10px; margin-top: 10px; border-left: 4px solid #dc3545; font-family: monospace; font-size: 0.9em; }
    </style>
</head>
<body>
    <div class="header">
        <h1>🧪 PowerShell テスト結果</h1>
        <p>生成日時: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")</p>
    </div>
    
    <div class="summary">
        <h2>📊 テスト概要</h2>
        <div class="stats">
            <div class="stat-item">
                <div class="stat-number passed">$($TestResult.PassedCount)</div>
                <div>成功</div>
            </div>
            <div class="stat-item">
                <div class="stat-number failed">$($TestResult.FailedCount)</div>
                <div>失敗</div>
            </div>
            <div class="stat-item">
                <div class="stat-number skipped">$($TestResult.SkippedCount)</div>
                <div>スキップ</div>
            </div>
            <div class="stat-item">
                <div class="stat-number">$($TestResult.TotalCount)</div>
                <div>合計</div>
            </div>
        </div>
        <p class="duration">⏱️ 実行時間: $($TestResult.Duration)</p>
    </div>
"@
        
        # Process test results by describe blocks with duplicate removal
        if ($TestResult.Tests) {
            # 重複テストの除去：同じファイル、同じDescribe、同じテスト名のものは最新の結果のみを保持
            $uniqueTests = @{}
            foreach ($test in $TestResult.Tests) {
                $testKey = "$($test.Path)::$($test.Block.Name)::$($test.Name)"
                if (-not $uniqueTests.ContainsKey($testKey) -or $test.Duration -gt $uniqueTests[$testKey].Duration) {
                    $uniqueTests[$testKey] = $test
                }
            }
            
            $testsByContainer = $uniqueTests.Values | Group-Object { $_.Block.Name }
            
            foreach ($container in $testsByContainer) {
                # コンテナ内のテストからファイル情報を取得
                $testFile = $container.Group[0].Path
                $fileName = if ($testFile) { Split-Path -Leaf $testFile } else { "未知のファイル" }
                
                $htmlContent += @"
    <div class="test-section">
        <div class="section-header">📋 $($container.Name) <span style="font-size: 0.8em; color: #6c757d;">($fileName)</span></div>
"@
                
                foreach ($test in $container.Group) {
                    $statusClass = switch ($test.Result) {
                        "Passed" { "passed" }
                        "Failed" { "failed" }
                        "Skipped" { "skipped" }
                        default { "" }
                    }
                    
                    $statusIcon = switch ($test.Result) {
                        "Passed" { "✅" }
                        "Failed" { "❌" }
                        "Skipped" { "⚠️" }
                        default { "❓" }
                    }
                    
                    $htmlContent += @"
        <div class="test-case">
            <span class="$statusClass">$statusIcon $($test.Name)</span>
            <span class="duration">($($test.Duration))</span>
"@
                    
                    if ($test.Result -eq "Failed" -and $test.ErrorRecord) {
                        $errorMessage = $test.ErrorRecord.Exception.Message -replace "<", "&lt;" -replace ">", "&gt;"
                        $htmlContent += @"
            <div class="error-details">
                <strong>エラー:</strong> $errorMessage
            </div>
"@
                    }
                    
                    $htmlContent += "        </div>`n"
                }
                
                $htmlContent += "    </div>`n"
            }
        }
        
        $htmlContent += @"
</body>
</html>
"@
        
        # Write HTML file
        $htmlContent | Out-File -FilePath $HtmlPath -Encoding UTF8
        
        Write-Host "📄 HTMLレポートが生成されました: $HtmlPath" -ForegroundColor Green
        return $true
        
    }
    catch {
        Write-Warning "HTMLレポートの生成に失敗しました: $($_.Exception.Message)"
        return $false
    }
}

# Determine test files based on parameters
$testFiles = @()
if ($TestPath) {
    $fullTestPath = Join-Path $PSScriptRoot $TestPath
    if (Test-Path $fullTestPath -PathType Leaf) {
        $testFiles = @($fullTestPath)
    }
    elseif (Test-Path $fullTestPath -PathType Container) {
        $testFiles = Get-ChildItem -Path $fullTestPath -Filter "*.Tests.ps1" -Recurse | Select-Object -ExpandProperty FullName
    }
    else {
        Write-Error "指定されたテストパスが見つかりません: $TestPath"
        exit 1
    }
}
elseif ($Layer) {
    $layerPath = Join-Path $PSScriptRoot "Utils\$Layer"
    if (Test-Path $layerPath) {
        $testFiles = Get-ChildItem -Path $layerPath -Filter "*.Tests.ps1" -Recurse | Select-Object -ExpandProperty FullName
        Write-Host "$Layer 層のテストを実行中..." -ForegroundColor Cyan
    }
    else {
        Write-Error "指定されたレイヤーが見つかりません: $Layer"
        exit 1
    }
}
else {
    # すべてのテストファイルを明示的に列挙
    $testFiles = Get-ChildItem -Path $PSScriptRoot -Filter "*.Tests.ps1" -Recurse | Select-Object -ExpandProperty FullName
}

Write-Host "実行対象のテストファイル数: $($testFiles.Count)" -ForegroundColor Green
if ($testFiles.Count -eq 0) {
    Write-Warning "実行するテストファイルが見つかりません。"
    exit 0
}

# Handle HTML format (convert to supported format)
$actualOutputFormat = $OutputFormat
$generateHtml = $false
if ($OutputFormat -eq "HTML") {
    $actualOutputFormat = "NUnitXml"  # Use NUnitXml as intermediate format
    $generateHtml = $true
    Write-Host "HTMLフォーマットが要求されました - NUnitXmlからHTMLを生成します" -ForegroundColor Yellow
}

# Test configuration with explicit file list to prevent duplicates
$testConfig = @{
    Run        = @{
        Path     = $testFiles
        PassThru = $true
    }
    Discovery  = @{
        ExcludeTagFilter = @()
    }
    Output     = @{
        Verbosity = 'Normal'
        CIFormat = 'None'
    }
    TestResult = @{
        Enabled      = $actualOutputFormat -ne "Console"
        OutputPath   = Join-Path $PSScriptRoot "TestResults.xml"
        OutputFormat = $actualOutputFormat
    }
}

# カバレッジ設定（要求された場合のみ）
if ($ShowCoverage) {
    $testConfig.CodeCoverage = @{
        Enabled      = $true
        Path         = @(
            (Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\main.ps1"),
            (Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\modules\**\*.psm1")
        )
        OutputPath   = Join-Path $PSScriptRoot "Coverage.xml"
        OutputFormat = "JaCoCo"
    }
}
else {
    # カバレッジを明示的に無効化
    $testConfig.CodeCoverage = @{
        Enabled = $false
    }
}

# Execute tests
Write-Host "テスト実行を開始します..." -ForegroundColor Cyan
Write-Host "実行予定テストファイル:" -ForegroundColor Yellow
foreach ($file in $testFiles) {
    $relativePath = [System.IO.Path]::GetRelativePath($PSScriptRoot, $file)
    Write-Host "  - $relativePath" -ForegroundColor Gray
}
Write-Host ""

# Execute tests and capture result without displaying object properties
Write-Host "テスト実行中..." -ForegroundColor Yellow
$testResult = Invoke-Pester -Configuration $testConfig
Write-Host "" # 改行を追加してテスト結果とその後の出力を分離

# Generate HTML report if requested
if ($generateHtml -and $testResult) {
    $htmlPath = Join-Path $PSScriptRoot "TestResults.html"
    $xmlPath = Join-Path $PSScriptRoot "TestResults.xml"
    
    if (Convert-TestResultToHtml -XmlPath $xmlPath -HtmlPath $htmlPath -TestResult $testResult) {
        Write-Host "✨ HTMLレポートの生成が完了しました" -ForegroundColor Green
        
        # Try to open HTML report in browser
        try {
            if ($IsWindows) {
                Start-Process $htmlPath
            }
            elseif ($IsMacOS) {
                & open $htmlPath
            }
            elseif ($IsLinux) {
                & xdg-open $htmlPath 2>/dev/null
            }
            Write-Host "🌐 ブラウザでレポートを開きました" -ForegroundColor Cyan
        }
        catch {
            Write-Host "📁 HTMLレポート: $htmlPath" -ForegroundColor Cyan
        }
    }
}

# Display results
Write-Host "`n" -NoNewline
Write-Host "======================== テスト結果 ========================" -ForegroundColor Cyan
Write-Host "実行されたテスト: " -NoNewline -ForegroundColor Yellow
Write-Host $testResult.TotalCount

Write-Host "成功: " -NoNewline -ForegroundColor Green
Write-Host $testResult.PassedCount

Write-Host "失敗: " -NoNewline -ForegroundColor Red
Write-Host $testResult.FailedCount

Write-Host "スキップ: " -NoNewline -ForegroundColor Yellow
Write-Host $testResult.SkippedCount

Write-Host "実行時間: " -NoNewline -ForegroundColor Magenta
Write-Host $testResult.Duration

# カバレッジ情報の表示
if ($ShowCoverage -and $testResult.CodeCoverage) {
    Write-Host "`nカバレッジ: " -NoNewline -ForegroundColor Cyan
    $coveragePercent = [Math]::Round(($testResult.CodeCoverage.CoveredPercent), 2)
    Write-Host "$coveragePercent%" -ForegroundColor $(if ($coveragePercent -gt 80) { "Green" } elseif ($coveragePercent -gt 60) { "Yellow" } else { "Red" })
}

# 終了コードの設定
if ($testResult.FailedCount -gt 0) {
    Write-Host "`n一部のテストが失敗しました。" -ForegroundColor Red
    exit 1
}
else {
    Write-Host "`nすべてのテストが成功しました。" -ForegroundColor Green
    exit 0
}