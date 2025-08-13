# PowerShell & SQLite 職員データ管理システム
# CSV処理ユーティリティスクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")
. (Join-Path $PSScriptRoot "sql-utils.ps1")
. (Join-Path $PSScriptRoot "file-utils.ps1")
. (Join-Path $PSScriptRoot "data-filter-utils.ps1")
. (Join-Path $PSScriptRoot "common-utils.ps1")

# CSVフォーマット設定取得関数
function Get-CsvFormatConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        $config = Get-DataSyncConfig
        
        # 出力用は sync_result → output にマップ
        $configKey = if ($TableName -eq "sync_result") { "output" } else { $TableName }
        
        if (-not $config.csv_format -or -not $config.csv_format.$configKey) {
            throw "CSVフォーマット設定が見つかりません: $TableName (設定キー: $configKey)"
        }
        
        return $config.csv_format.$configKey
    }
    catch {
        Write-SystemLog "CSVフォーマット設定の取得に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# エンコーディング名をPowerShell形式に変換
function ConvertTo-PowerShellEncoding {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EncodingName
    )
    
    switch ($EncodingName.ToUpper()) {
        "UTF-8" { return "UTF8" }
        "UTF-16" { return "Unicode" }
        "UTF-16BE" { return "BigEndianUnicode" }
        "UTF-32" { return "UTF32" }
        "SHIFT_JIS" { return "Shift_JIS" }
        "EUC-JP" { return "EUC-JP" }
        "ASCII" { return "ASCII" }
        "ISO-8859-1" { return "Latin1" }
        default { 
            Write-SystemLog "未サポートのエンコーディング: $EncodingName。UTF8を使用します。" -Level "Warning"
            return "UTF8" 
        }
    }
}

# 改行コード変換関数
function ConvertTo-NewlineFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        
        [Parameter(Mandatory = $true)]
        [string]$NewlineFormat
    )
    
    # 一旦すべての改行を統一
    $normalized = $Content -replace "`r`n", "`n" -replace "`r", "`n"
    
    switch ($NewlineFormat.ToUpper()) {
        "CRLF" { return $normalized -replace "`n", "`r`n" }
        "LF" { return $normalized }
        "CR" { return $normalized -replace "`n", "`r" }
        default { 
            Write-SystemLog "未サポートの改行コード: $NewlineFormat。CRLFを使用します。" -Level "Warning"
            return $normalized -replace "`n", "`r`n"
        }
    }
}

