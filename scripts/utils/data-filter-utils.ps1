# PowerShell & SQLite データ同期システム
# データフィルタリングユーティリティライブラリ

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")

# データフィルタリングの実行（最適化版）
function Test-DataFilter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$DataRow,
        
        [ref]$ExclusionReason
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    # フィルタリングが無効または設定されていない場合は通す
    if (-not $filterConfig -or -not $filterConfig.enabled) {
        return $true
    }
    
    # 各フィルタルールをチェック
    foreach ($rule in $filterConfig.rules) {
        $fieldValue = $DataRow[$rule.field]
        
        if (-not $fieldValue) {
            continue
        }
        
        switch ($rule.type) {
            "exclude_pattern" {
                if ($fieldValue -match $rule.pattern) {
                    $ExclusionReason.Value = "$($rule.field)='$fieldValue' (理由: $($rule.description))"
                    return $false
                }
            }
            "include_pattern" {
                if ($fieldValue -notmatch $rule.pattern) {
                    $ExclusionReason.Value = "$($rule.field)='$fieldValue' (理由: $($rule.description))"
                    return $false
                }
            }
            "exclude_value" {
                if ($fieldValue -eq $rule.value) {
                    $ExclusionReason.Value = "$($rule.field)='$fieldValue' (理由: $($rule.description))"
                    return $false
                }
            }
            "include_value" {
                if ($fieldValue -ne $rule.value) {
                    $ExclusionReason.Value = "$($rule.field)='$fieldValue' (理由: $($rule.description))"
                    return $false
                }
            }
        }
    }
    
    return $true
}

# フィルタリング統計の取得
function Get-FilterStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalCount,
        
        [Parameter(Mandatory = $true)]
        [int]$FilteredCount
    )
    
    $excludedCount = $TotalCount - $FilteredCount
    $exclusionRate = if ($TotalCount -gt 0) { [Math]::Round(($excludedCount / $TotalCount) * 100, 2) } else { 0 }
    
    return @{
        TableName     = $TableName
        TotalCount    = $TotalCount
        FilteredCount = $FilteredCount
        ExcludedCount = $excludedCount
        ExclusionRate = $exclusionRate
    }
}

# フィルタ設定の表示
function Show-FilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    if (-not $filterConfig) {
        Write-Host "テーブル '$TableName' にフィルタ設定がありません" -ForegroundColor Yellow
        return
    }
    
    Write-Host "=== フィルタ設定: $TableName ===" -ForegroundColor Cyan
    Write-Host "有効: $($filterConfig.enabled)" -ForegroundColor Green
    
    if ($filterConfig.rules -and $filterConfig.rules.Count -gt 0) {
        Write-Host "ルール数: $($filterConfig.rules.Count)" -ForegroundColor Green
        
        for ($i = 0; $i -lt $filterConfig.rules.Count; $i++) {
            $rule = $filterConfig.rules[$i]
            Write-Host "  [$($i + 1)] フィールド: $($rule.field)" -ForegroundColor White
            Write-Host "       タイプ: $($rule.type)" -ForegroundColor White
            
            if ($rule.pattern) {
                Write-Host "       パターン: $($rule.pattern)" -ForegroundColor White
            }
            if ($rule.value) {
                Write-Host "       値: $($rule.value)" -ForegroundColor White
            }
            
            Write-Host "       説明: $($rule.description)" -ForegroundColor Gray
        }
    }
    else {
        Write-Host "ルールが設定されていません" -ForegroundColor Yellow
    }
}

# データフィルタリングの実行（配列対応）
function Invoke-DataFiltering {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [array]$DataArray,
        
        [bool]$ShowStatistics = $true,
        
        [bool]$ShowConfig = $false
    )
    
    if ($ShowConfig) {
        Show-FilterConfig -TableName $TableName
    }
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    # フィルタリングが無効または設定されていない場合は全データを返す
    if (-not $filterConfig -or -not $filterConfig.enabled) {
        Write-Host "テーブル '$TableName' のフィルタリングは無効です" -ForegroundColor Yellow
        return $DataArray
    }
    
    Write-Host "テーブル '$TableName' のデータフィルタリングを実行中..." -ForegroundColor Cyan
    
    $filteredData = @()
    $exclusionReasons = @{}
    
    foreach ($dataRow in $DataArray) {
        $exclusionReason = ""
        $exclusionReasonRef = [ref]$exclusionReason
        
        # PSCustomObjectをhashtableに変換
        $hashtableRow = @{}
        foreach ($property in $dataRow.PSObject.Properties) {
            $hashtableRow[$property.Name] = $property.Value
        }
        
        if (Test-DataFilter -TableName $TableName -DataRow $hashtableRow -ExclusionReason $exclusionReasonRef) {
            $filteredData += $dataRow
        }
        else {
            # 除外理由を記録
            $reason = $exclusionReasonRef.Value
            if ($exclusionReasons.ContainsKey($reason)) {
                $exclusionReasons[$reason]++
            }
            else {
                $exclusionReasons[$reason] = 1
            }
        }
    }
    
    # 統計情報の表示
    if ($ShowStatistics) {
        $statistics = Get-FilterStatistics -TableName $TableName -TotalCount $DataArray.Count -FilteredCount $filteredData.Count
        
        Write-Host "=== フィルタリング統計: $TableName ===" -ForegroundColor Green
        Write-Host "総件数: $($statistics.TotalCount)" -ForegroundColor White
        Write-Host "通過件数: $($statistics.FilteredCount)" -ForegroundColor Green
        Write-Host "除外件数: $($statistics.ExcludedCount)" -ForegroundColor Red
        
        if ($exclusionReasons.Count -gt 0) {
            Write-Host "除外理由別件数:" -ForegroundColor Cyan
            foreach ($reason in $exclusionReasons.Keys | Sort-Object) {
                Write-Host "  - $reason : $($exclusionReasons[$reason])件" -ForegroundColor Gray
            }
        }
    }
    
    return $filteredData
}

