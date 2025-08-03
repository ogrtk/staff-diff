# PowerShell & SQLite 職員データ管理システム
# 共通ユーティリティライブラリ

# グローバル変数
$Global:SchemaConfig = $null

# スキーマ設定の読み込み
function Get-SchemaConfig {
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot "..\config\schema-config.json")
    )
    
    if ($null -eq $Global:SchemaConfig) {
        try {
            if (-not (Test-Path $ConfigPath)) {
                throw "設定ファイルが見つかりません: $ConfigPath"
            }
            
            $configContent = Get-Content -Path $ConfigPath -Raw -Encoding UTF8
            $Global:SchemaConfig = $configContent | ConvertFrom-Json
            
            Write-Host "スキーマ設定を読み込みました: $ConfigPath" -ForegroundColor Green
            
        }
        catch {
            Write-Error "スキーマ設定の読み込みに失敗しました: $($_.Exception.Message)"
            throw
        }
    }
    
    return $Global:SchemaConfig
}

# テーブル定義の取得
function Get-TableDefinition {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $config = Get-SchemaConfig
    
    if (-not $config.tables.$TableName) {
        throw "テーブル定義が見つかりません: $TableName"
    }
    
    return $config.tables.$TableName
}

# CSVカラムリストの取得
function Get-CsvColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    $csvColumns = $tableDefinition.columns | Where-Object { $_.csv_include -eq $true } | ForEach-Object { $_.name }
    
    return $csvColumns
}

# 必須カラムリストの取得
function Get-RequiredColumns {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    $requiredColumns = $tableDefinition.columns | Where-Object { $_.required -eq $true } | ForEach-Object { $_.name }
    
    return $requiredColumns
}

# CREATE TABLE文の動的生成
function New-CreateTableSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    
    $sql = "CREATE TABLE IF NOT EXISTS $TableName (`n"
    
    $columnDefinitions = @()
    foreach ($column in $tableDefinition.columns) {
        $columnDef = "    $($column.name) $($column.type)"
        if ($column.constraints) {
            $columnDef += " $($column.constraints)"
        }
        $columnDefinitions += $columnDef
    }
    
    $sql += $columnDefinitions -join ",`n"
    $sql += "`n);"
    
    return $sql
}

# INSERT文の動的生成
function New-InsertSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$Data
    )
    
    $csvColumns = Get-CsvColumns -TableName $TableName
    
    # データに存在するカラムのみを使用
    $availableColumns = @()
    $values = @()
    
    foreach ($column in $csvColumns) {
        if ($Data.ContainsKey($column)) {
            $availableColumns += $column
            $values += "'$($Data[$column])'"
        }
    }
    
    if ($availableColumns.Count -eq 0) {
        throw "挿入可能なデータが見つかりません"
    }
    
    $columnsString = $availableColumns -join ", "
    $valuesString = $values -join ", "
    
    $sql = "INSERT INTO $TableName ($columnsString) VALUES ($valuesString);"
    
    return $sql
}

# SELECT文の動的生成
function New-SelectSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [string[]]$Columns = @(),
        [string]$WhereClause = "",
        [string]$OrderBy = ""
    )
    
    if ($Columns.Count -eq 0) {
        $Columns = Get-CsvColumns -TableName $TableName
    }
    
    $columnsString = $Columns -join ", "
    $sql = "SELECT $columnsString FROM $TableName"
    
    if ($WhereClause) {
        $sql += " WHERE $WhereClause"
    }
    
    if ($OrderBy) {
        $sql += " ORDER BY $OrderBy"
    }
    
    $sql += ";"
    
    return $sql
}

# 比較用WHERE句の生成
function New-ComparisonWhereClause {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Table1Alias,
        
        [Parameter(Mandatory = $true)]
        [string]$Table2Alias,
        
        [string]$ComparisonType = "different" # "different" or "same"
    )
    
    $config = Get-SchemaConfig
    $comparisonColumns = $config.sync_rules.comparison_columns
    
    $conditions = @()
    foreach ($column in $comparisonColumns) {
        $condition = "$Table1Alias.$column"
        
        if ($ComparisonType -eq "different") {
            $condition += " != $Table2Alias.$column"
        }
        else {
            $condition += " = $Table2Alias.$column"
        }
        
        $conditions += $condition
    }
    
    $operator = if ($ComparisonType -eq "different") { " OR " } else { " AND " }
    return $conditions -join $operator
}

