# PowerShell & SQLite データ同期システム
# CSV結果エクスポート処理モジュール

# 同期結果をCSVファイルにエクスポート（外部パス出力 + 履歴保存対応）
function Invoke-CsvExport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [string]$OutputFilePath
    )

    $filePathConfig = Get-FilePathConfig

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
        $query = New-SelectSql -TableName "sync_result" -OrderBy $firstKey

        # クエリ実行
        $recordCount = Invoke-SqliteCsvExport -DatabasePath $DatabasePath -Query $query -OutputPath $OutputFilePath

        Write-SystemLog "同期結果をCSVファイルに出力しました: $OutputFilePath ($recordCount 件)" -Level "Success"
    }

    # 履歴ファイルとしても出力（コピー）
    Invoke-WithErrorHandling -Category External -Operation "履歴ファイル出力" -ScriptBlock {
        # 履歴ディレクトリの作成
        if (-not (Test-Path $filePathConfig.output_history_directory)) {
            New-Item -ItemType Directory -Path $filePathConfig.output_history_directory -Force | Out-Null
            Write-SystemLog "履歴ディレクトリを作成しま       
            した: $filePathConfig.output_history_directory"  -Level "Success"
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