# PowerShell & SQLite データ管理システム
# CSVデータインポート処理スクリプト（レイヤー化版）

# 統合されたデータインポート関数（冪等性対応）
function Invoke-CsvImport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [ValidateSet("provided_data", "current_data")]
        [string]$DataType
    )
    
    $filePathConfig = Get-FilePathConfig
    
    # データタイプに応じた設定を取得
    $config = switch ($DataType) {
        "provided_data" {
            @{
                TableName        = "provided_data"
                HistoryDirectory = $filePathConfig.provided_data_history_directory
                Description      = "提供データ"
            }
        }
        "current_data" {
            @{
                TableName        = "current_data" 
                HistoryDirectory = $filePathConfig.current_data_history_directory
                Description      = "現在データ"
            }
        }
    }
    
    Write-SystemLog "$($config.Description)のインポート処理を開始します" -Level "Info"
    Invoke-CsvImportMain -CsvPath $CsvPath -DatabasePath $DatabasePath -TableName $config.TableName -HistoryDirectory $config.HistoryDirectory -FileTypeDescription $config.Description
    Write-SystemLog "$($config.Description)のインポート処理が完了しました" -Level "Success"
}

# 汎用CSVインポート関数（単一ファイル + 履歴保存対応）
function script:Invoke-CsvImportMain {
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
        
    Write-SystemLog "処理対象ファイル ${FileTypeDescription}CSV: $CsvPath" -Level "Info"
    
    # 履歴ディレクトリにコピー保存(リトライ考慮無し)
    $historyFilePath = Invoke-WithErrorHandling -Category External -Operation "履歴ファイルコピー" -ScriptBlock {
        return Copy-InputFileToHistory -SourceFilePath $CsvPath -HistoryDirectory $HistoryDirectory
    }

    # ヘッダー無しCSVの場合、ヘッダーを付与した一時ファイルを作成
    $processingCsvPath = $CsvPath
    $tempHeaderFile = $null

    $formatConfig = Get-CsvFormatConfig -TableName $TableName
    if ($formatConfig.has_header -eq $false) {
        $tempHeaderFile = Invoke-WithErrorHandling -Category External -Operation "ヘッダ付き一時CSVファイル作成" -ScriptBlock {
            New-TempCsvWithHeader -CsvPath $CsvPath -TableName $TableName
        }
        $processingCsvPath = $tempHeaderFile
        Write-SystemLog "ヘッダー付きファイル作成完了: $processingCsvPath" -Level "Info"
    }

    # 作成したファイルのクリーンアップ処理（冪等性対応）
    $csvCleanupScript = {
        if ($historyFilePath -and (Test-Path $historyFilePath)) {
            Remove-Item $historyFilePath -Force -ErrorAction SilentlyContinue
            Write-SystemLog "履歴ファイルを削除しました: $historyFilePath" -Level "Info"
        }
        if ($tempHeaderFile -and (Test-Path $tempHeaderFile)) {
            Remove-Item $tempHeaderFile -Force -ErrorAction SilentlyContinue
            Write-SystemLog "一時ヘッダーファイルを削除しました: $tempHeaderFile" -Level "Info"
        }
    }

    # CSVフォーマットの検証
    Write-SystemLog "CSVフォーマットの検証開始" -Level "Info"
    Invoke-WithErrorHandling -Category System -Operation "CSVフォーマットの検証" -CleanupScript $csvCleanupScript -ScriptBlock {
        if (-not (Test-CsvFormat -CsvPath $processingCsvPath -TableName $TableName)) {
            throw "CSVフォーマットの検証に失敗しました"
        }    
    }
                
    # データフィルタリング
    Write-SystemLog "データフィルタリング処理開始" -Level "Info"
    $statistics = Invoke-WithErrorHandling -Category External -Operation "データフィルタリング処理" -CleanupScript $csvCleanupScript -ScriptBlock {
        Invoke-Filtering -DatabasePath $DatabasePath -TableName $TableName -CsvFilePath $processingCsvPath -ShowStatistics:$true
    }

    # 一時ファイルクリーンアップ実行
    & $csvCleanupScript

    Write-SystemLog "${FileTypeDescription}CSVのインポートが完了しました。処理件数: $($statistics.FilteredCount) / 読み込み件数: $($statistics.TotalCount)" -Level "Success"
}

