# PowerShell & SQLite データ同期システム
# テスト実行スクリプト

param(
    [string]$TestPath = "",
    [ValidateSet("All", "Unit", "Integration", "Foundation", "Infrastructure", "Process")]
    [string]$TestType = "All",
    [ValidateSet("NUnitXml", "HTML", "Console")]
    [string]$OutputFormat = "Console",
    [string]$OutputPath = "",
    [switch]$ShowCoverage,
    [switch]$Detailed,
    [switch]$SkipSlowTests
)

# スクリプトの場所を基準にプロジェクトルートを設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.FullName
$TestsRoot = $PSScriptRoot

# TestPathとTestTypeからテスト対象のパスを特定する統一関数
function Get-TestTargetPaths {
    param(
        [string]$TestPath,
        [string]$TestType,
        [string]$TestsRoot,
        [string]$ProjectRoot
    )
    
    $result = @{
        TestPaths        = @()
        IsSpecificFile   = $false
        ResolvedTestPath = ""
    }
    
    # 特定のテストパスが指定された場合
    if (-not [string]::IsNullOrEmpty($TestPath)) {
        $fullTestPath = if ([System.IO.Path]::IsPathRooted($TestPath)) {
            $TestPath
        }
        else {
            Join-Path $TestsRoot $TestPath
        }
        
        if (-not (Test-Path $fullTestPath)) {
            throw "指定されたテストパスが見つかりません: $fullTestPath"
        }
        
        $result.TestPaths = @($fullTestPath)
        $result.IsSpecificFile = $true
        $result.ResolvedTestPath = $fullTestPath
    }
    else {
        # TestTypeに基づくパス決定
        switch ($TestType) {
            "Unit" {
                $result.TestPaths = @(
                    (Join-Path $TestsRoot "Utils"),
                    (Join-Path $TestsRoot "Process")
                )
            }
            "Integration" {
                $result.TestPaths = @(Join-Path $TestsRoot "Integration")
            }
            "Foundation" {
                $result.TestPaths = @(Join-Path $TestsRoot "Utils" "Foundation")
            }
            "Infrastructure" {
                $result.TestPaths = @(Join-Path $TestsRoot "Utils" "Infrastructure")
            }
            "Process" {
                $result.TestPaths = @(Join-Path $TestsRoot "Process")
            }
            default {
                $result.TestPaths = @($TestsRoot)
            }
        }
        $result.IsSpecificFile = $false
    }
    
    return $result
}

# テスト結果からモジュール名を抽出（改良版）
function Get-ModuleNameFromTestResult {
    param(
        [Parameter(Mandatory = $true)]
        $TestObject,
        [Parameter(Mandatory = $false)]
        $TestTargets = $null
    )
    
    # ScriptBlockからファイルパスを取得を試行
    if ($TestObject.ScriptBlock -and $TestObject.ScriptBlock.File) {
        $filePath = $TestObject.ScriptBlock.File
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($filePath)
        if ($fileName.EndsWith(".Tests")) {
            return $fileName.Substring(0, $fileName.Length - 6)
        }
        else {
            return $fileName
        }
    }
    
    # TestTargetsから推測（設定されたパスから）
    if ($TestTargets -and $TestTargets.TestPaths) {
        foreach ($path in $TestTargets.TestPaths) {
            if (Test-Path $path -PathType Leaf) {
                # 単一ファイル
                $fileName = [System.IO.Path]::GetFileNameWithoutExtension($path)
                if ($fileName.EndsWith(".Tests")) {
                    return $fileName.Substring(0, $fileName.Length - 6)
                }
                else {
                    return $fileName
                }
            }
        }
    }
    
    # フォールバック: Path から最初の単語を取得
    if ($TestObject.Path) {
        $parts = $TestObject.Path -split '\s+'
        if ($parts.Count -gt 0) {
            $firstPart = $parts[0]
            # "モジュール" サフィックスを削除
            if ($firstPart.EndsWith("モジュール")) {
                return $firstPart.Substring(0, $firstPart.Length - 4)
            }
            else {
                return $firstPart
            }
        }
    }
    
    # 最終フォールバック
    return "不明"
}

