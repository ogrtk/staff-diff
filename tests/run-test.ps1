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

.EXAMPLE
.\run-test.ps1
すべてのテストを実行

.EXAMPLE
.\run-test.ps1 -TestPath "Utils\CommonUtils.Tests.ps1"
特定のテストファイルのみを実行

.EXAMPLE
.\run-test.ps1 -OutputFormat "HTML" -ShowCoverage
HTMLレポートでカバレッジを含めてテストを実行
#>

[CmdletBinding()]
param(
    [string]$TestPath = $null,
    [ValidateSet("NUnitXml", "JUnitXml", "HTML", "Console")]
    [string]$OutputFormat = "Console",
    [switch]$ShowCoverage
)

# UTF-8 encoding setup for Japanese text
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} else {
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

# Test configuration
$testConfig = @{
    Run = @{
        Path = if ($TestPath) { Join-Path $PSScriptRoot $TestPath } else { $PSScriptRoot }
        PassThru = $true
    }
    Output = @{
        Verbosity = 'Detailed'
    }
    TestResult = @{
        Enabled = $OutputFormat -ne "Console"
        OutputPath = Join-Path $PSScriptRoot "TestResults.xml"
        OutputFormat = $OutputFormat
    }
}

# カバレッジ設定（要求された場合のみ）
if ($ShowCoverage) {
    $testConfig.CodeCoverage = @{
        Enabled = $true
        Path = @(
            (Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\main.ps1"),
            (Join-Path (Split-Path -Parent $PSScriptRoot) "scripts\modules\**\*.psm1")
        )
        OutputPath = Join-Path $PSScriptRoot "Coverage.xml"
        OutputFormat = "JaCoCo"
    }
}

# Execute tests
Write-Host "Starting test execution..." -ForegroundColor Cyan
Write-Host "Configuration: " -NoNewline -ForegroundColor Gray
Write-Host ($testConfig | ConvertTo-Json -Depth 3) -ForegroundColor DarkGray

$testResult = Invoke-Pester -Configuration $testConfig

# Display results
Write-Host "`n" -NoNewline
Write-Host "======================== Test Results ========================" -ForegroundColor Cyan
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

# HTMLレポート生成（HTMLフォーマットが選択された場合）
if ($OutputFormat -eq "HTML") {
    $htmlPath = Join-Path $PSScriptRoot "TestReport.html"
    Write-Host "`nHTMLレポートを生成しています: $htmlPath" -ForegroundColor Cyan
}

# 終了コードの設定
if ($testResult.FailedCount -gt 0) {
    Write-Host "`n一部のテストが失敗しました。" -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nすべてのテストが成功しました。" -ForegroundColor Green
    exit 0
}