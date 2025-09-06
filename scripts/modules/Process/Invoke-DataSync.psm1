# PowerShell & SQLite 職員データ管理システム
# データ同期処理モジュール

using module "../Utils/Foundation/CoreUtils.psm1"
using module "../Utils/Infrastructure/LoggingUtils.psm1"
using module "../Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../Utils/DataAccess/DatabaseUtils.psm1"
using module "../Utils/DataAccess/FileSystemUtils.psm1"
using module "../Utils/DataProcessing/CsvProcessingUtils.psm1"
using module "../Utils/DataProcessing/DataFilteringUtils.psm1"

# メインの同期処理（冪等性・リトライ対応）
function Invoke-DataSync {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $config = Get-DataSyncConfig
    $syncActionLabels = $config.sync_rules.sync_action_labels.mappings
    
    # 冪等性確保: sync_resultテーブルクリア
    $cleanupScript = {
        try {
            Clear-Table -DatabasePath $DatabasePath -TableName "sync_result" -ShowStatistics:$false
            Write-SystemLog "リトライ準備: sync_resultテーブルをクリアしました" -Level "Info"
        }
        catch {
            Write-SystemLog "sync_resultテーブルクリア中にエラー: $($_.Exception.Message)" -Level "Warning"
        }
    }
    
    Invoke-WithErrorHandling -Category External -Operation "データ同期処理" -CleanupScript $cleanupScript -Context @{
        "DatabasePath" = $DatabasePath
    } -ScriptBlock {
        
        Write-SystemLog "データ同期処理を開始します..." -Level "Info"
        
        # 0. リトライ対応: sync_resultテーブルを初期化
        Clear-Table -DatabasePath $DatabasePath -TableName "sync_result"
        
        # 1. 現在データに存在しないレコード（新規追加対象）を特定
        Add-NewRecords -DatabasePath $DatabasePath -SyncActionLabels $syncActionLabels
        
        # 2. 更新があったレコードを処理
        Add-UpdateRecords -DatabasePath $DatabasePath -SyncActionLabels $syncActionLabels
        
        # 3. 現在データにしか存在しないレコード（削除対象）を特定
        Add-DeleteRecords -DatabasePath $DatabasePath -SyncActionLabels $syncActionLabels
        
        # 4. 変更のないレコードを保持
        Add-KeepRecords -DatabasePath $DatabasePath -SyncActionLabels $syncActionLabels
        
        # 5. フィルタ除外されたcurrent_dataをKEEPとして追加（設定有効時のみ）
        $config = Get-DataSyncConfig
        if ($config.data_filters.current_data.output_excluded_as_keep.enabled -eq $true) {
            Add-ExcludedCurrentDataAsKeep -DatabasePath $DatabasePath -SyncActionLabels $syncActionLabels
        }
        else {
            Write-SystemLog "除外データのKEEP出力設定が無効のため、スキップします" -Level "Info"
        }
        
        Write-SystemLog "データ同期処理が完了しました。" -Level "Success"
        
    }
}

# 新規追加対象レコードをsync_resultテーブルに追加
function Add-NewRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SyncActionLabels
    )
    
    # JOIN条件を動的に生成（エイリアス対応）
    $joinCondition = New-JoinCondition -LeftTableName "provided_data" -RightTableName "current_data" -LeftAlias "pd" -RightAlias "cd"
    $currentDataKeys = Get-TableKeyColumns -TableName "current_data"
    $currentDataKey = ($currentDataKeys | Select-Object -First 1)
    
    Write-SystemLog "新規レコードを特定中..." -Level "Info"
    
    # 設定ベースで新規レコード挿入クエリを生成（カラムマッピング対応）
    $insertColumns = Get-SyncResultInsertColumns
    $escapedInsertColumns = $insertColumns | ForEach-Object { Escape-SqlIdentifier -Identifier $_ }
    $insertColumnsString = $escapedInsertColumns -join ", "
    
    $selectClause = New-SyncResultSelectClause -SourceTableName "provided_data" -SourceTableAlias "pd" -SyncAction $SyncActionLabels.ADD.value
    
    $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $selectClause
