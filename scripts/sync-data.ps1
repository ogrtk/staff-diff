# PowerShell & SQLite 職員データ管理システム
# データ同期処理スクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "common-utils.ps1")

# メインの同期処理
function Sync-StaffData {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "データ同期処理を開始します..." -Level "Info"
        
        # 同期結果テーブルをクリア
        Clear-Table -DatabasePath $DatabasePath -TableName "sync_result"
        
        # 1. 職員マスタに存在しないレコード（新規追加対象）を特定
        Add-NewStaffRecords -DatabasePath $DatabasePath
        
        # 2. 更新があったレコードを処理
        Process-UpdatedRecords -DatabasePath $DatabasePath
        
        # 3. 職員マスタにしか存在しないレコード（削除対象）を特定
        Remove-ObsoleteRecords -DatabasePath $DatabasePath
        
        # 4. 変更のないレコードを保持
        Keep-UnchangedRecords -DatabasePath $DatabasePath
        
        Write-SystemLog "データ同期処理が完了しました。" -Level "Success"
        
    } catch {
        Write-SystemLog "データ同期処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 新規レコードの追加
function Add-NewStaffRecords {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "新規レコードを特定中..." -Level "Info"
        
        # 設定ベースで新規レコード挿入クエリを生成
        $csvColumns = Get-CsvColumns -TableName "staff_info"
        $csvColumnsWithPrefix = $csvColumns | ForEach-Object { "si.$_" }
        $csvColumnsString = $csvColumnsWithPrefix -join ", "
        
        $insertColumns = $csvColumns + @("sync_action")
        $insertColumnsString = $insertColumns -join ", "
        
        $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $csvColumnsString,
    'ADD'
FROM staff_info si
LEFT JOIN staff_master sm ON si.employee_id = sm.employee_id
WHERE sm.employee_id IS NULL;
"@
        
        Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
        
        # 追加されたレコード数を取得
        $countQuery = "SELECT COUNT(*) as count FROM sync_result WHERE sync_action = 'ADD';"
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
        $addCount = if ($result -is [array]) { $result[0] } else { $result }
        
        Write-SystemLog "新規追加対象: $($addCount.count)件" -Level "Success"
        
    } catch {
        Write-SystemLog "新規レコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 更新されたレコードの処理
function Process-UpdatedRecords {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "更新レコードを特定中..." -Level "Info"
        
        # 設定ベースで更新レコード挿入クエリを生成
        $csvColumns = Get-CsvColumns -TableName "staff_info"
        $csvColumnsWithPrefix = $csvColumns | ForEach-Object { "si.$_" }
        $csvColumnsString = $csvColumnsWithPrefix -join ", "
        
        $insertColumns = $csvColumns + @("sync_action")
        $insertColumnsString = $insertColumns -join ", "
        
        # 比較条件を動的に生成
        $whereClause = New-ComparisonWhereClause -Table1Alias "si" -Table2Alias "sm" -ComparisonType "different"
        
        $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $csvColumnsString,
    'UPDATE'
FROM staff_info si
INNER JOIN staff_master sm ON si.employee_id = sm.employee_id
WHERE 
    $whereClause;
"@
        
        Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
        
        # 更新されたレコード数を取得
        $countQuery = "SELECT COUNT(*) as count FROM sync_result WHERE sync_action = 'UPDATE';"
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
        $updateCount = if ($result -is [array]) { $result[0] } else { $result }
        
        Write-SystemLog "更新対象: $($updateCount.count)件" -Level "Success"
        
    } catch {
        Write-SystemLog "更新レコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 削除対象レコードの処理
function Remove-ObsoleteRecords {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "削除対象レコードを特定中..." -Level "Info"
        
        # 設定ベースで削除レコード挿入クエリを生成
        $csvColumns = Get-CsvColumns -TableName "staff_master"
        $csvColumnsWithPrefix = $csvColumns | ForEach-Object { "sm.$_" }
        $csvColumnsString = $csvColumnsWithPrefix -join ", "
        
        $insertColumns = $csvColumns + @("sync_action")
        $insertColumnsString = $insertColumns -join ", "
        
        $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $csvColumnsString,
    'DELETE'
FROM staff_master sm
LEFT JOIN staff_info si ON sm.employee_id = si.employee_id
WHERE si.employee_id IS NULL;
"@
        
        Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
        
        # 削除されたレコード数を取得
        $countQuery = "SELECT COUNT(*) as count FROM sync_result WHERE sync_action = 'DELETE';"
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
        $deleteCount = if ($result -is [array]) { $result[0] } else { $result }
        
        Write-SystemLog "削除対象: $($deleteCount.count)件" -Level "Success"
        
    } catch {
        Write-SystemLog "削除対象レコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 変更のないレコードの保持
function Keep-UnchangedRecords {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "変更なしレコードを特定中..." -Level "Info"
        
        # 設定ベースで変更なしレコード挿入クエリを生成
        $csvColumns = Get-CsvColumns -TableName "staff_info"
        $csvColumnsWithPrefix = $csvColumns | ForEach-Object { "si.$_" }
        $csvColumnsString = $csvColumnsWithPrefix -join ", "
        
        $insertColumns = $csvColumns + @("sync_action")
        $insertColumnsString = $insertColumns -join ", "
        
        # 比較条件を動的に生成
        $whereClause = New-ComparisonWhereClause -Table1Alias "si" -Table2Alias "sm" -ComparisonType "same"
        
        $query = @"
INSERT INTO sync_result ($insertColumnsString)
SELECT 
    $csvColumnsString,
    'KEEP'
FROM staff_info si
INNER JOIN staff_master sm ON si.employee_id = sm.employee_id
WHERE 
    $whereClause
    AND si.employee_id NOT IN (SELECT employee_id FROM sync_result);
"@
        
        Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
        
        # 保持されたレコード数を取得
        $countQuery = "SELECT COUNT(*) as count FROM sync_result WHERE sync_action = 'KEEP';"
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
        $keepCount = if ($result -is [array]) { $result[0] } else { $result }
        
        Write-SystemLog "変更なし（保持）: $($keepCount.count)件" -Level "Success"
        
    } catch {
        Write-SystemLog "変更なしレコードの処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 同期処理の詳細レポート生成
function Get-SyncReport {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    try {
        $reportQuery = @"
SELECT 
    'STAFF_INFO_TOTAL' as category,
    COUNT(*) as count
FROM staff_info
UNION ALL
SELECT 
    'STAFF_MASTER_TOTAL' as category,
    COUNT(*) as count
FROM staff_master
UNION ALL
SELECT 
    'SYNC_' || sync_action as category,
    COUNT(*) as count
FROM sync_result
GROUP BY sync_action;
"@
        
        # SQLite3コマンドラインでCSV形式で結果を取得
        $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if ($sqlite3Path) {
            $result = & sqlite3 -csv $DatabasePath $reportQuery
        } else {
            $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $reportQuery
        }
        
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
        } else {
            Write-Host "レポートデータがありません" -ForegroundColor Gray
        }
        Write-Host "=========================" -ForegroundColor Yellow
        
        return $report
        
    } catch {
        Write-SystemLog "同期レポートの生成に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# データの整合性チェック
function Test-DataConsistency {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "データ整合性をチェック中..." -Level "Info"
        
        # 重複チェック
        $duplicateQuery = @"
SELECT employee_id, COUNT(*) as count
FROM sync_result
GROUP BY employee_id
HAVING COUNT(*) > 1;
"@
        
        $duplicates = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $duplicateQuery
        
        if ($duplicates -and $duplicates.Count -gt 0) {
            Write-Warning "重複したemployee_idが見つかりました:"
            foreach ($dup in $duplicates) {
                Write-Warning "  $($dup.employee_id): $($dup.count)件"
            }
            return $false
        }
        
        Write-SystemLog "データ整合性チェック完了: 問題なし" -Level "Success"
        return $true
        
    } catch {
        Write-SystemLog "データ整合性チェックに失敗しました: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}