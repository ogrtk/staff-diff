# PowerShell & SQLite 職員データ管理システム
# データベース操作スクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "utils/config-utils.ps1")
. (Join-Path $PSScriptRoot "utils/sql-utils.ps1")
. (Join-Path $PSScriptRoot "utils/common-utils.ps1")

# 動的データベース初期化
function Initialize-Database {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $dbDir = Split-Path -Path $DatabasePath -Parent
    if (-not (Test-Path $dbDir)) {
        New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
    }
    
    try {
        Write-SystemLog "データベース初期化を開始します..." -Level "Info"
        
        # 設定の検証
        if (-not (Test-DataSyncConfig)) {
            throw "データ同期設定の検証に失敗しました"
        }
        
        # 動的にSQLを生成してデータベースを初期化
        Initialize-DatabaseDynamic -DatabasePath $DatabasePath
        
        Write-SystemLog "データベースが正常に初期化されました: $DatabasePath" -Level "Success"
        
    }
    catch {
        Write-SystemLog "データベースの初期化に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 動的データベース初期化の実装（性能最適化対応）
function Initialize-DatabaseDynamic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $config = Get-DataSyncConfig
    $allSqlStatements = @()
    
    # SQLite最適化PRAGMAを追加
    $pragmas = New-OptimizationPragmas
    $allSqlStatements += $pragmas
    
    # 各テーブルのDROP+CREATE TABLE文を生成
    foreach ($tableName in $config.tables.PSObject.Properties.Name) {
        Write-SystemLog "テーブル定義を生成中: $tableName" -Level "Info"
        
        # クリーンな初期化のためDROP TABLE IF EXISTSを追加
        $dropTableSql = "DROP TABLE IF EXISTS $tableName;"
        $allSqlStatements += $dropTableSql
        
        $createTableSql = New-CreateTableSql -TableName $tableName
        $allSqlStatements += $createTableSql
        
        # インデックスの作成（動的最適化は後でレコード数判定後に実行）
        # ここでは初期インデックスのみ作成
    }
    
    # SQLの実行
    $combinedSql = $allSqlStatements -join "`n`n"
    
    # sqlite3コマンドが利用可能かチェック
    $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($sqlite3Path) {
        try {
            $tempSqlFile = [System.IO.Path]::GetTempFileName() + ".sql"
            $encoding = Get-CrossPlatformEncoding
            $combinedSql | Out-File -FilePath $tempSqlFile -Encoding $encoding
            
            Write-SystemLog "sqlite3コマンドでデータベースを初期化中..." -Level "Info"
            
            # sqlite3コマンドの実行と結果の確認
            $sqliteResult = & sqlite3 $DatabasePath ".read $tempSqlFile" 2>&1
            
            if ($LASTEXITCODE -ne 0) {
                throw "sqlite3コマンドの実行に失敗しました。終了コード: $LASTEXITCODE, 出力: $sqliteResult"
            }
            
            Write-SystemLog "sqlite3コマンドでの初期化が完了しました" -Level "Success"
            
        }
        catch {
            Write-SystemLog "sqlite3コマンドでの初期化に失敗しました: $($_.Exception.Message)" -Level "Warning"
            Write-SystemLog "PowerShellでの直接操作にフォールバックします" -Level "Info"
            Initialize-DatabaseWithPowerShell -DatabasePath $DatabasePath -SqlContent $combinedSql
        }
        finally {
            if (Test-Path $tempSqlFile) {
                Remove-Item -Path $tempSqlFile -Force
            }
        }
    }
    else {
        Write-SystemLog "sqlite3コマンドが見つかりません。PowerShellでの直接操作を試行します。" -Level "Info"
        Initialize-DatabaseWithPowerShell -DatabasePath $DatabasePath -SqlContent $combinedSql
    }
}

# PowerShellでのデータベース初期化（フォールバック）
function Initialize-DatabaseWithPowerShell {
    param(
        [string]$DatabasePath,
        [string]$SqlContent
    )
    
    try {
        # SQLiteアセンブリの動的ロード
        $sqliteAssemblyPath = $null
        $possiblePaths = @(
            "System.Data.SQLite",
            "System.Data.SQLite.dll"
        )
        
        foreach ($path in $possiblePaths) {
            try {
                Add-Type -AssemblyName $path -ErrorAction Stop
                $sqliteAssemblyPath = $path
                break
            }
            catch {
                # 次のパスを試行
                continue
            }
        }
        
        if (-not $sqliteAssemblyPath) {
            throw "System.Data.SQLiteアセンブリが見つかりません。sqlite3コマンドを使用してください。"
        }
        
        # 簡単なSQLite接続クラス
        Add-Type -TypeDefinition @"
        using System;
        using System.Data;
        using System.Data.SQLite;
        
        public class SQLiteHelper {
            public static void ExecuteNonQuery(string connectionString, string sql) {
                using (var connection = new SQLiteConnection(connectionString)) {
                    connection.Open();
                    using (var command = new SQLiteCommand(sql, connection)) {
                        command.ExecuteNonQuery();
                    }
                }
            }
            
            public static DataTable ExecuteQuery(string connectionString, string sql) {
                using (var connection = new SQLiteConnection(connectionString)) {
                    connection.Open();
                    using (var command = new SQLiteCommand(sql, connection)) {
                        using (var adapter = new SQLiteDataAdapter(command)) {
                            var dataTable = new DataTable();
                            adapter.Fill(dataTable);
                            return dataTable;
                        }
                    }
                }
            }
        }
"@ -ReferencedAssemblies "System.Data", $sqliteAssemblyPath
        
        $connectionString = "Data Source=$DatabasePath;Version=3;"
        [SQLiteHelper]::ExecuteNonQuery($connectionString, $SqlContent)
        
    }
    catch {
        Write-SystemLog "PowerShellでのSQLite操作に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw "SQLiteの初期化に失敗しました。sqlite3コマンドが必要です。"
    }
}

# SQLiteコマンド実行（汎用）
function Invoke-SqliteCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [hashtable]$Parameters = @{},
        
        [string]$CsvOutputPath = "",
        
        [switch]$CsvOutput
    )
    
    try {
        $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if ($sqlite3Path) {
            # CSV出力モードの処理
            if ($CsvOutput -and -not [string]::IsNullOrEmpty($CsvOutputPath)) {
                try {
                    # SQLite3で直接CSV出力（ヘッダー付き）
                    $csvArgs = @($DatabasePath, "-csv", "-header", $Query)
                    $result = & sqlite3 @csvArgs 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "sqlite3 CSV出力エラー (終了コード: $LASTEXITCODE): $result"
                    }
                    
                    # 結果を指定されたファイルに書き込み
                    $encoding = Get-CrossPlatformEncoding
                    $result | Out-File -FilePath $CsvOutputPath -Encoding $encoding
                    
                    Write-SystemLog "SQLite直接CSV出力完了: $CsvOutputPath ($(if ($result -is [array]) { $result.Count - 1 } else { 0 })件)" -Level "Success"
                    return $result.Count - 1  # ヘッダー行を除いた件数を返す
                }
                catch {
                    Write-SystemLog "SQLite直接CSV出力に失敗しました: $($_.Exception.Message)" -Level "Warning"
                    # フォールバックとして通常処理を続行
                }
            }
            
            # 通常のSQLite3コマンド実行
            try {
                $tempFile = [System.IO.Path]::GetTempFileName()
                $encoding = Get-CrossPlatformEncoding
                $Query | Out-File -FilePath $tempFile -Encoding $encoding
                
                $result = & sqlite3 $DatabasePath ".read $tempFile" 2>&1
                
                if ($LASTEXITCODE -ne 0) {
                    throw "sqlite3コマンドエラー (終了コード: $LASTEXITCODE): $result"
                }
                
                return $result
            }
            catch {
                Write-SystemLog "sqlite3コマンドの実行に失敗しました: $($_.Exception.Message)" -Level "Warning"
                throw "sqlite3コマンドの実行に失敗しました: $($_.Exception.Message)"
            }
            finally {
                if (Test-Path $tempFile) {
                    Remove-Item -Path $tempFile -Force
                }
            }
        }
        else {
            # PowerShellの直接操作
            Write-SystemLog "sqlite3コマンドが利用できません。PowerShellで直接実行します" -Level "Info"
            $connectionString = "Data Source=$DatabasePath;Version=3;"
            return [SQLiteHelper]::ExecuteQuery($connectionString, $Query)
        }
    }
    catch {
        Write-SystemLog "SQLiteコマンドの実行に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# Clear-Table関数を削除（データベース初期化時にDROP/CREATEを実行するため不要）

# データベース情報の表示
function Show-DatabaseInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "データベース情報を取得中..." -Level "Info"
        
        $config = Get-DataSyncConfig
        
        Write-Host "`n=== データベース情報 ===" -ForegroundColor Yellow
        Write-Host "データベースファイル: $DatabasePath" -ForegroundColor White
        Write-Host "設定バージョン: $($config.version)" -ForegroundColor White
        
        foreach ($tableName in $config.tables.PSObject.Properties.Name) {
            $countQuery = "SELECT COUNT(*) as count FROM $tableName;"
            
            try {
                $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $countQuery
                $count = if ($result -is [array] -and $result.Count -gt 0) { $result[0] } else { $result }
                
                Write-Host "テーブル $tableName : $($count)件" -ForegroundColor White
            }
            catch {
                Write-Host "テーブル $tableName : 取得エラー" -ForegroundColor Red
            }
        }
        
        Write-Host "========================" -ForegroundColor Yellow
        
    }
    catch {
        Write-SystemLog "データベース情報の取得に失敗しました: $($_.Exception.Message)" -Level "Error"
    }
}