# CSVヘッダーの生成
function New-CsvHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $csvColumns = Get-CsvColumns -TableName $TableName
    return $csvColumns -join ","
}

# インデックス作成SQL文の生成
function New-CreateIndexSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    $sqlStatements = @()
    
    foreach ($index in $tableDefinition.indexes) {
        $columnsString = $index.columns -join ", "
        $sql = "CREATE INDEX IF NOT EXISTS $($index.name) ON $TableName($columnsString);"
        $sqlStatements += $sql
    }
    
    return $sqlStatements
}

# トリガー作成SQL文の生成（更新日時の自動更新）
function New-UpdateTriggerSql {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $tableDefinition = Get-TableDefinition -TableName $TableName
    
    # updated_atカラムが存在するかチェック
    $hasUpdatedAt = $tableDefinition.columns | Where-Object { $_.name -eq "updated_at" }
    
    if (-not $hasUpdatedAt) {
        return @()
    }
    
    $triggerName = "update_${TableName}_timestamp"
    
    $sql = @"
CREATE TRIGGER IF NOT EXISTS $triggerName 
    AFTER UPDATE ON $TableName
BEGIN
    UPDATE $TableName SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;
"@
    
    return @($sql)
}

# 設定の検証
function Test-SchemaConfig {
    try {
        $config = Get-SchemaConfig
        
        Write-Host "設定検証を実行中..." -ForegroundColor Cyan
        
        # 基本構造の検証
        if (-not $config.tables) {
            throw "テーブル定義が見つかりません"
        }
        
        # 各テーブルの検証
        foreach ($tableName in $config.tables.PSObject.Properties.Name) {
            $table = $config.tables.$tableName
            
            if (-not $table.columns -or $table.columns.Count -eq 0) {
                throw "テーブル '$tableName' のカラム定義が不正です"
            }
            
            # 必須カラムの存在確認
            $idColumn = $table.columns | Where-Object { $_.name -eq "id" }
            if (-not $idColumn) {
                Write-Warning "テーブル '$tableName' にidカラムがありません"
            }
        }
        
        # 同期ルールの検証
        if ($config.sync_rules -and $config.sync_rules.comparison_columns) {
            $staffInfoColumns = Get-CsvColumns -TableName "staff_info"
            foreach ($column in $config.sync_rules.comparison_columns) {
                if ($column -notin $staffInfoColumns) {
                    Write-Warning "比較カラム '$column' がstaff_infoテーブルに存在しません"
                }
            }
        }
        
        Write-Host "設定検証が完了しました: 問題なし" -ForegroundColor Green
        return $true
        
    }
    catch {
        Write-Error "設定検証に失敗しました: $($_.Exception.Message)"
        return $false
    }
}

# 日本時間でタイムスタンプを取得
function Get-JapanTimestamp {
    param(
        [string]$Format = "yyyyMMdd_HHmmss"
    )
    
    $config = Get-SchemaConfig
    $timezone = if ($config.file_paths.timezone) { $config.file_paths.timezone } else { "Asia/Tokyo" }
    
    try {
        # .NET TimeZoneInfo を使用して日本時間を取得
        $japanTimeZone = [System.TimeZoneInfo]::FindSystemTimeZoneById($timezone)
        $japanTime = [System.TimeZoneInfo]::ConvertTimeFromUtc([DateTime]::UtcNow, $japanTimeZone)
        return $japanTime.ToString($Format)
    }
    catch {
        # タイムゾーン取得に失敗した場合はUTC+9時間で計算
        $japanTime = [DateTime]::UtcNow.AddHours(9)
        return $japanTime.ToString($Format)
    }
}

# ファイルパス設定の取得
function Get-FilePathConfig {
    $config = Get-SchemaConfig
    
    if (-not $config.file_paths) {
        throw "ファイルパス設定が見つかりません"
    }
    
    return $config.file_paths
}