# ヘッダー付き一時CSVファイルを作成する関数（クリーンアップ機能付き）
function script:New-TempCsvWithHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    Write-SystemLog "ヘッダー付き一時CSVファイルを作成。元ファイル: $CsvPath (テーブル: $TableName)" -Level "Info"
    
    # 古い一時ファイルのクリーンアップ（処理開始時）
    try {
        $tempDir = [System.IO.Path]::GetTempPath()
        $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
        $tempPattern = "${baseFileName}_with_header_*.csv"
        $orphanFiles = Get-ChildItem -Path $tempDir -Filter $tempPattern -ErrorAction SilentlyContinue

        foreach ($file in $orphanFiles) {
            # 作成から1時間以上経過した孤立ファイルを削除
            if ($file.CreationTime -lt (Get-Date).AddHours(-1)) {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                Write-SystemLog "古い一時ファイルを削除しました: $($file.FullName)" -Level "Info"
            }
        }
    }
    catch {
        Write-SystemLog "古い一時ファイルクリーンアップ中にエラー: $($_.Exception.Message)" -Level "Warning"
    }
    
    # テーブル定義からCSVカラムを取得
    $tableColumns = Get-CsvColumns -TableName $TableName
    
    if (-not $tableColumns -or $tableColumns.Count -eq 0) {
        throw "テーブル '$TableName' のCSVカラム定義が見つかりません"
    }
    
    Write-SystemLog "生成するヘッダー: $($tableColumns -join ', ')" -Level "Info"
    
    # 一時ファイルパスを生成
    $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
    $extension = [System.IO.Path]::GetExtension($CsvPath)
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $tempFileName = "${baseFileName}_with_header_${timestamp}${extension}"
    $tempPath = Join-Path ([System.IO.Path]::GetTempPath()) $tempFileName
    
    Write-SystemLog "一時ファイルパス: $tempPath" -Level "Info"
    # 一時ファイルパスにファイルが存在する場合は一旦削除する
    if (Test-Path $tempPath) {
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
        Write-SystemLog "既存の一時ファイルを削除しました: $tempPath" -Level "Info"
    }

    # CSVフォーマット設定を取得
    $formatConfig = Get-CsvFormatConfig -TableName $TableName
    $encoding = ConvertTo-PowerShellEncoding -EncodingName $formatConfig.encoding
    
    # ヘッダー行を作成
    $headerLine = $tableColumns -join $formatConfig.delimiter
    
    # ヘッダー行を一時ファイルに書き込み
    $headerLine | Out-File -FilePath $tempPath -Encoding $encoding -NoNewline
    
    # 改行文字を追加
    switch ($formatConfig.newline.ToUpper()) {
        "LF" { "`n" | Out-File -FilePath $tempPath -Encoding $encoding -Append -NoNewline }
        "CR" { "`r" | Out-File -FilePath $tempPath -Encoding $encoding -Append -NoNewline }
        default { "`r`n" | Out-File -FilePath $tempPath -Encoding $encoding -Append -NoNewline }
    }
    
    # 元のCSVファイルの内容を追加
    $originalContent = Get-Content -Path $CsvPath -Encoding $encoding -Raw
    if ($originalContent) {
        $originalContent | Out-File -FilePath $tempPath -Encoding $encoding -Append -NoNewline
    }
    
    Write-SystemLog "ヘッダー付き一時CSVファイルを作成完了: $tempPath" -Level "Success"
    
    return $tempPath
}

