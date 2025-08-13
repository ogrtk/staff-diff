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

# # フィルタリング結果の返却形式（utils関数）
# function New-FilteringResult {
#     param(
#         [Parameter(Mandatory = $true)]
#         [int]$TotalCount,
        
#         [Parameter(Mandatory = $true)]
#         [int]$FilteredCount
#     )
    
#     $excludedCount = $TotalCount - $FilteredCount
#     $exclusionRate = if ($TotalCount -gt 0) { [Math]::Round(($excludedCount / $TotalCount) * 100, 2) } else { 0 }
    
#     return @{
#         TotalCount    = $TotalCount
#         FilteredCount = $FilteredCount
#         ExcludedCount = $excludedCount
#         ExclusionRate = $exclusionRate
#     }
# }

Export-ModuleMember -Function @(
    'Show-FilterConfig',
    'Show-FilteringStatistics',
    # 'New-FilteringResult',
    'New-TempTableName'
)
