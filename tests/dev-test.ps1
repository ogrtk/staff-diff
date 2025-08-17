#!/usr/bin/env pwsh
# -*- coding: utf-8 -*-
<#
.SYNOPSIS
開発者向けテスト実行スクリプト

.DESCRIPTION
開発時によく使用するテストパターンを簡単に実行できるヘルパースクリプトです。
レイヤー別テスト、クイックテスト、詳細テストなどを提供します。

.PARAMETER Mode
実行モード。quick, layer, full, debug, performance から選択

.PARAMETER Layer  
レイヤー指定時のレイヤー名

.PARAMETER Module
特定モジュールのテスト実行時のモジュール名

.PARAMETER Watch
ファイル変更を監視してテストを自動実行

.EXAMPLE
./dev-test.ps1 -Mode quick
クイックテスト（Foundation層のみ）を実行

.EXAMPLE  
./dev-test.ps1 -Mode layer -Layer "DataProcessing"
DataProcessing層のテストを実行

.EXAMPLE
./dev-test.ps1 -Mode debug -Module "CoreUtils"
CoreUtilsモジュールのデバッグテストを実行

.EXAMPLE
./dev-test.ps1 -Mode full -Watch
全テストを実行し、ファイル変更を監視
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("quick", "layer", "full", "debug", "performance", "coverage")]
    [string]$Mode,
    
    [ValidateSet("Foundation", "Infrastructure", "DataAccess", "DataProcessing")]
    [string]$Layer,
    
    [string]$Module,
    
    [switch]$Watch,
    
    [switch]$VerboseOutput
)

# UTF-8エンコーディングの設定
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
} else {
    $OutputEncoding = [System.Text.UTF8Encoding]::UTF8
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::UTF8
}

