# PowerShell & SQLite 職員データ管理システム
# データ同期処理スクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "utils/config-utils.ps1")
. (Join-Path $PSScriptRoot "utils/sql-utils.ps1")
. (Join-Path $PSScriptRoot "utils/file-utils.ps1")
. (Join-Path $PSScriptRoot "utils/common-utils.ps1")

# メインの同期処理
function Sync-StaffData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "データ同期処理を開始します..." -Level "Info"
        
        # 1. 職員マスタに存在しないレコード（新規追加対象）を特定
        Add-NewStaffRecords -DatabasePath $DatabasePath
        
        # 2. 更新があったレコードを処理
        Add-UpdateRecords -DatabasePath $DatabasePath
        
        # 3. 職員マスタにしか存在しないレコード（削除対象）を特定
        Add-DeleteRecords -DatabasePath $DatabasePath
        
        # 4. 変更のないレコードを保持
        Add-KeepRecords -DatabasePath $DatabasePath
        
        Write-SystemLog "データ同期処理が完了しました。" -Level "Success"
        
    }
    catch {
        Write-SystemLog "データ同期処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 新規追加対象レコードをsync_resultテーブルに追加
function Add-NewStaffRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # JOIN条件を動的に生成（エイリアス対応）
    $joinCondition = New-JoinCondition -LeftTableName "provided_data" -RightTableName "current_data" -LeftAlias "pd" -RightAlias "cd"
    $currentDataKeys = Get-TableKeyColumns -TableName "current_data"
    $currentDataKey = ($currentDataKeys | Select-Object -First 1)
    
    try {
        Write-SystemLog "新規レコードを特定中..." -Level "Info"
        
        # 設定ベースで新規レコード挿入クエリを生成（カラムマッピング対応）
        $insertColumns = Get-SyncResultInsertColumns
        $insertColumnsString = $insertColumns -join ", "
        
        $selectClause = New-SyncResultSelectClause -SourceTableName "provided_data" -SourceTableAlias "pd" -SyncAction "ADD"
        
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
    catch {
        Write-SystemLog "新規レコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 更新対象レコードをsync_resultテーブルに追加
function Add-UpdateRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # JOIN条件を動的に生成（エイリアス対応）
    $joinCondition = New-JoinCondition -LeftTableName "provided_data" -RightTableName "current_data" -LeftAlias "pd" -RightAlias "cd"
    
    try {
        Write-SystemLog "更新レコードを特定中..." -Level "Info"
        
        # 設定ベースで更新レコード挿入クエリを生成（カラムマッピング対応）
        $insertColumns = Get-SyncResultInsertColumns
        $insertColumnsString = $insertColumns -join ", "
        
        $selectClause = New-PriorityBasedSyncResultSelectClause -SyncAction "UPDATE"
        
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
    catch {
        Write-SystemLog "更新レコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 削除対象レコードをsync_resultテーブルに追加
function Add-DeleteRecords {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # 複合キー対応のJOIN条件生成
    $joinCondition = New-JoinCondition -LeftTableName "current_data" -RightTableName "provided_data" -LeftAlias "cd" -RightAlias "pd"
    $providedDataKeys = Get-TableKeyColumns -TableName "provided_data"
    # 最初の要素を安全に取得
    $providedDataKey = ($providedDataKeys | Select-Object -First 1)
    
    try {
        Write-SystemLog "削除対象レコードを特定中..." -Level "Info"
        
        # 設定ベースで削除レコード挿入クエリを生成（カラムマッピング対応）
        $insertColumns = Get-SyncResultInsertColumns
        $insertColumnsString = $insertColumns -join ", "
        
        $selectClause = New-SyncResultSelectClause -SourceTableName "current_data" -SourceTableAlias "cd" -SyncAction "DELETE"
        
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
    catch {
        Write-SystemLog "削除対象レコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 保持対象レコードをsync_resultテーブルに追加
function Add-KeepRecords {
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
    
    try {
        Write-SystemLog "変更なしレコードを特定中..." -Level "Info"
        
        # 設定ベースで変更なしレコード挿入クエリを生成（カラムマッピング対応）
        $insertColumns = Get-SyncResultInsertColumns
        $insertColumnsString = $insertColumns -join ", "
        
        $selectClause = New-PriorityBasedSyncResultSelectClause -SyncAction "KEEP"
        
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
    catch {
        Write-SystemLog "変更なしレコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 同期処理の詳細レポート生成
function Get-SyncReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    try {
        $reportQuery = @"
SELECT 
    'PROVIDED_DATA_TOTAL' as category,
    COUNT(*) as count
FROM provided_data
UNION ALL
SELECT 
    'CURRENT_DATA_TOTAL' as category,
    COUNT(*) as count
FROM current_data
UNION ALL
SELECT 
    'SYNC_' || sync_action as category,
    COUNT(*) as count
FROM sync_result
GROUP BY sync_action;
"@
        
        # SQLite CSV形式で結果を取得
        $result = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $reportQuery
        
        Write-Host "`n=== 詳細同期レポート ===" -ForegroundColor Yellow
        if ($result -and $result.Count -gt 0) {
            foreach ($line in $result) {
                if ($line) {
                    $parts = $line -split ','
                    if ($parts.Count -eq 2) {
                        Write-Host "$($parts[0]): $($parts[1])" -ForegroundColor White
                    }
                }
            }
        }
        else {
            Write-Host "レポートデータがありません" -ForegroundColor Gray
        }
        Write-Host "=========================" -ForegroundColor Yellow
        
        return $result
        
    }
    catch {
        Write-SystemLog "同期レポートの生成に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# データの整合性チェック
function Test-DataConsistency {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # 複合キー対応のGROUP BY句生成
    $groupByClause = New-GroupByClause -TableName "sync_result"
    $syncResultKeys = Get-TableKeyColumns -TableName "sync_result"
    
    try {
        Write-SystemLog "データ整合性をチェック中..." -Level "Info"
        
        # 重複チェック
        $duplicateQuery = @"
SELECT $groupByClause, COUNT(*) as count
FROM sync_result
GROUP BY $groupByClause
HAVING COUNT(*) > 1;
"@
        
        $duplicates = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $duplicateQuery
        
        if ($duplicates -and $duplicates.Count -gt 0) {
            Write-Warning "重複したキー（$($syncResultKeys -join ', ')）が見つかりました:"
            foreach ($dup in $duplicates) {
                $keyValues = @()
                foreach ($key in $syncResultKeys) {
                    $keyValues += $dup.$key
                }
                $keyString = $keyValues -join ', '
                Write-Warning "  ($keyString): $($dup.count)件"
            }
            return $false
        }
        
        Write-SystemLog "データ整合性チェック完了: 問題なし" -Level "Success"
        return $true
        
    }
    catch {
        Write-SystemLog "データ整合性チェックに失敗しました: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}