FROM provided_data pd
LEFT JOIN current_data cd ON $joinCondition
WHERE cd.$currentDataKey IS NULL;
"@
    
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
    
    # 追加されたレコード数を取得
    Write-SystemLog "新規レコード追加処理が完了しました" -Level "Success"
}

# 更新対象レコードをsync_resultテーブルに追加
function Add-UpdateRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SyncActionLabels
    )
    
    # JOIN条件を動的に生成（エイリアス対応）
    $joinCondition = New-JoinCondition -LeftTableName "provided_data" -RightTableName "current_data" -LeftAlias "pd" -RightAlias "cd"
    
    Write-SystemLog "更新レコードを特定中..." -Level "Info"
    
    # 設定ベースで更新レコード挿入クエリを生成（カラムマッピング対応）
    $insertColumns = Get-SyncResultInsertColumns
    $escapedInsertColumns = $insertColumns | ForEach-Object { Escape-SqlIdentifier -Identifier $_ }
    $insertColumnsString = $escapedInsertColumns -join ", "
    
    $selectClause = New-PriorityBasedSyncResultSelectClause -SyncAction $SyncActionLabels.UPDATE.value
    
    # 比較条件を動的に生成
    $whereClause = New-ComparisonWhereClause -Table1Alias "pd" -Table2Alias "cd" -ComparisonType "different" -Table1Name "provided_data" -Table2Name "current_data"
    
    $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $selectClause
FROM provided_data pd
INNER JOIN current_data cd ON $joinCondition
WHERE 
    $whereClause;
"@
    
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
    
    # 更新されたレコード数を取得
    Write-SystemLog "更新レコード追加処理が完了しました" -Level "Success"
}

# 削除対象レコードをsync_resultテーブルに追加
function Add-DeleteRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SyncActionLabels
    )
    
    # 複合キー対応のJOIN条件生成
    $joinCondition = New-JoinCondition -LeftTableName "current_data" -RightTableName "provided_data" -LeftAlias "cd" -RightAlias "pd"
    $providedDataKeys = Get-TableKeyColumns -TableName "provided_data"
    # 最初の要素を安全に取得
    $providedDataKey = ($providedDataKeys | Select-Object -First 1)
    
    Write-SystemLog "削除対象レコードを特定中..." -Level "Info"
    
    # 設定ベースで削除レコード挿入クエリを生成（カラムマッピング対応）
    $insertColumns = Get-SyncResultInsertColumns
    $escapedInsertColumns = $insertColumns | ForEach-Object { Escape-SqlIdentifier -Identifier $_ }
    $insertColumnsString = $escapedInsertColumns -join ", "
    
    $selectClause = New-SyncResultSelectClause -SourceTableName "current_data" -SourceTableAlias "cd" -SyncAction $SyncActionLabels.DELETE.value
    
    $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $selectClause
FROM current_data cd
LEFT JOIN provided_data pd ON $joinCondition
WHERE pd.$providedDataKey IS NULL;
"@
    
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
    
    # 削除されたレコード数を取得
    Write-SystemLog "削除レコード追加処理が完了しました" -Level "Success"
}