# 履歴用ファイル名の生成
function New-HistoryFileName {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BaseFileName,
        
        [string]$Extension = ".csv"
    )
    
    $timestamp = Get-JapanTimestamp
    $nameWithoutExt = [System.IO.Path]::GetFileNameWithoutExtension($BaseFileName)
    return "${nameWithoutExt}_${timestamp}${Extension}"
}

# 入力ファイルを履歴ディレクトリにコピー保存
function Copy-InputFileToHistory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$HistoryDirectory,
        
        [Parameter(Mandatory = $true)]
        [string]$FileType
    )
    
    try {
        if (-not (Test-Path $SourceFilePath)) {
            throw "ソースファイルが見つかりません: $SourceFilePath"
        }
        
        # 履歴ディレクトリが存在しない場合は作成
        if (-not (Test-Path $HistoryDirectory)) {
            New-Item -ItemType Directory -Path $HistoryDirectory -Force | Out-Null
            Write-SystemLog "履歴ディレクトリを作成しました: $HistoryDirectory" -Level "Info"
        }
        
        # 履歴用ファイル名を生成
        $sourceFileName = Split-Path -Leaf $SourceFilePath
        $historyFileName = New-HistoryFileName -BaseFileName $sourceFileName
        $historyFilePath = Join-Path $HistoryDirectory $historyFileName
        
        # ファイルをコピー
        Copy-Item -Path $SourceFilePath -Destination $historyFilePath -Force
        
        Write-SystemLog "${FileType} ファイルを履歴として保存しました: $historyFilePath" -Level "Success"
        
        return $historyFilePath
        
    }
    catch {
        Write-SystemLog "${FileType} ファイルの履歴保存に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 入力ファイルパスの解決（設定ファイル or パラメータ）
function Resolve-InputFilePath {
    param(
        [string]$ParameterPath,
        [string]$ConfigPath,
        [string]$FileType
    )
    
    $resolvedPath = ""
    
    # パラメータが指定されている場合はそれを優先
    if (-not [string]::IsNullOrEmpty($ParameterPath)) {
        $resolvedPath = $ParameterPath
        Write-SystemLog "${FileType}: パラメータで指定されたパス: $resolvedPath" -Level "Info"
    }
    # 設定ファイルにパスが設定されている場合
    elseif (-not [string]::IsNullOrEmpty($ConfigPath)) {
        $resolvedPath = $ConfigPath
        Write-SystemLog "${FileType}: 設定ファイルで指定されたパス: $resolvedPath" -Level "Info"
    }
    # どちらも指定されていない場合
    else {
        throw "${FileType} のファイルパスが指定されていません（パラメータまたは設定ファイルで指定してください）"
    }
    
    # ファイルの存在確認
    if (-not (Test-Path $resolvedPath)) {
        throw "${FileType} ファイルが見つかりません: $resolvedPath"
    }
    
    return $resolvedPath
}

# ログ設定の取得
function Get-LoggingConfig {
    $config = Get-SchemaConfig
    
    if (-not $config.logging) {
        # デフォルト設定を返す
        return @{
            enabled          = $false
            log_directory    = "./logs/"
            log_file_name    = "staff-management.log"
            max_file_size_mb = 10
            max_files        = 5
            levels           = @("Info", "Warning", "Error", "Success")
        }
    }
    
    return $config.logging
}

# ログファイルの初期化
function Initialize-LogFile {
    try {
        $logConfig = Get-LoggingConfig
        
        if (-not $logConfig.enabled) {
            return
        }
        
        # ログディレクトリが存在しない場合は作成
        if (-not (Test-Path $logConfig.log_directory)) {
            New-Item -ItemType Directory -Path $logConfig.log_directory -Force | Out-Null
        }
        
        $logFilePath = Join-Path $logConfig.log_directory $logConfig.log_file_name
        
        # ログファイルサイズチェックとローテーション
        if (Test-Path $logFilePath) {
            $logFile = Get-Item $logFilePath
            $fileSizeMB = [math]::Round($logFile.Length / 1MB, 2)
            
            if ($fileSizeMB -gt $logConfig.max_file_size_mb) {
                Rotate-LogFile -LogFilePath $logFilePath -MaxFiles $logConfig.max_files
            }
        }
        
        return $logFilePath
        
    }
    catch {
        # ログファイル初期化に失敗してもシステムは続行
        Write-Warning "ログファイルの初期化に失敗しました: $($_.Exception.Message)"
        return $null
    }
}

# ログファイルローテーション
function Rotate-LogFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LogFilePath,
        
        [int]$MaxFiles = 5
    )
    
    try {
        $directory = Split-Path -Parent $LogFilePath
        $fileName = [System.IO.Path]::GetFileNameWithoutExtension($LogFilePath)
        $extension = [System.IO.Path]::GetExtension($LogFilePath)
        
        # 既存のローテーションファイルを移動
        for ($i = $MaxFiles - 1; $i -gt 0; $i--) {
            $currentFile = Join-Path $directory "${fileName}.${i}${extension}"
            $nextFile = Join-Path $directory "${fileName}.$($i + 1)${extension}"
            
            if (Test-Path $currentFile) {
                if ($i -eq ($MaxFiles - 1)) {
                    # 最古のファイルは削除
                    Remove-Item $currentFile -Force
                }
                else {
                    # ファイルを次の番号に移動
                    Move-Item $currentFile $nextFile -Force
                }
            }
        }
        
        # 現在のログファイルを .1 に移動
        if (Test-Path $LogFilePath) {
            $rotatedFile = Join-Path $directory "${fileName}.1${extension}"
            Move-Item $LogFilePath $rotatedFile -Force
        }
        
    }
    catch {
        Write-Warning "ログファイルローテーションに失敗しました: $($_.Exception.Message)"
    }
}

