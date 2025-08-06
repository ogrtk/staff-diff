# PowerShell & SQLite 職員データ管理システム
# CSV処理ユーティリティスクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")
. (Join-Path $PSScriptRoot "sql-utils.ps1")
. (Join-Path $PSScriptRoot "file-utils.ps1")
. (Join-Path $PSScriptRoot "data-filter-utils.ps1")
. (Join-Path $PSScriptRoot "common-utils.ps1")

# 汎用CSVインポート関数（単一ファイル + 履歴保存対応）
function Import-CsvToTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryDirectory,
        
        [Parameter(Mandatory = $true)]
        [string]$FileTypeDescription
    )
    
    if (-not (Test-Path $CsvPath)) {
        throw "CSVファイルが見つかりません: $CsvPath"
    }
    
    try {
        Write-SystemLog "${FileTypeDescription}CSVをインポート中: $CsvPath" -Level "Info"
        
        # 履歴ディレクトリにコピー保存
        Copy-InputFileToHistory -SourceFilePath $CsvPath -HistoryDirectory $HistoryDirectory
        
        # CSVフォーマットの検証
        if (-not (Test-CsvFormat -CsvPath $CsvPath -TableName $TableName)) {
            throw "CSVフォーマットの検証に失敗しました"
        }
        
        # CSVファイルを読み込み（クロスプラットフォーム対応）
        $csvData = Import-CsvCrossPlatform -Path $CsvPath
        
        # データフィルタリングを適用
        $filteredData = Invoke-DataFiltering -TableName $TableName -DataArray $csvData
        
        # 設定ベースでフィルタリング済みデータをデータベースに高速挿入
        # 件数に関係なく常にバルクインポートを使用（最高の性能とコードの単純化）
        Write-SystemLog "バルクインポートを実行中: $($filteredData.Count)件" -Level "Info"
        Invoke-BulkImport -DatabasePath $DatabasePath -TableName $TableName -Data $filteredData
        
        Write-SystemLog "${FileTypeDescription}CSVのインポートが完了しました。処理件数: $($filteredData.Count) / 読み込み件数: $($csvData.Count)" -Level "Success"
        
    }
    catch {
        Write-SystemLog "${FileTypeDescription}CSVのインポートに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# SQLiteバルクインポート関数
function Invoke-BulkImport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        $Data
    )
    
    try {
        # 一時CSVファイルを作成
        $tempCsvFile = [System.IO.Path]::GetTempFileName() + ".csv"
        
        # CSV形式でデータを出力（設定ベースのカラム順序）
        $csvColumns = Get-CsvColumns -TableName $TableName
        $headerString = $csvColumns -join ","
        
        # ヘッダー行を書き込み
        $headerString | Out-File -FilePath $tempCsvFile -Encoding UTF8
        
        # データ行を書き込み
        foreach ($row in $Data) {
            $values = @()
            foreach ($column in $csvColumns) {
                $value = if ($row.$column) { $row.$column } else { "" }
                # CSV形式でエスケープ（カンマとダブルクォートを含む場合）
                if ($value -match '[",]') {
                    $value = '"' + ($value -replace '"', '""') + '"'
                }
                $values += $value
            }
            $csvLine = $values -join ","
            $csvLine | Out-File -FilePath $tempCsvFile -Encoding UTF8 -Append
        }
        
        # SQLiteバルクインポート: カラム指定版で実行
        $csvColumns = Get-CsvColumns -TableName $TableName
        $columnList = $csvColumns -join ", "
        
        $importCommand = @"
.mode csv
.import "$tempCsvFile" temp_import_table
INSERT INTO $TableName ($columnList) SELECT * FROM temp_import_table;
DROP TABLE temp_import_table;
"@
        
        # sqlite3コマンドを実行（echo経由で標準入力に渡す）
        $output = $importCommand | & sqlite3 $DatabasePath 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "SQLiteバルクインポートに失敗しました: $output"
        }
        
        Write-SystemLog "バルクインポートが完了しました: $($Data.Count)件" -Level "Success"
        
    }
    catch {
        Write-SystemLog "バルクインポートに失敗、個別INSERTにフォールバック: $($_.Exception.Message)" -Level "Warning"
        
        # フォールバック: 個別INSERT
        foreach ($row in $Data) {
            $data = ConvertTo-DataHashtable -InputObject $row
            $query = New-InsertSql -TableName $TableName -Data $data
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
        }
    }
    finally {
        # 一時ファイルを削除
        if ($tempCsvFile -and (Test-Path $tempCsvFile)) {
            Remove-Item $tempCsvFile -Force -ErrorAction SilentlyContinue
        }
    }
}

# 職員情報CSVをデータベースにインポート（汎用関数使用）
function Import-ProvidedDataCsv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $filePathConfig = Get-FilePathConfig
    Import-CsvToTable -CsvPath $CsvPath -DatabasePath $DatabasePath -TableName "provided_data" -HistoryDirectory $filePathConfig.provided_data_history_directory -FileTypeDescription "提供データ"
}

# 職員マスタCSVをデータベースにインポート（汎用関数使用）
function Import-CurrentDataCsv {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $filePathConfig = Get-FilePathConfig
    Import-CsvToTable -CsvPath $CsvPath -DatabasePath $DatabasePath -TableName "current_data" -HistoryDirectory $filePathConfig.current_data_history_directory -FileTypeDescription "現在データ"
}