# SQLベースフィルタリングによるCSVインポート（高速版）
function Import-CsvToSqliteWithSqlFilter {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName,
        
        [bool]$ShowStatistics = $true
    )
    
    try {
        Write-SystemLog "SQLベースフィルタリングでCSVをインポート中: $TableName ($CsvFilePath)" -Level "Info"
        
        # CSVファイルの件数を事前に取得
        $csvData = Import-Csv -Path $CsvFilePath
        $totalRecords = $csvData.Count
        
        Write-Host "CSVファイル読み込み完了: $totalRecords 件" -ForegroundColor Green
        
        # 一時テーブル名
        $tempTableName = "${TableName}_temp"
        
        # すべての処理を1つのトランザクションで実行（TEMPテーブルの一貫性のため）
        $allSqlStatements = @()
        
        # 1. 一時テーブル作成
        $createTempTableSql = New-CreateTempTableSql -BaseTableName $TableName -TempTableName $tempTableName
        Write-SystemLog "一時テーブル作成: $tempTableName" -Level "Info"
        # 一時テーブルを事前に作成
        $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $createTempTableSql
        
        # 2. CSVデータを一時テーブルに直接インポート（SQLite .import使用）
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
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $indexSql
        }
        
        # 統計表示
        if ($ShowStatistics) {
            $excludedCount = $totalRecords - $filteredCount
            $exclusionRate = if ($totalRecords -gt 0) { [Math]::Round(($excludedCount / $totalRecords) * 100, 2) } else { 0 }
            
            Write-Host "`n=== SQLフィルタリング統計: $TableName ===" -ForegroundColor Green
            Write-Host "総件数: $totalRecords" -ForegroundColor White
            Write-Host "通過件数: $filteredCount" -ForegroundColor Green
            Write-Host "除外件数: $excludedCount" -ForegroundColor Red
            Write-Host "除外率: $exclusionRate%" -ForegroundColor Yellow
            Write-Host "処理方式: SQLベースフィルタリング（高速）" -ForegroundColor Cyan
            
            if ($whereClause) {
                Write-Host "適用フィルタ: $whereClause" -ForegroundColor Gray
            }
            else {
                Write-Host "適用フィルタ: なし（全件通過）" -ForegroundColor Gray
            }
        }
        
        Write-SystemLog "SQLベースフィルタリング完了: $filteredCount 件を $TableName に挿入" -Level "Success"
        
        return @{
            TotalCount    = $totalRecords
            FilteredCount = $filteredCount
            ExcludedCount = $excludedCount
            ExclusionRate = $exclusionRate
        }
        
    }
    catch {
        Write-SystemLog "SQLベースフィルタリングに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# CSVデータをテーブルに挿入（高速バッチ処理）
function Import-CsvDataToTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [array]$CsvData,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    if ($CsvData.Count -eq 0) {
        Write-SystemLog "挿入するCSVデータがありません" -Level "Warning"
        return
    }
    
    try {
        # バッチ挿入用のSQL文を生成
        $csvColumns = Get-CsvColumns -TableName $TableName
        $columnsStr = $csvColumns -join ", "
        
        $insertStatements = @()
        $batchSize = 1000  # バッチサイズ
        
        for ($i = 0; $i -lt $CsvData.Count; $i += $batchSize) {
            $batch = $CsvData[$i..([Math]::Min($i + $batchSize - 1, $CsvData.Count - 1))]
            
            $valuesList = @()
            foreach ($row in $batch) {
                $values = @()
                foreach ($column in $csvColumns) {
                    $value = if ($row.$column) { $row.$column } else { "" }
                    $values += Protect-SqlValue -Value $value
                }
                $valuesList += "(" + ($values -join ", ") + ")"
            }
            
            if ($valuesList.Count -gt 0) {
                $insertSql = "INSERT INTO $TableName ($columnsStr) VALUES " + ($valuesList -join ", ") + ";"
                $insertStatements += $insertSql
            }
        }
        
        # トランザクションで高速実行
        $transactionSql = "BEGIN TRANSACTION;`n" + ($insertStatements -join "`n") + "`nCOMMIT;"
        Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $transactionSql
        
        Write-SystemLog "$($CsvData.Count) 件のデータを $TableName に挿入完了" -Level "Info"
        
    }
    catch {
        Write-SystemLog "CSVデータの挿入に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# CSVデータからINSERT文を生成
# CSV直接インポート関数（SQLite .importコマンド使用）
function Import-CsvToSqliteTable {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CsvFilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    try {
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
        
    }
    catch {
        Write-SystemLog "CSV直接インポートに失敗しました: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}

function Get-CsvInsertStatements {
    param(
        [Parameter(Mandatory = $true)]
        [array]$CsvData,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    if ($CsvData.Count -eq 0) {
        return @()
    }
    
    try {
        # バッチ挿入用のSQL文を生成
        $csvColumns = Get-CsvColumns -TableName $TableName
        $columnsStr = $csvColumns -join ", "
        
        $insertStatements = @()
        $batchSize = 1000  # バッチサイズ
        
        for ($i = 0; $i -lt $CsvData.Count; $i += $batchSize) {
            $batch = $CsvData[$i..([Math]::Min($i + $batchSize - 1, $CsvData.Count - 1))]
            
            $valuesList = @()
            foreach ($row in $batch) {
                $values = @()
                foreach ($column in $csvColumns) {
                    $value = if ($row.$column) { $row.$column } else { "" }
                    $values += Protect-SqlValue -Value $value
                }
                $valuesList += "(" + ($values -join ", ") + ")"
            }
            
            if ($valuesList.Count -gt 0) {
                $insertSql = "INSERT INTO $TableName ($columnsStr) VALUES " + ($valuesList -join ", ") + ";"
                $insertStatements += $insertSql
            }
        }
        
        return $insertStatements
        
    }
    catch {
        Write-SystemLog "CSVデータからのINSERT文生成に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}