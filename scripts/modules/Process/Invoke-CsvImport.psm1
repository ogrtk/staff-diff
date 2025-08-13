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
    Import-CsvToTable -CsvPath $CsvPath -DatabasePath $DatabasePath -TableName $config.TableName -HistoryDirectory $config.HistoryDirectory -FileTypeDescription $config.Description
    Write-SystemLog "$($config.Description)のインポート処理が完了しました" -Level "Success"
}

# 汎用CSVインポート関数（単一ファイル + 履歴保存対応）
function script:Import-CsvToTable {
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
            
    # 履歴ディレクトリにコピー保存
    Invoke-WithErrorHandling -Category External -Operation "履歴ファイルコピー" -ScriptBlock {
        Copy-InputFileToHistory -SourceFilePath $CsvPath -HistoryDirectory $HistoryDirectory
    }

    # ヘッダー無しCSVの場合、ヘッダーを付与した一時ファイルを作成
    $processingCsvPath = $CsvPath
    $tempHeaderFile = $null

    $formatConfig = Get-CsvFormatConfig -TableName $TableName
    if ($formatConfig.has_header -eq $false) {
        $tempHeaderFile = Invoke-WithErrorHandling -Category External -Operation "ヘッダ付きCSVファイル作成" -ScriptBlock {
            Add-CsvHeader -CsvPath $CsvPath -TableName $TableName
        }
        $processingCsvPath = $tempHeaderFile
        Write-SystemLog "ヘッダー付きファイル作成完了: $processingCsvPath" -Level "Info"
    }
            
    # 一時ファイルのクリーンアップ処理（冪等性対応強化）
    $csvCleanupScript = {
        # 一時ヘッダーファイルのクリーンアップ
        if ($tempHeaderFile -and (Test-Path $tempHeaderFile)) {
            Remove-Item $tempHeaderFile -Force -ErrorAction SilentlyContinue
            Write-SystemLog "一時ヘッダーファイルを削除しました: $tempHeaderFile" -Level "Info"
        }
            
        # 同名パターンの孤立一時ファイルもクリーンアップ
        try {
            $tempDir = [System.IO.Path]::GetTempPath()
            $baseFileName = [System.IO.Path]::GetFileNameWithoutExtension($CsvPath)
            $tempPattern = "${baseFileName}_with_header_*.csv"
            $orphanFiles = Get-ChildItem -Path $tempDir -Filter $tempPattern -ErrorAction SilentlyContinue
                
            foreach ($file in $orphanFiles) {
                # 作成から1時間以上経過した孤立ファイルを削除
                if ($file.CreationTime -lt (Get-Date).AddHours(-1)) {
                    Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                    Write-SystemLog "孤立一時ファイルを削除しました: $($file.FullName)" -Level "Info"
                }
            }
        }
        catch {
            Write-SystemLog "一時ファイルクリーンアップ中にエラー: $($_.Exception.Message)" -Level "Warning"
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
    return $statistics
}

# ヘッダー無しCSVファイルにヘッダーを付与する関数
function script:Add-CsvHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    Write-SystemLog "ヘッダ無しCSVファイルにヘッダーを付与。付与対象ファイル: $CsvPath (テーブル: $TableName)" -Level "Info"
    
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
    
    Write-SystemLog "ヘッダー付きCSVファイルを作成完了: $tempPath" -Level "Success"
    
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
        
        [bool]$ShowStatistics = $true,
        [switch]$ShowConfig = $false
    )
    
        
    if ($ShowConfig) {
        Show-FilterConfig -TableName $TableName
    }
        
    Write-SystemLog "フィルタリング用に一時テーブルへCSVをインポートする: $TableName ($CsvFilePath)" -Level "Info"

    # 一時テーブル名
    $tempTableName = New-TempTableName -BaseTableName $TableName

    # リトライ対応: 既存データをクリア
    Clear-Table -DatabasePath $DatabasePath -TableName $TableName

    # CSVファイルの件数を事前に取得
    $csvData = Import-Csv -Path $CsvFilePath
    $totalRecords = $csvData.Count
        
    Write-Host "CSVファイル読み込み完了: $totalRecords 件" -ForegroundColor Green
        
    # 1. 一時テーブル作成
    # 既存の一時テーブルがある場合はDROP
    $dropTempTableIfExistsSql = "DROP TABLE IF EXISTS $tempTableName;"
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $dropTempTableIfExistsSql
    Write-SystemLog "既存の一時テーブルを削除しました (もしあれば): $tempTableName" -Level "Info"

    $createTempTableSql = New-CreateTempTableSql -BaseTableName $TableName -TempTableName $tempTableName
    Write-SystemLog "一時テーブル作成: $tempTableName" -Level "Info"
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $createTempTableSql

    # 2. CSVデータを一時テーブルに直接インポート
    Write-Host "CSVデータを一時テーブルに直接インポート中..." -ForegroundColor Cyan
    $importResult = Import-CsvToSqliteTable -CsvFilePath $CsvFilePath -DatabasePath $DatabasePath -TableName $tempTableName
    if (-not $importResult) {
        throw "CSVファイルの一時テーブルへのインポートに失敗しました"
    }
        
    # 3. フィルタ用WHERE句生成
    $whereClause = New-FilterWhereClause -TableName $TableName
        
    # 4-6. フィルタ済みデータ移行、統計取得、クリーンアップ
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
        Invoke-WithErrorHandling -ScriptBlock {
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $indexSql
        } -Category External -Operation "インデックス作成" -Context @{"コマンド名" = "sqlite3"; "操作種別" = "インデックス作成" } -CleanupScript {
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
    }
        
    # 統計表示
    if ($ShowStatistics) {
        $whereClauseForDisplay = if ($whereClause) { $whereClause } else { "" }
        Show-FilteringStatistics -TableName $TableName -TotalCount $totalRecords -FilteredCount $filteredCount -WhereClause $whereClauseForDisplay
    }
        
    Write-SystemLog "SQLベースフィルタリング完了: $filteredCount 件を $TableName に挿入" -Level "Success"
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
    
    $context = @{
        "コマンド名" = "sqlite3"
        "操作種別"  = "CSV直接インポート ($TableName)"
    }
    
    $cleanupScript = {
        Write-SystemLog "外部コマンドの終了コード: $LASTEXITCODE" -Level "Info"
        
        $commandPath = Get-Command "sqlite3" -ErrorAction SilentlyContinue
        if ($commandPath) {
            Write-SystemLog "コマンドパス: $($commandPath.Source)" -Level "Info"
        }
        else {
            Write-SystemLog "コマンドが見つかりません: sqlite3" -Level "Warning"
        }
    }
    
    return Invoke-WithErrorHandling -ScriptBlock {
        if (-not (Test-Path $CsvFilePath)) {
            throw "CSVファイルが見つかりません: $CsvFilePath"
        }
        
        # SQLite3の.importコマンドを使用した直接インポート
        $result = & sqlite3 $DatabasePath ".mode csv" ".import `"$CsvFilePath`" $TableName" 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "SQLite .import エラー (終了コード: $LASTEXITCODE): $result"
        }
        
        Write-SystemLog "CSV直接インポート完了: $TableName" -Level "Success"
        return $true
        
    } -Category External -Operation "CSV直接インポート ($TableName)" -Context $context -CleanupScript $cleanupScript
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