# SQLベースフィルタリング（processing層実装）
function script:Invoke-Filtering {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath,
        
        [bool]$ShowStatistics = $true
    )
    
    Write-SystemLog "フィルタリング用に一時テーブルへCSVをインポート: $TableName ($CsvFilePath)" -Level "Info"

    # リトライ対応: 既存データをクリア
    Clear-Table -DatabasePath $DatabasePath -TableName $TableName

    # CSVファイルの件数を事前に取得
    $csvData = Import-Csv -Path $CsvFilePath
    $totalRecords = $csvData.Count
    Write-SystemLog "フィルタリング前: $totalRecords 件" -Level "Success"
        
    # 1. 一時テーブル作成
    # 一時テーブル名
    $tempTableName = New-TempTableName -BaseTableName $TableName
    # 既存の一時テーブルがある場合はDROP
    $dropTempTableIfExistsSql = "DROP TABLE IF EXISTS $tempTableName;"
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $dropTempTableIfExistsSql
    Write-SystemLog "既存の一時テーブルを削除しました: $tempTableName" -Level "Info"

    $createTempTableSql = New-CreateTempTableSql -BaseTableName $TableName -TempTableName $tempTableName
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $createTempTableSql
    Write-SystemLog "一時テーブルを作成しました: $tempTableName" -Level "Info"

    # 2. CSVデータを一時テーブルにインポート
    Import-CsvToSqliteTable -CsvFilePath $CsvFilePath -DatabasePath $DatabasePath -TableName $tempTableName
    Write-SystemLog "CSVデータを一時テーブルにインポートしました: $tempTableName" -Level "Info"
        
    # 3. フィルタ済みデータ移行
    $whereClause = New-FilterWhereClause -TableName $TableName
    $filteredInsertSql = New-FilteredInsertSql -TargetTableName $TableName -SourceTableName $tempTableName -WhereClause $whereClause
    $statisticsSql = "SELECT COUNT(*) as filtered_count FROM $TableName;"
    $dropTempTableSql = "DROP TABLE $tempTableName;"
        
    $filteringAndCleanupSql = @"
BEGIN TRANSACTION;
$filteredInsertSql
$statisticsSql
$dropTempTableSql
COMMIT;
"@
        
    Write-SystemLog "フィルタリングとクリーンアップ実行中..." -Level "Info"
    $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $filteringAndCleanupSql
        
    # 結果から件数を取得
    $filteredCount = if ($result -is [array] -and $result.Count -gt 0) { 
        # 最後の統計クエリの結果を取得
        [int]($result | Select-Object -Last 1)
    }
    else { 
        [int]$result 
    }
        
    # 動的インデックス作成（レコード数に基づく判定）
    $indexSqls = New-CreateIndexSql -TableName $TableName -RecordCount $filteredCount
    foreach ($indexSql in $indexSqls) {
        Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $indexSql
    }
        
    # 統計表示
    if ($ShowStatistics) {
        $whereClauseForDisplay = if ($whereClause) { $whereClause } else { "" }
        Show-FilteringStatistics -TableName $TableName -TotalCount $totalRecords -FilteredCount $filteredCount -WhereClause $whereClauseForDisplay
    }
        
    Write-SystemLog "SQLベースフィルタリング完了: $filteredCount 件を $TableName に挿入" -Level "Success"
    
    # 統計情報を返す
    return @{
        TotalCount    = $totalRecords
        FilteredCount = $filteredCount
        TableName     = $TableName
    }
}

# CSV直接インポート関数（SQLite .importコマンド使用）
function script:Import-CsvToSqliteTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    
    if (-not (Test-Path $CsvFilePath)) {
        throw "CSVファイルが見つかりません: $CsvFilePath"
    }
        
    # SQLite3の.importコマンドを使用した直接インポート
    $result = & sqlite3 $DatabasePath ".mode csv" ".import `"$CsvFilePath`" $TableName" 2>&1
        
    if ($LASTEXITCODE -ne 0) {
        throw "SQLite .import エラー (終了コード: $LASTEXITCODE): $result"
    }
        
    Write-SystemLog "CSV直接インポート完了: $TableName" -Level "Success"
}

# 一時テーブル作成SQL生成
function New-CreateTempTableSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseTableName,
        
        [Parameter(Mandatory = $true)]
        [string]$TempTableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $BaseTableName
    
    $columns = @()
    foreach ($column in $tableDefinition.columns) {
        if ($column.csv_include -eq $true) {
            $columnDef = "$($column.name) $($column.type)"
            $columns += $columnDef
        }
    }
    
    $sql = "CREATE TEMP TABLE $TempTableName (`n"
    $sql += "    " + ($columns -join ",`n    ") + "`n"
    $sql += ");"
    
    return $sql
}

Export-ModuleMember -Function 'Invoke-CsvImport'
