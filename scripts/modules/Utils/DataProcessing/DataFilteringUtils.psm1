# PowerShell & SQLite データ同期システム
# Layer 4: Data Filtering ユーティリティライブラリ（データフィルタ処理専用）
using module "../Foundation/CoreUtils.psm1"
using module "../Infrastructure/LoggingUtils.psm1"
using module "../Infrastructure/ConfigurationUtils.psm1"
using module "../DataAccess/DatabaseUtils.psm1"

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

# フィルタ除外データをKEEP用テーブルに保存
function Save-ExcludedDataForKeep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$SourceTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$ExcludedTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$FilterConfigTableName
    )
    
    # フィルタ条件を取得（除外データ特定用）
    $whereClause = New-FilterWhereClause -TableName $FilterConfigTableName

    if ([string]::IsNullOrWhiteSpace($whereClause)) {
        Write-SystemLog "フィルタ条件がないため、除外データ保存をスキップします: $FilterConfigTableName" -Level "Info"
        return
    }
    
    # 除外データ用テーブルを作成（既存テーブルをクリーンアップしてから作成）
    $dropTableSql = "DROP TABLE IF EXISTS $ExcludedTableName;"
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $dropTableSql
    
    $createTableSql = New-CreateTempTableSql -BaseTableName $FilterConfigTableName -TempTableName $ExcludedTableName
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $createTableSql
    
    Write-SystemLog "除外データ用テーブルを作成しました: $ExcludedTableName" -Level "Info"
    
    # 除外データをテーブルに保存（フィルタ条件の逆を使用）
    $csvColumns = Get-CsvColumns -TableName $FilterConfigTableName
    $escapedColumns = $csvColumns | ForEach-Object { Escape-SqlIdentifier -Identifier $_ }
    $columnsStr = $escapedColumns -join ", "
    
    # フィルタ条件を反転（除外データを抽出）
    $excludeWhereClause = "NOT ($whereClause)"
    
    $insertSql = @"
INSERT INTO $ExcludedTableName ($columnsStr)
SELECT $columnsStr FROM $SourceTableName
WHERE $excludeWhereClause;
"@
    
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $insertSql
    
    # 保存された除外データ数を取得
    $countQuery = "SELECT COUNT(*) as count FROM $ExcludedTableName;"
    $countResult = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
    $excludedCount = if ($countResult -and $countResult[0]) { $countResult[0].count } else { 0 }
    
    Write-SystemLog "除外データをKEEP用テーブルに保存しました: $ExcludedTableName ($excludedCount 件)" -Level "Success"
}

Export-ModuleMember -Function @(
    'New-TempTableName',
    'Show-FilteringStatistics',
    'Save-ExcludedDataForKeep'
)