# ログファイルへの書き込み
function Write-LogToFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [Parameter(Mandatory = $true)]
        [string]$Level,
        
        [Parameter(Mandatory = $true)]
        [string]$Timestamp
    )
    
    try {
        $logConfig = Get-LoggingConfig
        
        if (-not $logConfig.enabled -or $Level -notin $logConfig.levels) {
            return
        }
        
        $logFilePath = Initialize-LogFile
        
        if ($logFilePath) {
            $logLine = "[$Timestamp] [$Level] $Message"
            Add-Content -Path $logFilePath -Value $logLine -Encoding UTF8
        }
        
    }
    catch {
        # ログファイル書き込み失敗は無視（システム処理を停止させない）
    }
}

# ログ出力ヘルパー（ファイル出力対応版）
function Write-SystemLog {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,
        
        [ValidateSet("Info", "Warning", "Error", "Success")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-JapanTimestamp -Format "yyyy-MM-dd HH:mm:ss"
    $prefix = "[$timestamp]"
    
    # コンソール出力
    switch ($Level) {
        "Info" { Write-Host "$prefix $Message" -ForegroundColor White }
        "Warning" { Write-Host "$prefix WARNING: $Message" -ForegroundColor Yellow }
        "Error" { Write-Host "$prefix ERROR: $Message" -ForegroundColor Red }
        "Success" { Write-Host "$prefix $Message" -ForegroundColor Green }
    }
    
    # ファイル出力
    $logMessage = switch ($Level) {
        "Warning" { "WARNING: $Message" }
        "Error" { "ERROR: $Message" }
        default { $Message }
    }
    
    Write-LogToFile -Message $logMessage -Level $Level -Timestamp $timestamp
}

# 設定リロード
function Reset-SchemaConfig {
    $Global:SchemaConfig = $null
    Write-SystemLog "スキーマ設定をリセットしました" -Level "Info"
}

# データフィルタリング設定の取得
function Get-DataFilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $config = Get-SchemaConfig
    
    if (-not $config.data_filters -or -not $config.data_filters.$TableName) {
        return $null
    }
    
    return $config.data_filters.$TableName
}

