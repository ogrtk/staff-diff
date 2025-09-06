# PowerShell & SQLite データ同期システム
# CSV結果エクスポート処理モジュール

using module "../Utils/Foundation/CoreUtils.psm1"
using module "../Utils/Infrastructure/LoggingUtils.psm1"
using module "../Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../Utils/DataAccess/DatabaseUtils.psm1"
using module "../Utils/DataAccess/FileSystemUtils.psm1"
using module "../Utils/DataProcessing/CsvProcessingUtils.psm1"
using module "../Utils/DataProcessing/DataFilteringUtils.psm1"

# 同期結果をCSVファイルにエクスポート（外部パス出力 + 履歴保存）
function Invoke-CsvExport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [string]$OutputFilePath
    )
    # グローバルキャッシュから既存設定を取得（テスト時の設定を保持）
    $config = Get-DataSyncConfig
    
    # ファイルパス設定を直接取得（Get-FilePathConfigは内部でGet-DataSyncConfigを呼び出すため使用しない）
    $filePathConfig = if ($config.file_paths) {
        $config.file_paths
    } else {
        @{
            output_history_directory = "./data/output/"
            timezone = "Asia/Tokyo"
        }
    }

    # 出力ファイルパスの解決
    if ([string]::IsNullOrEmpty($OutputFilePath)) {
        throw "出力ファイルパスが指定されていません"
    }
    
    # SQLiteから同期結果データを出力
    Invoke-WithErrorHandling -Category External -Operation "同期結果CSVエクスポート処理" -Context @{
        "DatabasePath"   = $DatabasePath
        "OutputFilePath" = $OutputFilePath
    } -ScriptBlock {
        # クエリ準備
        $syncResultKeys = Get-TableKeyColumns -TableName "sync_result"
        $firstKey = if ($syncResultKeys -is [array]) { $syncResultKeys[0] } else { $syncResultKeys }
        
        # フィルタリング条件を生成（既に読み込み済みの設定を使用）
        $whereClause = ""
        $syncActionLabels = $config.sync_rules.sync_action_labels.mappings
        
        $enabledActions = @()
        $disabledActions = @()
        
        foreach ($action in @('ADD', 'UPDATE', 'DELETE', 'KEEP')) {
            $actionSetting = $syncActionLabels.$action
            $isEnabled = $true  # デフォルトは有効
            
            if ($actionSetting -and $null -ne $actionSetting.enabled) {
                $isEnabled = $actionSetting.enabled
            }
            
            if ($isEnabled) {
                $enabledActions += "'$($actionSetting.value)'"
            }
            else {
                $disabledActions += "$action (設定元: sync_action_labels)"
            }
        }
        
        if ($enabledActions.Count -gt 0) {
            $whereClause = "sync_action IN ($($enabledActions -join ', '))"
            Write-SystemLog "出力フィルタリング適用: $whereClause" -Level "Info"
            if ($disabledActions.Count -gt 0) {
                Write-SystemLog "除外されたアクション: $($disabledActions -join ', ')" -Level "Info"
            }
        }
        else {
            $whereClause = "1=0"  # 全て除外
            Write-SystemLog "全ての同期アクションが無効化されています: $($disabledActions -join ', ')" -Level "Warning"
        }
        
        $query = New-SelectSql -TableName "sync_result" -WhereClause $whereClause -OrderBy $firstKey

        # クエリ実行
        $recordCount = Invoke-SqliteCsvExport -DatabasePath $DatabasePath -Query $query -OutputPath $OutputFilePath

        Write-SystemLog "同期結果をCSVファイルに出力しました: $OutputFilePath ($recordCount 件)" -Level "Success"
    }

    # 履歴ファイルとしても出力（コピー）
    Invoke-WithErrorHandling -Category External -Operation "履歴ファイル出力" -ScriptBlock {
        # 履歴ディレクトリの作成
        if (-not (Test-Path $filePathConfig.output_history_directory)) {
            New-Item -ItemType Directory -Path $filePathConfig.output_history_directory -Force | Out-Null
            Write-SystemLog "履歴ディレクトリを作成しました: $($filePathConfig.output_history_directory)" -Level "Success"
        }
        # 履歴保存パス準備（OutputFilePathのファイル名を使用）
        $baseFileName = Split-Path -Leaf $OutputFilePath
        $historyFileName = New-HistoryFileName -BaseFileName $baseFileName
        $historyPath = Join-Path $filePathConfig.output_history_directory $historyFileName
        Copy-Item -Path $OutputFilePath -Destination $historyPath -Force

        Write-SystemLog "同期結果を履歴フォルダに出力しました: $historyPath" -Level "Success"
    }
}

Export-ModuleMember -Function 'Invoke-CsvExport'