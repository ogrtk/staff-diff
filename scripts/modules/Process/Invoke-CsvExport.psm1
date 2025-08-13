# PowerShell & SQLite データ同期システム
# CSV結果エクスポート処理モジュール

# 同期結果をCSVファイルにエクスポート（外部パス出力 + 履歴保存対応）
function Invoke-CsvExport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [string]$OutputFilePath = ""
    )
    
    return Invoke-WithErrorHandling -Category External -Operation "同期結果CSVエクスポート処理" -Context @{
        "DatabasePath" = $DatabasePath
        "OutputFilePath" = $OutputFilePath
    } -ScriptBlock {
        
        $filePathConfig = Get-FilePathConfig
        
        # 出力ファイルパスの解決
        $resolvedOutputPath = ""
        if (-not [string]::IsNullOrEmpty($OutputFilePath) -or -not [string]::IsNullOrEmpty($filePathConfig.output_file_path)) {
            $resolvedOutputPath = Resolve-FilePath -ParameterPath $OutputFilePath -ConfigKey "output_file_path" -Description "出力ファイル"
        }
        else {
            Write-SystemLog "出力ファイルパスが指定されていません（履歴保存のみ実行）" -Level "Warning"
        }
        
        # 履歴ディレクトリの作成
        Invoke-WithErrorHandling -ScriptBlock {
            if (-not (Test-Path $filePathConfig.output_history_directory)) {
                New-Item -ItemType Directory -Path $filePathConfig.output_history_directory -Force | Out-Null
                Write-Host "履歴ディレクトリを作成しました: $filePathConfig.output_history_directory" -ForegroundColor Green
            }
        } -Category External -Operation "履歴ディレクトリ作成" -Context @{"ファイルパス" = $filePathConfig.output_history_directory; "操作種別" = "履歴ディレクトリ作成"} -CleanupScript {
            # ファイル操作特有のクリーンアップ
            if (Test-Path $filePathConfig.output_history_directory -ErrorAction SilentlyContinue) {
                $fileInfo = Get-Item $filePathConfig.output_history_directory -ErrorAction SilentlyContinue
                if ($fileInfo) {
                    Write-SystemLog "ファイル情報 - サイズ: $($fileInfo.Length) bytes, 最終更新: $($fileInfo.LastWriteTime)" -Level "Info"
                }
            }
        }

        # 履歴保存パス準備
        $historyFileName = New-HistoryFileName -BaseFileName "sync_result.csv"
        $historyPath = Join-Path $filePathConfig.output_history_directory $historyFileName
        
        # SQLクエリを1回だけ実行してデータを取得
        Write-SystemLog "同期結果データを取得中..." -Level "Info"
        $syncResultKeys = Get-TableKeyColumns -TableName "sync_result"
        $firstKey = if ($syncResultKeys -is [array]) { $syncResultKeys[0] } else { $syncResultKeys }
        $query = New-SelectSql -TableName "sync_result" -OrderBy $firstKey
        
        Write-SystemLog "結果をCSVファイルに出力中..." -Level "Info"
        if (-not [string]::IsNullOrEmpty($resolvedOutputPath)) {
            Write-SystemLog "ファイル パス（パラメータ指定）: $resolvedOutputPath" -Level "Info"
        }
        
        # パフォーマンス最適化: SQLite3から直接CSV出力（PSObject変換を完全に回避）
        $outputCount = 0
        
        # メイン出力（外部パス）
        if (-not [string]::IsNullOrEmpty($resolvedOutputPath)) {
            $recordCount = Invoke-WithErrorHandling -ScriptBlock {
                Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query -CsvOutput -CsvOutputPath $resolvedOutputPath
            } -Category External -Operation "メイン出力ファイル書き込み" -Context @{"コマンド名" = "sqlite3"; "操作種別" = "メイン出力ファイル書き込み"} -CleanupScript {
                # 外部コマンド特有のクリーンアップ
                Write-SystemLog "外部コマンドの終了コード: $LASTEXITCODE" -Level "Info"
                
                # コマンド可用性チェック
                $commandPath = Get-Command "sqlite3" -ErrorAction SilentlyContinue
                if ($commandPath) {
                    Write-SystemLog "コマンドパス: $($commandPath.Source)" -Level "Info"
                }
                else {
                    Write-SystemLog "コマンドが見つかりません: sqlite3" -Level "Warning"
                }
            }
            
            Write-SystemLog "同期結果をCSVファイルに出力しました: $resolvedOutputPath ($recordCount件)" -Level "Success"
            $outputCount++
        }
        
        # 履歴保存（data/output配下）
        $recordCount = Invoke-WithErrorHandling -ScriptBlock {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query -CsvOutput -CsvOutputPath $historyPath
        } -Category External -Operation "履歴ファイル書き込み" -Context @{"コマンド名" = "sqlite3"; "操作種別" = "履歴ファイル書き込み"} -CleanupScript {
            # 外部コマンド特有のクリーンアップ
            Write-SystemLog "外部コマンドの終了コード: $LASTEXITCODE" -Level "Info"
            
            # コマンド可用性チェック
            $commandPath = Get-Command "sqlite3" -ErrorAction SilentlyContinue
            if ($commandPath) {
                Write-SystemLog "コマンドパス: $($commandPath.Source)" -Level "Info"
            }
            else {
                Write-SystemLog "コマンドが見つかりません: sqlite3" -Level "Warning"
            }
        }
        
        Write-SystemLog "同期結果をCSVファイルに出力しました: $historyPath ($recordCount件)" -Level "Success"
        Write-SystemLog "履歴ファイルとして保存: $historyPath" -Level "Info"
        $outputCount++
        
        Write-SystemLog "同期結果出力完了: $outputCount ファイル" -Level "Success"
        
        return @{
            OutputCount = $outputCount
            MainOutputPath = $resolvedOutputPath
            HistoryPath = $historyPath
            RecordCount = $recordCount
        }
    }
}

Export-ModuleMember -Function 'Invoke-CsvExport'