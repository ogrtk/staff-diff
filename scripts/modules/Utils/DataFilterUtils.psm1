# PowerShell & SQLite データ同期システム
# データフィルタリングユーティリティライブラリ

# フィルタ設定の表示
function Show-FilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    if (-not $filterConfig) {
        Write-SystemLog "テーブル '$TableName' にフィルタ設定がありません" -Level "Warning"
        return
    }
    
    Write-SystemLog "=== フィルタ設定: $TableName ===" -Level "Info"
    Write-SystemLog "有効: $($filterConfig.enabled)" -Level "Info"
    
    if ($filterConfig.rules -and $filterConfig.rules.Count -gt 0) {
        Write-SystemLog "ルール数: $($filterConfig.rules.Count)" -Level "Info"
        
        for ($i = 0; $i -lt $filterConfig.rules.Count; $i++) {
            $rule = $filterConfig.rules[$i]
            Write-SystemLog "  [$($i + 1)] フィールド: $($rule.field)" -Level "Info"
            Write-SystemLog "       タイプ: $($rule.type)" -Level "Info"
            
            if ($rule.pattern) {
                Write-SystemLog "       パターン: $($rule.pattern)" -Level "Info"
            }
            if ($rule.value) {
                Write-SystemLog "       値: $($rule.value)" -Level "Info"
            }
            
            Write-SystemLog "       説明: $($rule.description)" -Level "Info"
        }
    }
    else {
        Write-SystemLog "ルールが設定されていません" -Level "Warning"
    }
}

# 一時テーブル名の生成（utils関数）
function New-TempTableName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseTableName
    )
    
    return "${BaseTableName}_temp"
}

# フィルタリング統計の表示（utils関数）
function Show-FilteringStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [int]$TotalCount,
        
        [Parameter(Mandatory = $true)]
        [int]$FilteredCount,
        
        [string]$WhereClause = ""
    )
    
    $excludedCount = $TotalCount - $FilteredCount
    
    Write-SystemLog "`n=== データフィルタ処理結果: $TableName ===" -Level "Info"
    
    if ($WhereClause) {
        Write-SystemLog "適用フィルタ: $WhereClause" -Level "Info"
        Write-SystemLog "総件数: $TotalCount" -Level "Info"
        Write-SystemLog "通過件数: $FilteredCount" -Level "Info"
        Write-SystemLog "除外件数: $excludedCount" -Level "Info"
    }
    else {
        Write-SystemLog "適用フィルタ: なし（全件通過）" -Level "Info"
    }
}

Export-ModuleMember -Function @(
    'Show-FilterConfig',
    'Show-FilteringStatistics',
    'New-TempTableName'
)
