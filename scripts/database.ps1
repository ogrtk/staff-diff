# PowerShell & SQLite 職員データ管理システム
# データベース操作スクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "utils/config-utils.ps1")
. (Join-Path $PSScriptRoot "utils/sql-utils.ps1")
. (Join-Path $PSScriptRoot "utils/common-utils.ps1")
. (Join-Path $PSScriptRoot "utils/error-handling-utils.ps1")

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
    
    Write-SystemLog "データベース初期化を開始します..." -Level "Info"
    
    # 1. SQL文の生成
    $sqlStatements = New-DatabaseSchema
    
    # 2. SQL文の実行
    Invoke-DatabaseInitialization -DatabasePath $DatabasePath -SqlStatements $sqlStatements
    
    Write-SystemLog "データベースが正常に初期化されました: $DatabasePath" -Level "Success"
}

# データベーススキーマのSQL文を生成（責務の分離）
function script:New-DatabaseSchema {
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
    }
    
    return $allSqlStatements
}

# データベース初期化の実行（sqlite3コマンド必須）
function script:Invoke-DatabaseInitialization {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [array]$SqlStatements
    )
    
    $combinedSql = $SqlStatements -join "`n`n"
    
    # sqlite3コマンドが利用可能かチェック
    $sqlite3Path = Get-Sqlite3Path
    
    Invoke-SqliteSchemaCommand -DatabasePath $DatabasePath -SqlContent $combinedSql
}

# SQLite3コマンドでのSQL実行（スキーマ初期化専用）
function script:Invoke-SqliteSchemaCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$SqlContent
    )
    
    $tempSqlFile = [System.IO.Path]::GetTempFileName() + ".sql"
    try {
        $encoding = Get-CrossPlatformEncoding
        $SqlContent | Out-File -FilePath $tempSqlFile -Encoding $encoding
        
        Write-SystemLog "sqlite3コマンドでSQL実行中..." -Level "Info"
        
        # sqlite3コマンドの実行と結果の確認
        $sqliteResult = & sqlite3 $DatabasePath ".read $tempSqlFile" 2>&1
        
        if ($LASTEXITCODE -ne 0) {
            throw "sqlite3コマンドの実行に失敗しました。終了コード: $LASTEXITCODE, 出力: $sqliteResult"
        }
        
        Write-SystemLog "sqlite3コマンドでの実行が完了しました" -Level "Success"
    }
    finally {
        if (Test-Path $tempSqlFile) {
            Remove-Item -Path $tempSqlFile -Force
        }
    }
}


# SQLiteコマンド実行（汎用）
function script:Invoke-SqliteCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [string]$Query,
        
        [hashtable]$Parameters = @{},
        
        [string]$CsvOutputPath = "",
        
        [switch]$CsvOutput
    )
    
    return Invoke-ExternalCommandWithErrorHandling -ScriptBlock {
        try {
            $sqlite3Path = Get-Sqlite3Path
            # CSV出力モードの処理
            if ($CsvOutput -and -not [string]::IsNullOrEmpty($CsvOutputPath)) {
                $csvResult = Invoke-WithErrorHandling -ScriptBlock {
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
                } -Category External -Operation "SQLite CSV出力" -SuppressThrow
                
                if ($null -ne $csvResult) {
                    return $csvResult
                }
                else {
                    Write-SystemLog "SQLite直接CSV出力に失敗しました。通常処理を続行します。" -Level "Warning"
                }
            }
            
            # 通常のSQLite3コマンド実行
            return Invoke-WithErrorHandling -ScriptBlock {
                $tempFile = [System.IO.Path]::GetTempFileName()
                try {
                    $encoding = Get-CrossPlatformEncoding
                    $Query | Out-File -FilePath $tempFile -Encoding $encoding
                    
                    $result = & sqlite3 $DatabasePath ".read $tempFile" 2>&1
                    
                    if ($LASTEXITCODE -ne 0) {
                        throw "sqlite3コマンドエラー (終了コード: $LASTEXITCODE): $result"
                    }
                    
                    return $result
                }
                finally {
                    if (Test-Path $tempFile) {
                        Remove-Item -Path $tempFile -Force
                    }
                }
            } -Category External -Operation "SQLite一時ファイル処理"
        }
        catch {
            throw "SQLite3の実行に失敗しました: $($_.Exception.Message)"
        }
    } -CommandName "sqlite3" -Operation "SQLiteコマンド実行"
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