# 設定ベースCSVインポート関数
function Import-CsvWithFormat {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        $formatConfig = Get-CsvFormatConfig -TableName $TableName
        
        Write-SystemLog "CSVファイルを読み込み中: $CsvPath (テーブル: $TableName)" -Level "Info"
        Write-SystemLog "使用設定 - エンコーディング: $($formatConfig.encoding), 区切り文字: '$($formatConfig.delimiter)', ヘッダー有り: $($formatConfig.has_header)" -Level "Info"
        
        # PowerShell用エンコーディング名に変換
        $encoding = ConvertTo-PowerShellEncoding -EncodingName $formatConfig.encoding
        
        # Import-Csvパラメータ準備（ヘッダー付きCSVとして処理）
        $importParams = @{
            Path     = $CsvPath
            Encoding = $encoding
        }
        
        # 区切り文字設定（PowerShellのデフォルトはカンマ）
        if ($formatConfig.delimiter -ne ",") {
            $importParams.Delimiter = $formatConfig.delimiter
        }
        
        # CSVデータインポート
        $csvData = Import-Csv @importParams
        
        # null値の変換
        if ($formatConfig.null_values -and $formatConfig.null_values.Count -gt 0) {
            foreach ($row in $csvData) {
                foreach ($prop in $row.PSObject.Properties) {
                    if ($prop.Value -in $formatConfig.null_values) {
                        $prop.Value = $null
                    }
                }
            }
        }
        
        Write-SystemLog "CSVファイル読み込み完了: $($csvData.Count)行" -Level "Success"
        return $csvData
        
    }
    catch {
        Write-SystemLog "CSVファイルの読み込みに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# SQLite文字列結果をPSCustomObjectに変換
function ConvertFrom-SqliteStringResult {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$StringArray,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
        if ($StringArray.Count -eq 0) {
            return @()
        }
        
        # SQLite3のデフォルト出力は"|"区切り
        # 最初の行をヘッダーとして扱う
        $headers = $StringArray[0] -split '\|'
        $headers = $headers | ForEach-Object { $_.Trim() }
        
        if ($StringArray.Count -eq 1) {
            # ヘッダーのみでデータなし
            return @()
        }
        
        $dataRows = $StringArray[1..($StringArray.Count - 1)]
        
        $objects = foreach ($row in $dataRows) {
            if ([string]::IsNullOrWhiteSpace($row)) { 
                continue 
            }
            
            $values = $row -split '\|'
            $obj = [PSCustomObject]@{}
            
            for ($i = 0; $i -lt $headers.Count; $i++) {
                $value = if ($i -lt $values.Count) { $values[$i].Trim() } else { "" }
                # 空文字列をnullに変換
                if ([string]::IsNullOrEmpty($value)) {
                    $value = $null
                }
                $obj | Add-Member -NotePropertyName $headers[$i] -NotePropertyValue $value
            }
            $obj
        }
        
        Write-SystemLog "SQLite結果変換完了: $($objects.Count)件のPSCustomObjectに変換" -Level "Success"
        return $objects
        
    }
    catch {
        Write-SystemLog "SQLite結果の変換に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 設定ベースCSVエクスポート関数
# 統合されたCSVエクスポート関数（責務分割によるリファクタリング）
function Export-CsvWithFormat {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [switch]$SuppressDetailedLog,
        
        [switch]$SkipConversion
    )
    
    try {
        if (-not $SuppressDetailedLog) {
            Write-SystemLog "CSVファイルを出力中: $OutputPath (テーブル: $TableName)" -Level "Info"
        }
        
        # 1. データの前処理・変換
        $processedData = Convert-DataForExport -Data $Data -TableName $TableName -SkipConversion:$SkipConversion -SuppressDetailedLog:$SuppressDetailedLog
        
        # 2. CSVフォーマット設定の取得
        $formatConfig = Get-CsvFormatConfig -TableName $TableName
        
        if (-not $SuppressDetailedLog) {
            Write-SystemLog "使用設定 - エンコーディング: $($formatConfig.encoding), 区切り文字: '$($formatConfig.delimiter)', ヘッダー出力: $($formatConfig.include_header)" -Level "Info"
        }
        
        # 3. CSVファイル出力処理
        Write-CsvWithEncoding -Data $processedData -OutputPath $OutputPath -FormatConfig $formatConfig
        
        if (-not $SuppressDetailedLog) {
            Write-SystemLog "CSVファイル出力完了: $($processedData.Count)行" -Level "Success"
        }
        
    }
    catch {
        Write-SystemLog "CSVファイルの出力に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# データのエクスポート用前処理（責務の分離）
function Convert-DataForExport {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [switch]$SkipConversion,
        
        [switch]$SuppressDetailedLog
    )
    
    # データ型とサイズのチェック
    if ($null -eq $Data) {
        throw "データがnullです"
    }
    
    # データが配列でない場合は配列に変換
    if ($Data -isnot [array]) {
        $Data = @($Data)
    }
    
    if (-not $SuppressDetailedLog) {
        Write-SystemLog "データ型: $($Data.GetType().Name), 要素数: $($Data.Count)" -Level "Info"
        if ($Data.Count -gt 0) {
            Write-SystemLog "最初の要素の型: $($Data[0].GetType().Name)" -Level "Info"
        }
    }
    
    # 文字列データの検出と自動変換（SkipConversionが指定されていない場合のみ）
    if (-not $SkipConversion -and $Data.Count -gt 0 -and $Data[0] -is [string]) {
        if (-not $SuppressDetailedLog) {
            Write-SystemLog "SQLite結果の文字列データを検出しました。PSCustomObjectに自動変換します。" -Level "Info"
        }
        $Data = ConvertFrom-SqliteStringResult -StringArray $Data -TableName $TableName
        
        # 変換後のデータチェック
        if (-not $SuppressDetailedLog) {
            if ($Data.Count -gt 0) {
                Write-SystemLog "SQLite結果変換完了: $($Data.Count)件のPSCustomObjectに変換" -Level "Info"
                Write-SystemLog "変換後のデータ型: $($Data[0].GetType().Name), 要素数: $($Data.Count)" -Level "Info"
            }
            else {
                Write-SystemLog "変換後のデータが空です" -Level "Warning"
            }
        }
    }
    elseif ($SkipConversion -and -not $SuppressDetailedLog) {
        Write-SystemLog "変換をスキップします（既に変換済みデータを使用）" -Level "Info"
    }
    
    return $Data
}

# CSVファイル書き込み処理（エンコーディング・フォーマット対応）
function Write-CsvWithEncoding {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        
        [Parameter(Mandatory = $true)]
        $FormatConfig
    )
    
    # PowerShell用エンコーディング名に変換
    $encoding = ConvertTo-PowerShellEncoding -EncodingName $FormatConfig.encoding
    
    # 出力ディレクトリが存在しない場合は作成
    $outputDir = Split-Path -Parent $OutputPath
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    
    # Export-Csvパラメータ準備
    $exportParams = @{
        Path              = $OutputPath
        Encoding          = $encoding
        NoTypeInformation = $true
    }
    
    # 区切り文字設定
    if ($FormatConfig.delimiter -ne ",") {
        $exportParams.Delimiter = $FormatConfig.delimiter
    }
    
    # ヘッダー設定による出力分岐
    if ($FormatConfig.include_header -eq $false) {
        # ヘッダーなし出力の場合、一時的にヘッダー付きで出力してからヘッダー行を削除
        $tempPath = "$OutputPath.tmp"
        $Data | Export-Csv @exportParams -Path $tempPath
        
        $content = Get-Content $tempPath -Encoding $encoding | Select-Object -Skip 1
        $content | Out-File -FilePath $OutputPath -Encoding $encoding
        Remove-Item $tempPath -Force -ErrorAction SilentlyContinue
    }
    else {
        # 通常のヘッダー付き出力
        $Data | Export-Csv @exportParams
    }
    
    # 改行コード変換（必要な場合）
    if ($FormatConfig.newline -and $FormatConfig.newline.ToUpper() -ne "CRLF") {
        $content = Get-Content $OutputPath -Raw -Encoding $encoding
        $convertedContent = ConvertTo-NewlineFormat -Content $content -NewlineFormat $FormatConfig.newline
        $convertedContent | Out-File -FilePath $OutputPath -Encoding $encoding -NoNewline
    }
}

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
    
    Write-SystemLog "処理対象ファイル ${FileTypeDescription}CSV: $CsvPath" -Level "Info"
        
    # 履歴ディレクトリにコピー保存
    Invoke-WithErrorHandling -ScriptBlock {
        Copy-InputFileToHistory -SourceFilePath $CsvPath -HistoryDirectory $HistoryDirectory
    } -Category External -Operation "履歴ファイルコピー"
        
    # ヘッダー無しCSVの場合、ヘッダーを付与した一時ファイルを作成
    $processingCsvPath = $CsvPath
    $tempHeaderFile = $null

    $formatConfig = Get-CsvFormatConfig -TableName $TableName
    if ($formatConfig.has_header -eq $false) {
        $tempHeaderFile = Invoke-WithErrorHandling -ScriptBlock {
            Add-CsvHeader -CsvPath $CsvPath -TableName $TableName
        } -Category External -Operation "ヘッダ付きCSVファイル作成"
        $processingCsvPath = $tempHeaderFile
        Write-SystemLog "作成完了: $processingCsvPath" -Level "Info"
    }
        
    # 一時ファイルのクリーンアップ処理
    $cleanupScript = {
        if ($tempHeaderFile -and (Test-Path $tempHeaderFile)) {
            Remove-Item $tempHeaderFile -Force -ErrorAction SilentlyContinue
            Write-SystemLog "一時ヘッダーファイルを削除しました: $tempHeaderFile" -Level "Info"
        }
    }
        
    # CSVフォーマットの検証
    Write-SystemLog "CSVフォーマットの検証開始" -Level "Info"
    Invoke-WithErrorHandling -Category System -Operation "CSVフォーマットの検証" -CleanupScript $cleanupScript -ScriptBlock {
        if (-not (Test-CsvFormat -CsvPath $processingCsvPath -TableName $TableName)) {
            throw "CSVフォーマットの検証に失敗しました"
        }    
    }
            
    # データフィルタリング
    Write-SystemLog "データフィルタリング処理開始" -Level "Info"
    $statistics = Invoke-WithErrorHandling -Category System -Operation "データフィルタリング処理" -CleanupScript $cleanupScript -ScriptBlock {
        Invoke-Filtering -DatabasePath $DatabasePath -TableName $TableName -CsvFilePath $processingCsvPath -ShowStatistics:$true
    }

    Write-SystemLog "${FileTypeDescription}CSVのインポートが完了しました。処理件数: $($statistics.FilteredCount) / 読み込み件数: $($statistics.TotalCount)" -Level "Success"
    return $statistics
}