# ファイルパスからモジュール名を抽出（シンプル版 - レガシー）
function Get-ModuleNameFromPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )
    
    # ファイルパスが実際のパスかどうかを確認
    if ([System.IO.Path]::IsPathRooted($FilePath) -or $FilePath.Contains('\') -or $FilePath.Contains('/')) {
        # 実際のファイルパス
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($FilePath)
    }
    else {
        # Path から最初の単語を取得
        $parts = $FilePath -split '\s+'
        if ($parts.Count -gt 0) {
            $firstPart = $parts[0]
            # "モジュール" サフィックスを削除
            if ($firstPart.EndsWith("モジュール")) {
                return $firstPart.Substring(0, $firstPart.Length - 4)
            }
            else {
                return $firstPart
            }
        }
        $fileName = $FilePath
    }
    
    # .Tests サフィックスを削除
    if ($fileName.EndsWith(".Tests")) {
        $result = $fileName.Substring(0, $fileName.Length - 6)
    }
    else {
        $result = $fileName
    }
    
    return $result
}

# Block情報から分類（Describe/Context）を取得
function Get-TestClassification {
    param(
        [Parameter(Mandatory = $true)]
        $TestObject
    )
    
    # Blockプロパティまたは階層情報から分類を取得
    if ($TestObject.Block) {
        return $TestObject.Block
    }
    elseif ($TestObject.ExpandedName) {
        # ExpandedNameから最初のDescribeブロック名を抽出
        $parts = $TestObject.ExpandedName -split '\.'
        if ($parts.Count -gt 1) {
            return $parts[0]
        }
    }
    elseif ($TestObject.Name) {
        # 他のプロパティから推測を試行
        $testName = $TestObject.Name
        if ($testName -match "^(.+?)\s+モジュール") {
            return $matches[1] + " モジュール"
        }
    }
    
    # デフォルト値
    return "テスト"
}

# テストファイルパスからモジュール名を抽出（レガシー関数 - 後方互換性のため保持）
function Get-ModuleNameFromTest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestPath
    )
    
    return Get-ModuleNameFromPath -FilePath $TestPath
}

# テストファイルから対応するモジュールファイルパスを取得
function Get-ModulePathFromTest {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestPath,
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )
    
    # ファイル名からモジュール名を抽出（.Tests サフィックスを削除）
    $fileName = [System.IO.Path]::GetFileNameWithoutExtension($TestPath)
    if ($fileName.EndsWith(".Tests")) {
        $moduleName = $fileName.Substring(0, $fileName.Length - 6) + ".psm1"
    }
    else {
        $moduleName = $fileName + ".psm1"
    }
    
    # テストファイルのディレクトリ構造から対応するモジュールパスを特定
    $testsRoot = Join-Path $ProjectRoot "tests"
    $relativePath = $TestPath -replace [regex]::Escape($testsRoot), ""
    $relativePath = $relativePath.TrimStart("\", "/").Replace("\", "/")
    
    $moduleBasePath = Join-Path $ProjectRoot "scripts" "modules"
    
    
    if ($relativePath -match "^Integration") {
        # 統合テストの場合、すべてのモジュールが対象なので空を返す
        return $null
    }
    elseif ($relativePath -match "^Process") {
        return Join-Path $moduleBasePath "Process" $moduleName
    }
    elseif ($relativePath -match "^Utils/Foundation") {
        return Join-Path $moduleBasePath "Utils" "Foundation" $moduleName
    }
    elseif ($relativePath -match "^Utils/Infrastructure") {
        return Join-Path $moduleBasePath "Utils" "Infrastructure" $moduleName
    }
    elseif ($relativePath -match "^Utils/DataAccess") {
        return Join-Path $moduleBasePath "Utils" "DataAccess" $moduleName
    }
    elseif ($relativePath -match "^Utils/DataProcessing") {
        return Join-Path $moduleBasePath "Utils" "DataProcessing" $moduleName
    }
    elseif ($relativePath -match "^Utils") {
        return Join-Path $moduleBasePath "Utils" $moduleName
    }
    else {
        return $null
    }
}

