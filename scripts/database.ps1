# PowerShell & SQLite 職員データ管理システム
# データベース操作スクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "config-utils.ps1")
. (Join-Path $PSScriptRoot "sql-utils.ps1")
. (Join-Path $PSScriptRoot "common-utils.ps1")

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

# 動的データベース初期化の実装
function Initialize-DatabaseDynamic {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    $config = Get-DataSyncConfig
    $allSqlStatements = @()
    
    # 各テーブルのDROP+CREATE TABLE文を生成
    foreach ($tableName in $config.tables.PSObject.Properties.Name) {
        Write-SystemLog "テーブル定義を生成中: $tableName" -Level "Info"
        
        # クリーンな初期化のためDROP TABLE IF EXISTSを追加
        $dropTableSql = "DROP TABLE IF EXISTS $tableName;"
        $allSqlStatements += $dropTableSql
        
        $createTableSql = New-CreateTableSql -TableName $tableName
        $allSqlStatements += $createTableSql
        
        # インデックスの作成
        $indexSqls = New-CreateIndexSql -TableName $tableName
        $allSqlStatements += $indexSqls
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
        
        [hashtable]$Parameters = @{}
    )
    
    try {
        $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if ($sqlite3Path) {
            # sqlite3コマンドラインツールを使用
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