# 統合されたデータインポート関数（DRY原則に基づく統合）
function Import-DataCsvByType {
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
    
    Import-CsvToTable -CsvPath $CsvPath -DatabasePath $DatabasePath -TableName $config.TableName -HistoryDirectory $config.HistoryDirectory -FileTypeDescription $config.Description
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
        
        # 履歴ディレクトリの作成
        if (-not (Test-Path $filePathConfig.output_history_directory)) {
            New-Item -ItemType Directory -Path $filePathConfig.output_history_directory -Force | Out-Null
            Write-Host "履歴ディレクトリを作成しました: $filePathConfig.output_history_directory" -ForegroundColor Green
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
            $recordCount = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query -CsvOutput -CsvOutputPath $resolvedOutputPath
            Write-SystemLog "同期結果をCSVファイルに出力しました: $resolvedOutputPath ($recordCount件)" -Level "Success"
            $outputCount++
        }
        
        # 履歴保存（data/output配下）
        $recordCount = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query -CsvOutput -CsvOutputPath $historyPath
        Write-SystemLog "同期結果をCSVファイルに出力しました: $historyPath ($recordCount件)" -Level "Success"
        Write-SystemLog "履歴ファイルとして保存: $historyPath" -Level "Info"
        $outputCount++
        
        Write-SystemLog "同期結果出力完了: $outputCount ファイル" -Level "Success"
        
        # 結果の統計情報を表示
        Show-SyncStatistics -DatabasePath $DatabasePath
        
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

# ヘッダー無しCSVファイルにヘッダーを付与する関数
function Add-CsvHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
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
    catch {
        Write-SystemLog "ヘッダー付与処理に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
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
        # CSV設定を取得
        $formatConfig = Get-CsvFormatConfig -TableName $TableName
        Write-SystemLog "CSVファイルを検証中: $(Split-Path -Leaf $CsvPath) (テーブル: $TableName, ヘッダー有り: $($formatConfig.has_header))" -Level "Info"
        
        $csvData = Import-CsvWithFormat -CsvPath $CsvPath -TableName $TableName
        
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
        
        # カラム数チェック（ヘッダー付きファイルとして処理されるため、設定ベースでチェック）
        $expectedColumns = Get-CsvColumns -TableName $TableName
        if ($headers.Count -ne $expectedColumns.Count) {
            Write-SystemLog "カラム数が一致しません。期待値: $($expectedColumns.Count), 実際: $($headers.Count)" -Level "Warning"
            Write-SystemLog "期待されるカラム: $($expectedColumns -join ', ')" -Level "Info"
            Write-SystemLog "実際のカラム: $($headers -join ', ')" -Level "Info"
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