# テスト対象に基づくカバレッジファイル特定関数
function Get-CoverageFilePaths {
    param(
        [string]$ProjectRoot,
        [hashtable]$TestTargets
    )
    
    $coveragePaths = @()
    $utilsPath = Join-Path $ProjectRoot "scripts" "modules" "Utils"
    $processPath = Join-Path $ProjectRoot "scripts" "modules" "Process"
    
    # 特定のテストファイルが指定された場合
    if ($TestTargets.IsSpecificFile) {
        $targetModulePath = Get-ModulePathFromTest -TestPath $TestTargets.ResolvedTestPath -ProjectRoot $ProjectRoot
        if ($targetModulePath -and (Test-Path $targetModulePath)) {
            $coveragePaths += $targetModulePath
        }
    }
    # TestTypeに基づく絞り込み（$TestTargets.TestPathsから推定）
    else {
        # TestPathsからTestTypeを推定
        $firstTestPath = $TestTargets.TestPaths[0]
        $testType = ""
        
        if ($firstTestPath -match "\\Utils\\Foundation$" -or $firstTestPath -match "/Utils/Foundation$") {
            $testType = "Foundation"
        }
        elseif ($firstTestPath -match "\\Utils\\Infrastructure$" -or $firstTestPath -match "/Utils/Infrastructure$") {
            $testType = "Infrastructure"
        }
        elseif ($firstTestPath -match "\\Process$" -or $firstTestPath -match "/Process$") {
            $testType = "Process"
        }
        elseif ($firstTestPath -match "\\Integration$" -or $firstTestPath -match "/Integration$") {
            $testType = "Integration"
        }
        elseif ($TestTargets.TestPaths.Count -eq 2 -and 
                ($TestTargets.TestPaths -contains (Join-Path $TestsRoot "Utils")) -and 
                ($TestTargets.TestPaths -contains (Join-Path $TestsRoot "Process"))) {
            $testType = "Unit"
        }
        else {
            $testType = "All"
        }
        
        switch ($testType) {
            "Foundation" {
                $foundationPath = Join-Path $utilsPath "Foundation"
                if (Test-Path $foundationPath) {
                    $foundationFiles = Get-ChildItem -Path $foundationPath -Filter "*.psm1" | Select-Object -ExpandProperty FullName
                    $coveragePaths += $foundationFiles
                }
            }
            "Infrastructure" {
                $infrastructurePath = Join-Path $utilsPath "Infrastructure"
                if (Test-Path $infrastructurePath) {
                    $infrastructureFiles = Get-ChildItem -Path $infrastructurePath -Filter "*.psm1" | Select-Object -ExpandProperty FullName
                    $coveragePaths += $infrastructureFiles
                }
            }
            "Process" {
                if (Test-Path $processPath) {
                    $processFiles = Get-ChildItem -Path $processPath -Filter "*.psm1" | Select-Object -ExpandProperty FullName
                    $coveragePaths += $processFiles
                }
            }
            "Unit" {
                # Unit = Utils (Foundation + Infrastructure + DataAccess + DataProcessing)
                if (Test-Path $utilsPath) {
                    $utilsFiles = Get-ChildItem -Path $utilsPath -Recurse -Filter "*.psm1" | Select-Object -ExpandProperty FullName
                    $coveragePaths += $utilsFiles
                }
                if (Test-Path $processPath) {
                    $processFiles = Get-ChildItem -Path $processPath -Filter "*.psm1" | Select-Object -ExpandProperty FullName
                    $coveragePaths += $processFiles
                }
            }
            default {
                # All または Integration の場合はすべてのファイル
                if (Test-Path $utilsPath) {
                    $utilsFiles = Get-ChildItem -Path $utilsPath -Recurse -Filter "*.psm1" | Select-Object -ExpandProperty FullName
                    $coveragePaths += $utilsFiles
                }
                if (Test-Path $processPath) {
                    $processFiles = Get-ChildItem -Path $processPath -Filter "*.psm1" | Select-Object -ExpandProperty FullName
                    $coveragePaths += $processFiles
                }
            }
        }
    }
    
    Write-Host "カバレッジ対象ファイル数: $($coveragePaths.Count)" -ForegroundColor Yellow
    foreach ($path in $coveragePaths) {
        Write-Host "  - $path" -ForegroundColor Gray
    }
    
    return $coveragePaths
}

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
        [string]$TestPath,
        [string]$TestType,
        [string]$OutputFormat,
        [string]$OutputPath,
        [bool]$ShowCoverage,
        [bool]$SkipSlowTests,
        [string]$ProjectRoot,
        [bool]$Detailed
    )
    
    # Pester 5.x の設定
    $config = New-PesterConfiguration
    
    # テスト対象パスを統一関数で取得
    $testTargets = Get-TestTargetPaths -TestPath $TestPath -TestType $TestType -TestsRoot $TestsRoot -ProjectRoot $ProjectRoot
    $config.Run.Path = $testTargets.TestPaths
    
    # 特定ファイル実行時のメッセージ表示
    if ($testTargets.IsSpecificFile) {
        Write-Host "特定のテストを実行中: $($testTargets.ResolvedTestPath)" -ForegroundColor Yellow
    }
    else {
        Write-Host "テストタイプ: $TestType" -ForegroundColor Yellow
    }
    
    # 出力設定
    $config.Output.Verbosity = if ($Detailed) { "Detailed" } else { "Normal" }
        
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
    }
    
    # カバレッジ設定
    if ($ShowCoverage) {
        $config.CodeCoverage.Enabled = $true
        $coveragePaths = Get-CoverageFilePaths -ProjectRoot $ProjectRoot -TestTargets $TestTargets
        $config.CodeCoverage.Path = $coveragePaths
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
        [string]$OutputPath,
        $TestTargets = $null
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
            <tr><td>実行時間</td><td>$(if ($TestResult.Duration) { $TestResult.Duration.ToString("mm\:ss\.fff") } else { "00:00.000" })</td></tr>
        </table>
    </div>
    
    <div class="module-summary">
        <h3>モジュール別実行結果</h3>
        <table>
            <tr><th>モジュール</th><th>総数</th><th>成功</th><th>失敗</th><th>スキップ</th><th>実行時間</th></tr>
"@

    # モジュール別統計を集計（分類は除外し、モジュール単位で集計）
    $moduleStats = @{}
    foreach ($test in $TestResult.Tests) {
        $moduleName = Get-ModuleNameFromTestResult -TestObject $test -TestTargets $testTargets
        
        if (-not $moduleStats.ContainsKey($moduleName)) {
            $moduleStats[$moduleName] = @{
                Total   = 0
                Passed  = 0
                Failed  = 0
                Skipped = 0
                Time    = [TimeSpan]::Zero
            }
        }
        
        $moduleStats[$moduleName].Total++
        if ($test.Duration) {
            $moduleStats[$moduleName].Time = $moduleStats[$moduleName].Time.Add($test.Duration)
        }
        
        switch ($test.Result) {
            "Passed" { $moduleStats[$moduleName].Passed++ }
            "Failed" { $moduleStats[$moduleName].Failed++ }
            "Skipped" { $moduleStats[$moduleName].Skipped++ }
        }
    }
    
    foreach ($moduleName in ($moduleStats.Keys | Sort-Object)) {
        $stats = $moduleStats[$moduleName]
        $htmlContent += @"
            <tr>
                <td>$moduleName</td>
                <td>$($stats.Total)</td>
                <td class="passed">$($stats.Passed)</td>
                <td class="failed">$($stats.Failed)</td>
                <td class="skipped">$($stats.Skipped)</td>
                <td>$($stats.Time.ToString("mm\:ss\.fff"))</td>
            </tr>
"@
    }
    
    $htmlContent += @"
        </table>
    </div>
"@

    if ($TestResult.Failed.Count -gt 0) {
        $htmlContent += @"
    <div class="test-details">
        <h3>失敗したテスト</h3>
"@
        foreach ($failedTest in $TestResult.Failed) {
            $moduleName = Get-ModuleNameFromTestResult -TestObject $failedTest -TestTargets $testTargets
            $classification = Get-TestClassification -TestObject $failedTest
            $htmlContent += @"
        <div class="test-container">
            <div class="test-name">[$moduleName] $classification - $($failedTest.Name)</div>
            <div class="test-time">実行時間: $(if ($failedTest.Duration) { $failedTest.Duration.ToString("mm\:ss\.fff") } else { "00:00.000" })</div>
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
                <th>モジュール</th>
                <th>分類</th>
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
        
        $moduleName = Get-ModuleNameFromTestResult -TestObject $test -TestTargets $testTargets
        $classification = Get-TestClassification -TestObject $test
        
        $htmlContent += @"
            <tr>
                <td>$moduleName</td>
                <td>$classification</td>
                <td>$($test.Name)</td>
                <td class="$statusClass">$($test.Result)</td>
                <td>$(if ($test.Duration) { $test.Duration.ToString("mm\:ss\.fff") } else { "00:00.000" })</td>
                <td>$details</td>
            </tr>
"@
    }
    
    $htmlContent += @"
        </table>
    </div>
"@

    # カバレッジ情報の追加（すべてのテスト結果の後）
    if ($null -ne $TestResult.CodeCoverage) {
        $coverage = $TestResult.CodeCoverage
        $coveragePercent = $coverage.CoveragePercent
        $executedCount = if ($coverage.CommandsExecuted) { $coverage.CommandsExecuted.Count } else { 0 }
        $missedCount = if ($coverage.CommandsMissed) { $coverage.CommandsMissed.Count } else { 0 }
        $totalAnalyzed = $executedCount + $missedCount
        
        $htmlContent += @"
    <div class="coverage-summary" style="margin-top: 30px; border-top: 3px solid #2196F3; padding-top: 20px;">
        <h2 style="color: #2196F3; border-bottom: 2px solid #2196F3; padding-bottom: 10px;">📊 コードカバレッジレポート</h2>
        <table>
            <tr><th>項目</th><th>値</th></tr>
            <tr><td>カバレッジ率</td><td>$([math]::Round($coveragePercent, 2))%</td></tr>
            <tr><td>実行されたコマンド</td><td>$executedCount</td></tr>
            <tr><td>解析されたコマンド</td><td>$totalAnalyzed</td></tr>
            <tr><td>未実行のコマンド</td><td>$missedCount</td></tr>
        </table>
        <p style="font-size: 0.9em; color: #666;">※ Pester 5.xでは「コマンド」単位で測定（行単位ではない）</p>
    </div>
    
    <div class="file-coverage">
        <h3 style="color: #2196F3;">📁 ファイル別カバレッジ詳細</h3>
        <table>
            <tr>
                <th>ファイル</th>
                <th>解析コマンド数</th>
                <th>実行コマンド数</th>
                <th>未実行コマンド数</th>
                <th>カバレッジ率</th>
            </tr>
"@

        # ファイル別カバレッジの計算
        $fileStats = @{}
        
        # 実行されたコマンドの集計
        if ($coverage.CommandsExecuted) {
            foreach ($cmd in $coverage.CommandsExecuted) {
                $file = $cmd.File
                if (-not $fileStats.ContainsKey($file)) {
                    $fileStats[$file] = @{ Executed = 0; Missed = 0 }
                }
                $fileStats[$file].Executed++
            }
        }
        
        # 未実行コマンドの集計
        if ($coverage.CommandsMissed) {
            foreach ($cmd in $coverage.CommandsMissed) {
                $file = $cmd.File
                if (-not $fileStats.ContainsKey($file)) {
                    $fileStats[$file] = @{ Executed = 0; Missed = 0 }
                }
                $fileStats[$file].Missed++
            }
        }
        
        # ファイル別統計の表示
        foreach ($file in ($fileStats.Keys | Sort-Object)) {
            $stats = $fileStats[$file]
            $totalCommands = $stats.Executed + $stats.Missed
            $fileCoveragePercent = if ($totalCommands -gt 0) { 
                [math]::Round(($stats.Executed / $totalCommands) * 100, 2) 
            }
            else { 
                0 
            }
            
            # ファイル名を短縮表示（プロジェクトルートからの相対パス）
            $relativePath = $file -replace [regex]::Escape($ProjectRoot), ""
            $relativePath = $relativePath.TrimStart("\", "/")
            
            $htmlContent += @"
            <tr>
                <td>$relativePath</td>
                <td>$totalCommands</td>
                <td>$($stats.Executed)</td>
                <td>$($stats.Missed)</td>
                <td>$fileCoveragePercent%</td>
            </tr>
"@
        }
        
        $htmlContent += @"
        </table>
    </div>
"@

        # 未実行コマンドの詳細表示（すべて表示）
        $missedCommands = if ($coverage.CommandsMissed) { $coverage.CommandsMissed } else { @() }
        if ($missedCommands.Count -gt 0) {
            $htmlContent += @"
    <div class="missed-commands">
        <h3 style="color: #ff9800;">⚠️ 未実行コマンド詳細（全 $($missedCommands.Count) 個）</h3>
        <table>
            <tr>
                <th>ファイル</th>
                <th>行番号</th>
                <th>コマンド</th>
            </tr>
"@
            
            # すべての未実行コマンドを表示
            foreach ($cmd in $missedCommands) {
                $relativePath = $cmd.File -replace [regex]::Escape($ProjectRoot), ""
                $relativePath = $relativePath.TrimStart("\", "/")
                $command = if ($cmd.Command) { $cmd.Command } else { "不明" }
                
                $htmlContent += @"
            <tr>
                <td>$relativePath</td>
                <td>$($cmd.Line)</td>
                <td style="font-family: monospace; font-size: 0.9em;">$command</td>
            </tr>
"@
            }
            
            $htmlContent += @"
        </table>
    </div>
"@
        }
    }

    $htmlContent += @"
</body>
</html>
"@
    
    $htmlContent | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "HTMLレポートを生成しました: $OutputPath" -ForegroundColor Green
}

# メイン処理
function Invoke-TestExecution {
    param(
        [string]$TestPath = $TestPath,
        [string]$TestType = $TestType,
        [string]$OutputFormat = $OutputFormat,
        [string]$OutputPath = $OutputPath,
        [switch]$ShowCoverage = $ShowCoverage,
        [switch]$Detailed = $Detailed,
        [switch]$SkipSlowTests = $SkipSlowTests
    )
    Write-Host "=== PowerShell & SQLite データ同期システム テスト実行 ===" -ForegroundColor Cyan
    Write-Host "プロジェクトルート: $ProjectRoot" -ForegroundColor Gray
    Write-Host "テストルート: $TestsRoot" -ForegroundColor Gray
    Write-Host ""
    
        
    try {
        # 必要なモジュールのインストール
        Install-RequiredModules

        # Pester設定の初期化
        $config = Initialize-PesterConfiguration -TestPath $TestPath -TestType $TestType -OutputFormat $OutputFormat -OutputPath $OutputPath -ShowCoverage $ShowCoverage -SkipSlowTests $SkipSlowTests -ProjectRoot $ProjectRoot -Detailed $Detailed
    
        Write-Host "テストを開始します..." -ForegroundColor Green
        $startTime = Get-Date

        # テストを実行
        $result = Invoke-Pester -Configuration $config
        
        $endTime = Get-Date
        $totalDuration = $endTime - $startTime

        # コンソールへの結果表示
        Write-Host ""
        Write-Host "=== テスト実行完了 ===" -ForegroundColor Cyan
        Write-Host "総実行時間: $($totalDuration.TotalSeconds) 秒" -ForegroundColor Gray
        Write-Host "総テスト数: $($result.TotalCount)" -ForegroundColor White
        Write-Host "成功: $($result.PassedCount)" -ForegroundColor Green
        Write-Host "失敗: $($result.FailedCount)" -ForegroundColor Red
        Write-Host "スキップ: $($result.SkippedCount)" -ForegroundColor Yellow
        
        # HTML レポートの生成
        if ($OutputFormat -eq "HTML") {
            Write-Host "pass"
            if ([string]::IsNullOrEmpty($OutputPath)) {
                $OutputPath = Join-Path $TestsRoot "TestResults.html"
            }
            New-HtmlReport -TestResult $result -OutputPath $OutputPath -TestTargets $testTargets
        }

        # カバレッジ情報の表示
        if ($ShowCoverage) {
            Write-Host ""
            Write-Host "=== コードカバレッジ ===" -ForegroundColor Cyan

            if ($null -ne $result.CodeCoverage) {
                # Pester 5.x のプロパティ名を使用
                $coveragePercent = $result.CodeCoverage.CoveragePercent
                $executedCount = if ($result.CodeCoverage.CommandsExecuted) { $result.CodeCoverage.CommandsExecuted.Count } else { 0 }
                $missedCount = if ($result.CodeCoverage.CommandsMissed) { $result.CodeCoverage.CommandsMissed.Count } else { 0 }
                
                # 解析されたコマンド総数は、実行されたコマンド + 未実行のコマンド
                $totalAnalyzed = $executedCount + $missedCount
                
                Write-Host "カバレッジ率: $([math]::Round($coveragePercent, 2))%" -ForegroundColor White
                Write-Host "実行されたコマンド: $executedCount" -ForegroundColor Green
                Write-Host "解析されたコマンド: $totalAnalyzed" -ForegroundColor White
                Write-Host "未実行のコマンド: $missedCount" -ForegroundColor Yellow
                Write-Host "注意: Pester 5.xでは「コマンド」単位で測定（行単位ではない）" -ForegroundColor Gray
                
                # 解析されたファイル情報
                if ($result.CodeCoverage.FilesAnalyzed) {
                    Write-Host "解析されたファイル数: $($result.CodeCoverage.FilesAnalyzed.Count)" -ForegroundColor Cyan
                }
            }
            else {
                Write-Host "CodeCoverageオブジェクトがnullです" -ForegroundColor Red
            }
            
            # 未実行コマンドの表示（Pester 5.x では CommandsMissed）
            $missedCommands = if ($result.CodeCoverage.CommandsMissed) { $result.CodeCoverage.CommandsMissed } else { @() }
            if ($missedCommands.Count -gt 0) {
                Write-Host "未実行のコマンドがあります:" -ForegroundColor Yellow
                foreach ($missedCommand in $missedCommands | Select-Object -First 10) {
                    Write-Host "  $($missedCommand.File):$($missedCommand.Line)" -ForegroundColor Yellow
                }
                if ($missedCommands.Count -gt 10) {
                    Write-Host "  ... 他 $($missedCommands.Count - 10) 行" -ForegroundColor Yellow
                }
            }
        }

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
Invoke-TestExecution -TestPath $TestPath -TestType $TestType -OutputFormat $OutputFormat -OutputPath $OutputPath -ShowCoverage:$ShowCoverage -Detailed:$Detailed -SkipSlowTests:$SkipSlowTests