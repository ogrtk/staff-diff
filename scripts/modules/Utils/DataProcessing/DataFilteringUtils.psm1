# PowerShell & SQLite データ同期システム
# Layer 4: Data Filtering ユーティリティライブラリ（データフィルタ処理専用）

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
    $filterRate = if ($TotalCount -gt 0) { [math]::Round(($FilteredCount / $TotalCount) * 100, 1) } else { 0 }
    
    Write-SystemLog "----------------------------------" -Level "Info"
    Write-SystemLog "データフィルタ処理結果: $TableName" -Level "Info"
    
    if ($WhereClause) {
        Write-SystemLog "適用フィルタ: $WhereClause" -Level "Info"
        Write-SystemLog "総件数: $TotalCount" -Level "Info"
        Write-SystemLog "通過件数: $FilteredCount (通過率: ${filterRate}%)" -Level "Info"
        Write-SystemLog "除外件数: $excludedCount" -Level "Info"
        
        if ($excludedCount -gt 0) {
            Write-SystemLog "フィルタにより $excludedCount 件のデータが除外されました" -Level "Warning"
        }
    }
    else {
        Write-SystemLog "適用フィルタ: なし（全件通過）" -Level "Info"
        Write-SystemLog "処理件数: $TotalCount" -Level "Info"
    }
    
    Write-SystemLog "----------------------------------" -Level "Info"
}

Export-ModuleMember -Function @(
    'New-TempTableName',
    'Show-FilteringStatistics'
)