function Write-DevLog {
    param(
        [string]$Message,
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $color = switch ($Level) {
        "Info" { "White" }
        "Success" { "Green" }
        "Warning" { "Yellow" }
        "Error" { "Red" }
        "Debug" { "Cyan" }
        default { "White" }
    }
    
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor Gray
    Write-Host $Message -ForegroundColor $color
}

function Invoke-QuickTest {
    Write-DevLog "🚀 クイックテスト実行中..." -Level "Info"
    Write-DevLog "Foundation層のテストを実行します" -Level "Debug"
    
    $result = & "$PSScriptRoot/run-test.ps1" -Layer "Foundation" -OutputFormat "Console"
    
    if ($LASTEXITCODE -eq 0) {
        Write-DevLog "✅ クイックテスト完了" -Level "Success"
    } else {
        Write-DevLog "❌ クイックテストで問題が見つかりました" -Level "Error"
    }
    
    return $result
}

function Invoke-LayerTest {
    param([string]$LayerName)
    
    Write-DevLog "🏗️ $LayerName 層テスト実行中..." -Level "Info"
    
    $result = & "$PSScriptRoot/run-test.ps1" -Layer $LayerName -OutputFormat "Console"
    
    if ($LASTEXITCODE -eq 0) {
        Write-DevLog "✅ $LayerName 層テスト完了" -Level "Success"
    } else {
        Write-DevLog "❌ $LayerName 層テストで問題が見つかりました" -Level "Error"
    }
    
    return $result
}

function Invoke-FullTest {
    Write-DevLog "🌟 フルテスト実行中..." -Level "Info"
    
    $layers = @("Foundation", "Infrastructure", "DataAccess", "DataProcessing")
    $overallSuccess = $true
    
    foreach ($layer in $layers) {
        Write-DevLog "📋 $layer 層テスト開始" -Level "Debug"
        
        $result = & "$PSScriptRoot/run-test.ps1" -Layer $layer -OutputFormat "Console"
        
        if ($LASTEXITCODE -ne 0) {
            $overallSuccess = $false
            Write-DevLog "⚠️ $layer 層でエラーが発生しました" -Level "Warning"
        } else {
            Write-DevLog "✅ $layer 層テスト完了" -Level "Success"
        }
    }
    
    # Process, Integration, Feature テスト
    Write-DevLog "📋 プロセステスト開始" -Level "Debug"
    & "$PSScriptRoot/run-test.ps1" -TestPath "Process" -OutputFormat "Console"
    if ($LASTEXITCODE -ne 0) { $overallSuccess = $false }
    
    Write-DevLog "📋 統合テスト開始" -Level "Debug"
    & "$PSScriptRoot/run-test.ps1" -TestPath "Integration" -OutputFormat "Console"
    if ($LASTEXITCODE -ne 0) { $overallSuccess = $false }
    
    Write-DevLog "📋 機能テスト開始" -Level "Debug"
    & "$PSScriptRoot/run-test.ps1" -TestPath "Feature" -OutputFormat "Console"
    if ($LASTEXITCODE -ne 0) { $overallSuccess = $false }
    
    if ($overallSuccess) {
        Write-DevLog "🎉 すべてのテストが成功しました！" -Level "Success"
    } else {
        Write-DevLog "💥 一部のテストで問題が見つかりました" -Level "Error"
    }
}

function Invoke-DebugTest {
    param([string]$ModuleName)
    
    if (-not $ModuleName) {
        Write-DevLog "❌ デバッグモードではモジュール名の指定が必要です" -Level "Error"
        return
    }
    
    Write-DevLog "🔍 $ModuleName モジュールのデバッグテスト実行中..." -Level "Info"
    
    # モジュールのテストファイルを検索
    $testFiles = Get-ChildItem -Path "$PSScriptRoot/Utils" -Recurse -Filter "*$ModuleName.Tests.ps1"
    
    if (-not $testFiles) {
        Write-DevLog "❌ $ModuleName のテストファイルが見つかりません" -Level "Error"
        return
    }
    
    foreach ($testFile in $testFiles) {
        Write-DevLog "🧪 テストファイル: $($testFile.Name)" -Level "Debug"
        
        # Pesterの詳細出力でテスト実行
        $testPath = $testFile.FullName.Replace($PSScriptRoot + [System.IO.Path]::DirectorySeparatorChar, "")
        
        if ($VerboseOutput) {
            pwsh -Command "Invoke-Pester '$($testFile.FullName)' -Output Detailed"
        } else {
            & "$PSScriptRoot/run-test.ps1" -TestPath $testPath -OutputFormat "Console"
        }
    }
}

function Invoke-PerformanceTest {
    Write-DevLog "⚡ パフォーマンステスト実行中..." -Level "Info"
    
    # 大量データテストファイルの作成
    Write-DevLog "📊 テストデータ生成中..." -Level "Debug"
    if (Test-Path "$PSScriptRoot/create-utf8-tests.ps1") {
        & "$PSScriptRoot/create-utf8-tests.ps1"
    }
    
    # メモリ使用量の測定開始
    $initialMemory = [GC]::GetTotalMemory($false)
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    
    # 統合テストでパフォーマンス測定
    Write-DevLog "🏃 統合テスト実行中..." -Level "Debug"
    & "$PSScriptRoot/run-test.ps1" -TestPath "Integration/FullSystem.Tests.ps1" -ShowCoverage
    
    $stopwatch.Stop()
    [GC]::Collect()
    $finalMemory = [GC]::GetTotalMemory($true)
    
    # 結果の表示
    $durationSeconds = $stopwatch.Elapsed.TotalSeconds
    $memoryUsedMB = ($finalMemory - $initialMemory) / 1MB
    
    Write-DevLog "📈 パフォーマンス結果:" -Level "Info"
    Write-DevLog "  実行時間: $([math]::Round($durationSeconds, 2)) 秒" -Level "Info"
    Write-DevLog "  メモリ使用量: $([math]::Round($memoryUsedMB, 2)) MB" -Level "Info"
    
    # パフォーマンス基準の確認
    if ($durationSeconds -gt 120) {  # 2分
        Write-DevLog "⚠️ 実行時間が長すぎます (>2分)" -Level "Warning"
    }
    
    if ($memoryUsedMB -gt 100) {  # 100MB
        Write-DevLog "⚠️ メモリ使用量が多すぎます (>100MB)" -Level "Warning"
    }
    
    if ($durationSeconds -le 60 -and $memoryUsedMB -le 50) {
        Write-DevLog "🎯 パフォーマンス良好！" -Level "Success"
    }
}

function Invoke-CoverageTest {
    Write-DevLog "📊 カバレッジテスト実行中..." -Level "Info"
    
    # HTMLレポート付きでカバレッジテスト実行
    & "$PSScriptRoot/run-test.ps1" -OutputFormat "HTML" -ShowCoverage
    
    # カバレッジ結果の確認
    if (Test-Path "$PSScriptRoot/TestResults.html") {
        Write-DevLog "📄 HTMLレポートが生成されました: tests/TestResults.html" -Level "Success"
        
        # プラットフォーム別でHTMLファイルを開く
        $htmlPath = Resolve-Path "$PSScriptRoot/TestResults.html"
        try {
            if ($IsWindows) {
                Start-Process $htmlPath
            } elseif ($IsMacOS) {
                & open $htmlPath
            } elseif ($IsLinux) {
                & xdg-open $htmlPath
            }
            Write-DevLog "🌐 ブラウザでレポートを開きました" -Level "Info"
        } catch {
            Write-DevLog "📁 レポートファイル: $htmlPath" -Level "Info"
        }
    }
}

function Start-FileWatcher {
    Write-DevLog "👀 ファイル変更監視を開始します..." -Level "Info"
    Write-DevLog "Ctrl+C で監視を停止" -Level "Debug"
    
    # FileSystemWatcherの設定
    $watcher = New-Object System.IO.FileSystemWatcher
    $watcher.Path = Split-Path $PSScriptRoot -Parent
    $watcher.Filter = "*.ps1"
    $watcher.IncludeSubdirectories = $true
    $watcher.EnableRaisingEvents = $true
    
    # イベントハンドラーの登録
    $action = {
        $path = $Event.SourceEventArgs.FullPath
        $changeType = $Event.SourceEventArgs.ChangeType
        $fileName = Split-Path $path -Leaf
        
        if ($fileName -match "(\.Tests\.ps1|\.psm1)$") {
            Write-DevLog "📝 ファイル変更検出: $fileName ($changeType)" -Level "Debug"
            
            Start-Sleep -Seconds 2  # 変更が完了するまで待機
            
            # 変更されたファイルに応じてテストを実行
            if ($fileName -match "CoreUtils") {
                Invoke-LayerTest -LayerName "Foundation"
            } elseif ($fileName -match "(Configuration|Logging|ErrorHandling)Utils") {
                Invoke-LayerTest -LayerName "Infrastructure"
            } elseif ($fileName -match "(Database|FileSystem)Utils") {
                Invoke-LayerTest -LayerName "DataAccess"
            } elseif ($fileName -match "(CsvProcessing|DataFiltering)Utils") {
                Invoke-LayerTest -LayerName "DataProcessing"
            } else {
                Invoke-QuickTest
            }
        }
    }
    
    Register-ObjectEvent -InputObject $watcher -EventName Created -Action $action
    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $action
    
    try {
        while ($true) {
            Start-Sleep -Seconds 1
        }
    } finally {
        $watcher.EnableRaisingEvents = $false
        $watcher.Dispose()
        Write-DevLog "🛑 ファイル監視を停止しました" -Level "Info"
    }
}

# メイン実行ロジック
Write-DevLog "🎯 開発者テストツール - モード: $Mode" -Level "Info"

try {
    switch ($Mode) {
        "quick" {
            Invoke-QuickTest
        }
        "layer" {
            if (-not $Layer) {
                Write-DevLog "❌ レイヤーモードではレイヤー名の指定が必要です (-Layer)" -Level "Error"
                exit 1
            }
            Invoke-LayerTest -LayerName $Layer
        }
        "full" {
            Invoke-FullTest
        }
        "debug" {
            Invoke-DebugTest -ModuleName $Module
        }
        "performance" {
            Invoke-PerformanceTest
        }
        "coverage" {
            Invoke-CoverageTest
        }
    }
    
    # ファイル監視モードの開始
    if ($Watch) {
        Start-FileWatcher
    }
    
} catch {
    Write-DevLog "💥 エラーが発生しました: $($_.Exception.Message)" -Level "Error"
    if ($VerboseOutput) {
        Write-DevLog "スタックトレース: $($_.ScriptStackTrace)" -Level "Debug"
    }
    exit 1
}

Write-DevLog "🏁 テスト実行完了" -Level "Success"