# 同期結果をCSVファイルにエクスポート（外部パス出力 + 履歴保存対応）
function Export-SyncResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [string]$OutputFilePath = ""
    )
    
    try {
        $filePathConfig = Get-FilePathConfig
        
        # 出力ファイルパスの解決
        $resolvedOutputPath = ""
        if (-not [string]::IsNullOrEmpty($OutputFilePath) -or -not [string]::IsNullOrEmpty($filePathConfig.output_file_path)) {
            $resolvedOutputPath = Resolve-FilePath -ParameterPath $OutputFilePath -ConfigPath $filePathConfig.output_file_path -FileType "出力ファイル" -FileMode "Output"
        }
        else {
            Write-SystemLog "出力ファイルパスが指定されていません（履歴保存のみ実行）" -Level "Warning"
        }
        
        # メイン出力（外部パス）
        if (-not [string]::IsNullOrEmpty($resolvedOutputPath)) {
            Export-SyncResultToFile -DatabasePath $DatabasePath -OutputPath $resolvedOutputPath
        }
        
        # 履歴保存（data/output配下）
        $historyFileName = New-HistoryFileName -BaseFileName "synchronized_staff.csv"
        $historyPath = Join-Path $filePathConfig.output_history_directory $historyFileName
        Export-SyncResultToFile -DatabasePath $DatabasePath -OutputPath $historyPath
        Write-SystemLog "履歴ファイルとして保存: $historyPath" -Level "Info"
        
        # 結果の統計情報を表示
        Show-SyncStatistics -DatabasePath $DatabasePath
        
    }
    catch {
        Write-SystemLog "CSVファイルの出力に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 同期結果をファイルにエクスポート（内部関数）
function Export-SyncResultToFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath
    )
    
    try {
        # 出力ディレクトリが存在しない場合は作成
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # 設定ベースで同期結果を取得
        $syncResultKeys = Get-TableKeyColumns -TableName "sync_result"
        # 配列として強制的に扱い、最初の要素を安全に取得
        $firstKey = if ($syncResultKeys -is [array]) { $syncResultKeys[0] } else { $syncResultKeys }
        $query = New-SelectSql -TableName "sync_result" -OrderBy $firstKey
        
        # SQLite結果をCSVとして直接エクスポート
        $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if ($sqlite3Path) {
            # データベースロック回避のため少し待機
            Start-Sleep -Milliseconds 500
            # 設定ベースでCSVヘッダーを生成
            $headers = New-CsvHeader -TableName "sync_result"
            $headerString = $headers -join ","
            Out-FileCrossPlatform -FilePath $OutputPath -Content $headerString
            
            $sqliteOutput = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $query
            # CSVオブジェクトを行に変換して出力
            foreach ($row in $sqliteOutput) {
                if ($row) {
                    $csvLine = ($headers | ForEach-Object { $row.$_ }) -join ","
                    Out-FileCrossPlatform -FilePath $OutputPath -Content $csvLine -Append
                }
            }
        }
        else {
            # PowerShellでの処理
            $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
            Export-CsvCrossPlatform -InputObject $result -Path $OutputPath -NoTypeInformation
        }
        
        Write-SystemLog "同期結果をCSVファイルに出力しました: $OutputPath" -Level "Success"
        
    }
    catch {
        Write-SystemLog "CSVファイルの出力に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 同期統計情報の表示
function Show-SyncStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    try {
        $statsQuery = @"
SELECT 
    sync_action,
    COUNT(*) as count
FROM sync_result
GROUP BY sync_action;
"@
        
        # SQLite CSV形式で結果を取得
        $result = Invoke-SqliteCsvQuery -DatabasePath $DatabasePath -Query $statsQuery
        
        Write-Host "`n=== 同期処理統計 ===" -ForegroundColor Yellow
        if ($result -and $result.Count -gt 0) {
            foreach ($line in $result) {
                if ($line) {
                    $parts = $line -split ','
                    if ($parts.Count -eq 2) {
                        Write-Host "$($parts[0]): $($parts[1])件" -ForegroundColor White
                    }
                }
            }
        }
        else {
            Write-Host "統計データがありません" -ForegroundColor Gray
        }
        Write-Host "=====================" -ForegroundColor Yellow
        
    }
    catch {
        Write-Warning "統計情報の取得に失敗しました: $($_.Exception.Message)"
    }
}

# CSVファイルのバリデーション（設定ベース版）
function Test-CsvFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        $csvData = Import-CsvCrossPlatform -Path $CsvPath
        
        # 空のCSVファイルチェック
        if (-not $csvData -or $csvData.Count -eq 0) {
            Write-SystemLog "CSVファイルが空です: $(Split-Path -Leaf $CsvPath)" -Level "Warning"
            return $false
        }
        
        # ヘッダー取得（最初の行から）
        $headers = @()
        $firstRow = $csvData[0]
        if ($firstRow -and $firstRow.PSObject.Properties) {
            $headers = $firstRow.PSObject.Properties.Name
        }
        
        if ($headers.Count -eq 0) {
            Write-SystemLog "CSVファイルにヘッダーが見つかりません: $(Split-Path -Leaf $CsvPath)" -Level "Warning"
            return $false
        }
        
        # 設定ベースで必要カラムを取得
        $requiredColumns = Get-RequiredColumns -TableName $TableName
        
        $missingColumns = $requiredColumns | Where-Object { $_ -notin $headers }
        
        if ($missingColumns.Count -gt 0) {
            Write-SystemLog "必要なカラムが不足しています: $($missingColumns -join ', ')" -Level "Warning"
            Write-SystemLog "実際のヘッダー: $($headers -join ', ')" -Level "Info"
            return $false
        }
        
        Write-SystemLog "CSVフォーマットの検証が完了しました: $(Split-Path -Leaf $CsvPath) (行数: $($csvData.Count))" -Level "Success"
        return $true
        
    }
    catch {
        Write-SystemLog "CSVファイルの検証に失敗しました: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}