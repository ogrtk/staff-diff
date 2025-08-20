# PowerShell & SQLite データ同期システム
# 統合同期結果表示モジュール

using module "../Utils/Foundation/CoreUtils.psm1"
using module "../Utils/Infrastructure/LoggingUtils.psm1"
using module "../Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../Utils/DataAccess/DatabaseUtils.psm1"
using module "../Utils/DataAccess/FileSystemUtils.psm1"
using module "../Utils/DataProcessing/CsvProcessingUtils.psm1"
using module "../Utils/DataProcessing/DataFilteringUtils.psm1"

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
        Write-SystemLog "=== 同期処理完了レポート ===" -Level "Info" -ConsoleColor "Magenta" 
        
        # 1. 実行情報セクション
        Write-SystemLog "--- 実行情報 ---" -Level "Info" -ConsoleColor "Magenta" 
        Write-SystemLog "データベースファイル: $DatabasePath" -Level "Info" -ConsoleColor "Magenta" 
        Write-SystemLog "提供データファイル: $ProvidedDataFilePath" -Level "Info" -ConsoleColor "Magenta" 
        Write-SystemLog "現在データファイル: $CurrentDataFilePath" -Level "Info" -ConsoleColor "Magenta" 
        
        $config = Get-DataSyncConfig
        Write-SystemLog "設定バージョン: $($config.version)" -Level "Info" -ConsoleColor "Magenta" 
        $japanTime = [DateTime]::UtcNow.AddHours(9).ToString('yyyy-MM-dd HH:mm:ss')  
        Write-SystemLog "実行時刻: $japanTime" -Level "Info" -ConsoleColor "Magenta" 
        
        # sync_action_labels設定を取得
        $syncActionLabels = $config.sync_rules.sync_action_labels.mappings
        
        # 2. データ統計セクション
        Write-SystemLog "--- データ統計 ---" -Level "Info" -ConsoleColor "Magenta" 
        
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
            Write-SystemLog "$($tableResult.table_name): $($tableResult.count) 件" -Level "Info" -ConsoleColor "Magenta" 
        }
        
        # 3. 同期結果セクション
        Write-SystemLog "--- 同期結果 ---" -Level "Info" -ConsoleColor "Magenta" 
        
        # 設定から動的にORDER BY句を生成
        $syncActionLabels = $config.sync_rules.sync_action_labels.mappings
        
        $orderByCases = @()
        $displayOrder = 1
        
        foreach ($actionKey in $syncActionLabels.PSObject.Properties.Name) {
            $actionConfig = $syncActionLabels.$actionKey
            $actionName = $actionConfig.value
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
            
            # データベースには数値（1, 2等）が格納されているので、
            # 設定ファイルのvalueと一致するものを検索
            foreach ($key in $syncActionLabels.PSObject.Properties.Name) {
                if ($syncActionLabels.$key.value -eq $cleanAction) {
                    $actionConfig = $syncActionLabels.$key
                    break
                }
            }
            
            if ($actionConfig) {
                $displayLabel = $actionConfig.value
                $actionDescription = $actionConfig.description
            }
            else {
                # フォールバック: 設定にない場合は元の値をそのまま使用
                $displayLabel = $cleanAction
                $actionDescription = $cleanAction
            }

            Write-SystemLog "$actionDescription ($displayLabel): $count 件" -Level "Info" -ConsoleColor "Magenta" 
        }

        if ($totalSyncRecords -gt 0) {
            Write-SystemLog "同期処理総件数: $totalSyncRecords 件" -Level "Info" -ConsoleColor "Magenta" 
        }
    }
}

Export-ModuleMember -Function 'Show-SyncResult'