# データフィルタリングの実行
function Test-DataFilter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [hashtable]$DataRow
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    # フィルタリングが無効または設定されていない場合は通す
    if (-not $filterConfig -or -not $filterConfig.enabled) {
        return $true
    }
    
    # 各フィルタルールをチェック
    foreach ($rule in $filterConfig.rules) {
        $fieldValue = $DataRow[$rule.field]
        
        if (-not $fieldValue) {
            continue
        }
        
        switch ($rule.type) {
            "exclude_pattern" {
                if ($fieldValue -match $rule.pattern) {
                    Write-SystemLog "データを除外: $($rule.field)='$fieldValue' (理由: $($rule.description))" -Level "Info"
                    return $false
                }
            }
            "include_pattern" {
                if ($fieldValue -notmatch $rule.pattern) {
                    Write-SystemLog "データを除外: $($rule.field)='$fieldValue' (理由: $($rule.description))" -Level "Info"
                    return $false
                }
            }
            "exclude_value" {
                if ($fieldValue -eq $rule.value) {
                    Write-SystemLog "データを除外: $($rule.field)='$fieldValue' (理由: $($rule.description))" -Level "Info"
                    return $false
                }
            }
            "include_value" {
                if ($fieldValue -ne $rule.value) {
                    Write-SystemLog "データを除外: $($rule.field)='$fieldValue' (理由: $($rule.description))" -Level "Info"
                    return $false
                }
            }
        }
    }
    
    return $true
}

# フィルタリング統計情報
function Get-FilterStatistics {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [array]$OriginalData,
        
        [Parameter(Mandatory = $true)]
        [array]$FilteredData
    )
    
    $originalCount = $OriginalData.Count
    $filteredCount = $FilteredData.Count
    $excludedCount = $originalCount - $filteredCount
    
    $stats = @{
        OriginalCount = $originalCount
        FilteredCount = $filteredCount
        ExcludedCount = $excludedCount
        ExclusionRate = if ($originalCount -gt 0) { [math]::Round(($excludedCount / $originalCount) * 100, 2) } else { 0 }
    }
    
    return $stats
}

# フィルタリング設定の表示
function Show-FilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    if (-not $filterConfig) {
        Write-SystemLog "テーブル '$TableName' にフィルタリング設定がありません" -Level "Info"
        return
    }
    
    Write-Host "`n=== $TableName フィルタリング設定 ===" -ForegroundColor Yellow
    Write-Host "有効: $($filterConfig.enabled)" -ForegroundColor White
    Write-Host "説明: $($filterConfig.description)" -ForegroundColor White
    
    if ($filterConfig.rules -and $filterConfig.rules.Count -gt 0) {
        Write-Host "ルール:" -ForegroundColor White
        foreach ($rule in $filterConfig.rules) {
            Write-Host "  - $($rule.type): $($rule.field) '$($rule.pattern)$($rule.value)' ($($rule.description))" -ForegroundColor Gray
        }
    }
    Write-Host "================================" -ForegroundColor Yellow
}

# バッチフィルタリング処理
function Invoke-DataFiltering {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [Parameter(Mandatory = $true)]
        [array]$Data
    )
    
    $filterConfig = Get-DataFilterConfig -TableName $TableName
    
    # フィルタリングが無効または設定されていない場合はそのまま返す
    if (-not $filterConfig -or -not $filterConfig.enabled) {
        Write-SystemLog "テーブル '$TableName' のフィルタリングは無効です" -Level "Info"
        return $Data
    }
    
    Write-SystemLog "テーブル '$TableName' のデータフィルタリングを開始します" -Level "Info"
    Show-FilterConfig -TableName $TableName
    
    $filteredData = @()
    $excludedCount = 0
    
    foreach ($row in $Data) {
        # HashTableに変換
        $dataRow = @{}
        foreach ($property in $row.PSObject.Properties) {
            $dataRow[$property.Name] = $property.Value
        }
        
        # フィルタリングテスト
        if (Test-DataFilter -TableName $TableName -DataRow $dataRow) {
            $filteredData += $row
        }
        else {
            $excludedCount++
        }
    }
    
    # 統計情報の表示
    $stats = Get-FilterStatistics -TableName $TableName -OriginalData $Data -FilteredData $filteredData
    Write-SystemLog "フィルタリング完了: 元データ $($stats.OriginalCount)件 → 処理対象 $($stats.FilteredCount)件 (除外 $($stats.ExcludedCount)件, $($stats.ExclusionRate)%)" -Level "Success"
    
    return $filteredData
}

# 注意: このファイルは通常のPowerShellスクリプトとして読み込まれるため、
# Export-ModuleMemberは使用しません。すべての関数は自動的に利用可能になります。