# SQLベースフィルタリングのサポート関数
function Invoke-SqlBasedFiltering {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath,
        
        [bool]$ShowStatistics = $true,
        
        [switch]$ShowConfig = $false
    )
    
    if ($ShowConfig) {
        Show-FilterConfig -TableName $TableName
    }
    
    try {
        Write-Host "SQLベースフィルタリングを実行中: $TableName" -ForegroundColor Cyan
        
        # 新しい高速フィルタリング機能を呼び出し
        $statistics = Import-CsvToSqliteWithSqlFilter -DatabasePath $DatabasePath -CsvFilePath $CsvFilePath -TableName $TableName -ShowStatistics:$ShowStatistics
        
        return $statistics
        
    }
    catch {
        Write-SystemLog "SQLベースフィルタリングに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# フィルタリング方式の自動選択
function Invoke-OptimalFiltering {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath,
        
        [bool]$ShowStatistics = $true,
        
        [bool]$ShowConfig = $false,
        
        [bool]$ForceClassicFiltering = $false
    )
    
    if ($ForceClassicFiltering) {
        Write-Host "クラシックフィルタリング（PowerShell）を強制実行" -ForegroundColor Yellow
        
        # 従来の PowerShell ベースフィルタリング
        $csvData = Import-Csv -Path $CsvFilePath
        $filteredData = Invoke-DataFiltering -TableName $TableName -DataArray $csvData -ShowStatistics:$ShowStatistics -ShowConfig:$ShowConfig
        
        # データベースに挿入（従来の方法）
        # この部分は既存の実装に依存
        
        return @{
            TotalCount      = $csvData.Count
            FilteredCount   = $filteredData.Count
            ExcludedCount   = $csvData.Count - $filteredData.Count
            ExclusionRate   = if ($csvData.Count -gt 0) { [Math]::Round((($csvData.Count - $filteredData.Count) / $csvData.Count) * 100, 2) } else { 0 }
            FilteringMethod = "PowerShell (Classic)"
        }
    }
    else {
        Write-Host "SQLベースフィルタリング（高速）を実行" -ForegroundColor Green
        
        # 新しい SQL ベースフィルタリング
        $statistics = Invoke-SqlBasedFiltering -DatabasePath $DatabasePath -TableName $TableName -CsvFilePath $CsvFilePath -ShowStatistics:$ShowStatistics -ShowConfig:$ShowConfig
        $statistics.FilteringMethod = "SQL (High Speed)"
        
        return $statistics
    }
}

# フィルタリング性能比較機能
function Compare-FilteringPerformance {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath
    )
    
    Write-Host "`n=== フィルタリング性能比較 ===" -ForegroundColor Yellow
    
    try {
        # SQLベース測定
        Write-Host "`n[1] SQLベースフィルタリング測定中..." -ForegroundColor Cyan
        $sqlStartTime = Get-Date
        $sqlStats = Invoke-SqlBasedFiltering -DatabasePath $DatabasePath -TableName $TableName -CsvFilePath $CsvFilePath -ShowStatistics:$false
        $sqlEndTime = Get-Date
        $sqlDuration = ($sqlEndTime - $sqlStartTime).TotalSeconds
        
        # テーブルクリア（PowerShell測定のため）
        Invoke-SqliteCommand -DatabasePath $DatabasePath -Query "DELETE FROM $TableName"
        
        # PowerShellベース測定
        Write-Host "`n[2] PowerShellベースフィルタリング測定中..." -ForegroundColor Cyan
        $classicStartTime = Get-Date
        Invoke-OptimalFiltering -DatabasePath $DatabasePath -TableName $TableName -CsvFilePath $CsvFilePath -ShowStatistics:$false -ForceClassicFiltering
        $classicEndTime = Get-Date
        $classicDuration = ($classicEndTime - $classicStartTime).TotalSeconds
        
        # 結果比較
        Write-Host "`n=== 性能比較結果 ===" -ForegroundColor Green
        Write-Host "データ件数: $($sqlStats.TotalCount)" -ForegroundColor White
        Write-Host "フィルタ後: $($sqlStats.FilteredCount)" -ForegroundColor White
        Write-Host ""
        Write-Host "SQLベース処理時間: $([Math]::Round($sqlDuration, 2))秒" -ForegroundColor Green
        Write-Host "PowerShellベース処理時間: $([Math]::Round($classicDuration, 2))秒" -ForegroundColor Yellow
        
        $speedImprovement = if ($sqlDuration -gt 0) { [Math]::Round($classicDuration / $sqlDuration, 2) } else { 0 }
        Write-Host "性能向上倍率: ${speedImprovement}倍" -ForegroundColor Cyan
        
        if ($speedImprovement -gt 1) {
            Write-Host "✅ SQLベースが高速です" -ForegroundColor Green
        }
        elseif ($speedImprovement -eq 1) {
            Write-Host "➡️ 同等の性能です" -ForegroundColor Yellow
        }
        else {
            Write-Host "⚠️ PowerShellベースが高速です（データサイズが小さい可能性）" -ForegroundColor Red
        }
        
        return @{
            SqlDuration       = $sqlDuration
            ClassicDuration   = $classicDuration
            SpeedImprovement  = $speedImprovement
            RecommendedMethod = if ($speedImprovement -ge 1) { "SQL" } else { "PowerShell" }
        }
        
    }
    catch {
        Write-SystemLog "性能比較に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}