# 保持対象レコードをsync_resultテーブルに追加
function Add-KeepRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SyncActionLabels
    )
    
    # 複合キー対応のJOIN条件とNOT IN条件生成
    $joinCondition = New-JoinCondition -LeftTableName "provided_data" -RightTableName "current_data" -LeftAlias "pd" -RightAlias "cd"
    $syncResultKeys = Get-TableKeyColumns -TableName "sync_result"
    
    # NOT IN句用: provided_dataのキーカラムを優先度ベースマッピングから生成
    $providedDataMappedKeys = @()
    foreach ($syncResultKey in $syncResultKeys) {
        $providedDataField = Get-PriorityBasedSourceField -SyncResultField $syncResultKey -SourceTableName "provided_data"
        $providedDataMappedKeys += "pd.$providedDataField"
    }
    $providedDataGroupBy = $providedDataMappedKeys -join ", "
    
    # サブクエリ用: sync_resultのキーカラムをそのまま指定
    $syncResultGroupBy = New-GroupByClause -TableName "sync_result"
    
    Write-SystemLog "変更なしレコードを特定中..." -Level "Info"
    
    # 設定ベースで変更なしレコード挿入クエリを生成（カラムマッピング対応）
    $insertColumns = Get-SyncResultInsertColumns
    $escapedInsertColumns = $insertColumns | ForEach-Object { Escape-SqlIdentifier -Identifier $_ }
    $insertColumnsString = $escapedInsertColumns -join ", "
    
    $selectClause = New-PriorityBasedSyncResultSelectClause -SyncAction $SyncActionLabels.KEEP.value
    
    # 比較条件を動的に生成
    $whereClause = New-ComparisonWhereClause -Table1Alias "pd" -Table2Alias "cd" -ComparisonType "same" -Table1Name "provided_data" -Table2Name "current_data"
    
    $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $selectClause
FROM provided_data pd
INNER JOIN current_data cd ON $joinCondition
WHERE 
    $whereClause
    AND ($providedDataGroupBy) NOT IN (SELECT $syncResultGroupBy FROM sync_result);
"@
    
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
    
    # 保持されたレコード数を取得
    Write-SystemLog "変更なしレコード追加処理が完了しました" -Level "Success"
}

# フィルタ除外されたcurrent_dataをKEEPアクションとして追加
function Add-ExcludedCurrentDataAsKeep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$SyncActionLabels
    )
    
    $excludedTableName = "current_data_excluded"
    
    # 除外データテーブルの存在確認
    $checkTableQuery = @"
SELECT name FROM sqlite_master 
WHERE type='table' AND name='$excludedTableName';
"@
    
    $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $checkTableQuery
    
    if (-not $result -or $result.Count -eq 0) {
        Write-SystemLog "除外データテーブルが存在しないため、スキップします: $excludedTableName" -Level "Info"
        return
    }
    
    Write-SystemLog "フィルタ除外されたcurrent_dataをKEEPアクションとして追加中..." -Level "Info"
    
    # sync_result用の挿入カラム取得
    $insertColumns = Get-CsvColumns -TableName "sync_result"
    $escapedInsertColumns = $insertColumns | ForEach-Object { Escape-SqlIdentifier -Identifier $_ }
    $insertColumnsString = $escapedInsertColumns -join ", "
    
    # 除外されたcurrent_dataから直接マッピングしてSELECT句を生成
    $selectClauses = @()
    foreach ($syncResultColumn in $insertColumns) {
        if ($syncResultColumn -eq "sync_action") {
            $selectClauses += "'$($SyncActionLabels.KEEP.value)'"
        }
        elseif ($syncResultColumn -eq "syokuin_no") {
            # current_dataのuser_idをsyokuin_noにマッピング
            $selectClauses += "ced.user_id"
        }
        else {
            # その他のカラムは同名でマッピング（エスケープ対応）
            $escapedColumn = Escape-SqlIdentifier -Identifier $syncResultColumn
            $selectClauses += "ced.$escapedColumn"
        }
    }
    $selectClause = $selectClauses -join ", "
    
    $query = @"
INSERT OR IGNORE INTO sync_result ($insertColumnsString)
SELECT 
    $selectClause
FROM $excludedTableName ced;
"@
    
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
    
    # 追加されたレコード数を取得
    $countQuery = "SELECT COUNT(*) as count FROM $excludedTableName;"
    $countResult = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
    $addedCount = if ($countResult -and $countResult[0]) { $countResult[0].count } else { 0 }
    
    Write-SystemLog "フィルタ除外データをKEEPアクションとして追加しました ($addedCount 件)" -Level "Success"
}

Export-ModuleMember -Function 'Invoke-DataSync'