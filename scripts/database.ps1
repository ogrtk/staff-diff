# PowerShell & SQLite 職員データ管理システム
# データベース操作スクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "common-utils.ps1")

# SQLiteモジュールが必要な場合のチェック
function Test-SqliteModule {
    if (-not (Get-Module -ListAvailable -Name System.Data.SQLite)) {
        Write-Warning "System.Data.SQLite モジュールが見つかりません。"
        Write-Host "SQLiteへの接続にはSystem.Data.SQLiteが必要です。" -ForegroundColor Yellow
        Write-Host "代替として、sqlite3.exeを使用してデータベース操作を行います。" -ForegroundColor Yellow
    }
}

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
        if (-not (Test-SchemaConfig)) {
            throw "スキーマ設定の検証に失敗しました"
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
    
    $config = Get-SchemaConfig
    $allSqlStatements = @()
    
    # 各テーブルのCREATE TABLE文を生成
    foreach ($tableName in $config.tables.PSObject.Properties.Name) {
        Write-SystemLog "テーブル定義を生成中: $tableName" -Level "Info"
        
        $createTableSql = New-CreateTableSql -TableName $tableName
        $allSqlStatements += $createTableSql
        
        # インデックスの作成
        $indexSqls = New-CreateIndexSql -TableName $tableName
        $allSqlStatements += $indexSqls
        
        # 更新トリガーの作成
        $triggerSqls = New-UpdateTriggerSql -TableName $tableName
        $allSqlStatements += $triggerSqls
    }
    
    # SQLの実行
    $combinedSql = $allSqlStatements -join "`n`n"
    
    # sqlite3コマンドが利用可能かチェック
    $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
    if ($sqlite3Path) {
        $tempSqlFile = [System.IO.Path]::GetTempFileName() + ".sql"
        $combinedSql | Out-File -FilePath $tempSqlFile -Encoding UTF8
        
        Write-SystemLog "sqlite3コマンドでデータベースを初期化中..." -Level "Info"
        & sqlite3 $DatabasePath ".read $tempSqlFile"
        
        Remove-Item -Path $tempSqlFile -Force
    }
    else {
        Write-Warning "sqlite3コマンドが見つかりません。PowerShellでの直接操作を試行します。"
        Initialize-DatabaseWithPowerShell -DatabasePath $DatabasePath -SqlContent $combinedSql
    }
}

# PowerShellでのデータベース初期化（フォールバック）
function Initialize-DatabaseWithPowerShell {
    param(
        [string]$DatabasePath,
        [string]$SqlContent
    )
    
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
"@ -ReferencedAssemblies "System.Data", "System.Data.SQLite"
    
    $connectionString = "Data Source=$DatabasePath;Version=3;"
    [SQLiteHelper]::ExecuteNonQuery($connectionString, $SqlContent)
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
            $tempFile = [System.IO.Path]::GetTempFileName()
            $Query | Out-File -FilePath $tempFile -Encoding UTF8
            $result = & sqlite3 $DatabasePath ".read $tempFile"
            Remove-Item -Path $tempFile -Force
            return $result
        }
        else {
            # PowerShellの直接操作
            $connectionString = "Data Source=$DatabasePath;Version=3;"
            return [SQLiteHelper]::ExecuteQuery($connectionString, $Query)
        }
    }
    catch {
        Write-SystemLog "SQLiteコマンドの実行に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# テーブルのクリア
function Clear-Table {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    Write-SystemLog "テーブルをクリア中: $TableName" -Level "Info"
    $query = "DELETE FROM $TableName;"
    Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
}

# データベース情報の表示
function Show-DatabaseInfo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    try {
        Write-SystemLog "データベース情報を取得中..." -Level "Info"
        
        $config = Get-SchemaConfig
        
        Write-Host "`n=== データベース情報 ===" -ForegroundColor Yellow
        Write-Host "データベースファイル: $DatabasePath" -ForegroundColor White
        Write-Host "設定バージョン: $($config.version)" -ForegroundColor White
        
        foreach ($tableName in $config.tables.PSObject.Properties.Name) {
            $table = $config.tables.$tableName
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