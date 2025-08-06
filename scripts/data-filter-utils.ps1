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
        TableName = $TableName
        TotalCount = $TotalCount
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
        
        [switch]$ShowStatistics = $true,
        
        [switch]$ShowConfig = $false
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
        Write-Host "除外率: $($statistics.ExclusionRate)%" -ForegroundColor Yellow
        
        if ($exclusionReasons.Count -gt 0) {
            Write-Host "除外理由別件数:" -ForegroundColor Cyan
            foreach ($reason in $exclusionReasons.Keys | Sort-Object) {
                Write-Host "  - $reason : $($exclusionReasons[$reason])件" -ForegroundColor Gray
            }
        }
    }
    
    return $filteredData
}