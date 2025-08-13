# PowerShell & SQLite 職員データ管理システム
# データ同期処理モジュール

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
        Add-NewRecords -DatabasePath $DatabasePath
        
        # 2. 更新があったレコードを処理
        Add-UpdateRecords -DatabasePath $DatabasePath
        
        # 3. 現在データにしか存在しないレコード（削除対象）を特定
        Add-DeleteRecords -DatabasePath $DatabasePath
        
        # 4. 変更のないレコードを保持
        Add-KeepRecords -DatabasePath $DatabasePath
        
        Write-SystemLog "データ同期処理が完了しました。" -Level "Success"
        
    }
}

# 新規追加対象レコードをsync_resultテーブルに追加
function script:Add-NewRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # JOIN条件を動的に生成（エイリアス対応）
    $joinCondition = New-JoinCondition -LeftTableName "provided_data" -RightTableName "current_data" -LeftAlias "pd" -RightAlias "cd"
    $currentDataKeys = Get-TableKeyColumns -TableName "current_data"
    $currentDataKey = ($currentDataKeys | Select-Object -First 1)
    
    Write-SystemLog "新規レコードを特定中..." -Level "Info"
    
    # 設定ベースで新規レコード挿入クエリを生成（カラムマッピング対応）
    $insertColumns = Get-SyncResultInsertColumns
    $insertColumnsString = $insertColumns -join ", "
    
    $selectClause = New-SyncResultSelectClause -SourceTableName "provided_data" -SourceTableAlias "pd" -SyncAction $syncActionLabels.ADD.action_name
    
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
    Write-SystemLog "新規追加処理が完了しました" -Level "Success"
}

# 更新対象レコードをsync_resultテーブルに追加
function script:Add-UpdateRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # JOIN条件を動的に生成（エイリアス対応）
    $joinCondition = New-JoinCondition -LeftTableName "provided_data" -RightTableName "current_data" -LeftAlias "pd" -RightAlias "cd"
    
    Write-SystemLog "更新レコードを特定中..." -Level "Info"
    
    # 設定ベースで更新レコード挿入クエリを生成（カラムマッピング対応）
    $insertColumns = Get-SyncResultInsertColumns
    $insertColumnsString = $insertColumns -join ", "
    
    $selectClause = New-PriorityBasedSyncResultSelectClause -SyncAction $syncActionLabels.UPDATE.action_name
    
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
    Write-SystemLog "更新処理が完了しました" -Level "Success"
}

# 削除対象レコードをsync_resultテーブルに追加
function script:Add-DeleteRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # 複合キー対応のJOIN条件生成
    $joinCondition = New-JoinCondition -LeftTableName "current_data" -RightTableName "provided_data" -LeftAlias "cd" -RightAlias "pd"
    $providedDataKeys = Get-TableKeyColumns -TableName "provided_data"
    # 最初の要素を安全に取得
    $providedDataKey = ($providedDataKeys | Select-Object -First 1)
    
    Write-SystemLog "削除対象レコードを特定中..." -Level "Info"
    
    # 設定ベースで削除レコード挿入クエリを生成（カラムマッピング対応）
    $insertColumns = Get-SyncResultInsertColumns
    $insertColumnsString = $insertColumns -join ", "
    
    $selectClause = New-SyncResultSelectClause -SourceTableName "current_data" -SourceTableAlias "cd" -SyncAction $syncActionLabels.DELETE.action_name
    
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
    Write-SystemLog "削除処理が完了しました" -Level "Success"
}

# 保持対象レコードをsync_resultテーブルに追加
function script:Add-KeepRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
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
    $insertColumnsString = $insertColumns -join ", "
    
    $selectClause = New-PriorityBasedSyncResultSelectClause -SyncAction $syncActionLabels.KEEP.action_name
    
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
    Write-SystemLog "保持処理が完了しました" -Level "Success"
}

Export-ModuleMember -Function 'Invoke-DataSync'