# PowerShell & SQLite データ同期システム
# 統合同期結果表示モジュール

# 同期処理の包括的結果表示（安全な操作）
function Show-SyncResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$ProvidedDataFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$CurrentDataFilePath
    )
    
    Invoke-WithErrorHandling  -Operation "同期レポート生成" -Category External -SuppressThrow:$true -ScriptBlock {
        Write-SystemLog "=== 同期処理完了レポート ===" -Level "Info"
        
        # 1. 実行情報セクション
        Write-SystemLog "--- 実行情報 ---" -Level "Info"
        Write-SystemLog "データベースファイル: $DatabasePath" -Level "Info"
        Write-SystemLog "提供データファイル: $ProvidedDataFilePath" -Level "Info"
        Write-SystemLog "現在データファイル: $CurrentDataFilePath" -Level "Info"
        
        $config = Get-DataSyncConfig
        Write-SystemLog "設定バージョン: $($config.version)" -Level "Info"
        $japanTime = [DateTime]::UtcNow.AddHours(9).ToString('yyyy-MM-dd HH:mm:ss')
        Write-SystemLog "実行時刻: $japanTime" -Level "Info"
        
        # sync_action_labels設定を取得
        $syncActionLabels = $config.sync_rules.sync_action_labels.mappings
        
        # 2. データ統計セクション
        Write-SystemLog "--- データ統計 ---" -Level "Info"
        
        # 全テーブル件数を一括取得
        $allTablesQuery = @"
SELECT 'provided_data' as table_name, COUNT(*) as count FROM provided_data
UNION ALL
SELECT 'current_data' as table_name, COUNT(*) as count FROM current_data
UNION ALL
SELECT 'sync_result' as table_name, COUNT(*) as count FROM sync_result;
"@
        
        $tableResults = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $allTablesQuery
        
        foreach ($tableResult in $tableResults) {
            Write-SystemLog "$($tableResult.table_name): $($tableResult.count) 件" -Level "Info"
        }
        
        # 3. 同期結果セクション
        Write-SystemLog "--- 同期結果 ---" -Level "Info"
        
        # 設定から動的にORDER BY句を生成
        $syncActionLabels = $config.sync_rules.sync_action_labels.mappings
        
        $orderByCases = @()
        $displayOrder = 1
        
        foreach ($actionKey in $syncActionLabels.PSObject.Properties.Name) {
            $actionConfig = $syncActionLabels.$actionKey
            $actionName = $actionConfig.action_name
            $orderByCases += "        WHEN '$actionName' THEN $displayOrder"
            $displayOrder++
        }
        
        $orderByClause = $orderByCases -join "`n"
        
        $syncResultQuery = @"
SELECT 
    sync_action,
    COUNT(*) as count
FROM sync_result
GROUP BY sync_action
ORDER BY 
    CASE sync_action 
$orderByClause
        ELSE 999
    END;
"@
        
        $syncResults = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $syncResultQuery
        
        $totalSyncRecords = 0
        foreach ($syncResult in $syncResults) {
            $action = $syncResult.sync_action
            $count = [int]$syncResult.count
            $totalSyncRecords += $count
            
            # 設定ファイルから動的に取得（ハードコーディング排除）
            $cleanAction = $action.ToString().Trim()
            
            # sync_action_labelsから設定を取得
            $actionConfig = $null
            if ($syncActionLabels -and $syncActionLabels.$cleanAction) {
                $actionConfig = $syncActionLabels.$cleanAction
            }
            else {
                # 文字列のアクション名から検索（ADD, UPDATE等で格納されている場合）
                foreach ($key in $syncActionLabels.Keys) {
                    if ($syncActionLabels.$key.action_name -eq $cleanAction) {
                        $actionConfig = $syncActionLabels.$key
                        break
                    }
                }
            }
            
            if ($actionConfig) {
                $displayLabel = $actionConfig.display_label
                $actionDescription = $actionConfig.description
            }
            else {
                # フォールバック: 設定にない場合は元の値をそのまま使用
                $displayLabel = $cleanAction
                $actionDescription = $cleanAction
            }

            Write-SystemLog "$displayLabel ($actionDescription): $count 件" -Level "Info"
        }

        if ($totalSyncRecords -gt 0) {
            Write-SystemLog "同期処理総件数: $totalSyncRecords 件" -Level "Info"
        }
    }
}

Export-ModuleMember -Function 'Show-SyncResult'
