# PowerShell & SQLite 職員データ管理システム
# データベース初期化モジュール

# 動的データベース初期化（冪等性・リトライ対応）
function Invoke-DatabaseInitialization {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath
    )
    
    # 冪等性確保のためのクリーンアップ（データベースファイル確認・復旧）
    $cleanupScript = {
        try {
            # 既存データベースファイルの検証
            if (Test-Path $DatabasePath) {
                $dbInfo = Get-Item $DatabasePath -ErrorAction SilentlyContinue
                if ($dbInfo) {
                    Write-SystemLog "既存データベースファイル: $($dbInfo.Length) bytes, 最終更新: $($dbInfo.LastWriteTime)" -Level "Info"
                    
                    # データベースファイルの整合性チェック（基本的な検証）
                    if ($dbInfo.Length -eq 0) {
                        Write-SystemLog "空のデータベースファイルを検出、削除して再作成します" -Level "Warning"
                        Remove-Item $DatabasePath -Force -ErrorAction SilentlyContinue
                    }
                }
            }
            
            # データベースディレクトリの再確認
            $dbDir = Split-Path -Path $DatabasePath -Parent
            if (-not (Test-Path $dbDir)) {
                Write-SystemLog "データベースディレクトリが存在しません。再作成します: $dbDir" -Level "Info"
                New-Item -ItemType Directory -Path $dbDir -Force -ErrorAction SilentlyContinue | Out-Null
            }
        }
        catch {
            Write-SystemLog "データベースクリーンアップ中にエラー: $($_.Exception.Message)" -Level "Warning"
        }
    }
    
    Invoke-WithErrorHandling -Category External -Operation "データベース初期化処理" -CleanupScript $cleanupScript -Context @{
        "DatabasePath" = $DatabasePath
    } -ScriptBlock {
        
        # データベースディレクトリの作成
        $dbDir = Split-Path -Path $DatabasePath -Parent
        if (-not (Test-Path $dbDir)) {
            Invoke-WithErrorHandling -ScriptBlock {
                New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
                Write-SystemLog "データベースディレクトリを作成しました: $dbDir" -Level "Info"
            } -Category External -Operation "ディレクトリ作成" -Context @{"ファイルパス" = $dbDir; "操作種別" = "ディレクトリ作成" } -CleanupScript {
                # ファイル操作特有のクリーンアップ
                if (Test-Path $dbDir -ErrorAction SilentlyContinue) {
                    $fileInfo = Get-Item $dbDir -ErrorAction SilentlyContinue
                    if ($fileInfo) {
                        Write-SystemLog "ファイル情報 - サイズ: $($fileInfo.Length) bytes, 最終更新: $($fileInfo.LastWriteTime)" -Level "Info"
                    }
                }
            }
        }
        
        Write-SystemLog "データベース初期化を開始します..." -Level "Info"
        
        # 1. SQL文の生成
        $sqlStatements = New-DatabaseSchema
        
        # 2. SQL文の実行（外部コマンド依存）
        Invoke-WithErrorHandling -ScriptBlock {
            Invoke-DatabaseInitializationInternal -DatabasePath $DatabasePath -SqlStatements $sqlStatements
        } -Category External -Operation "データベーススキーマ作成" -Context @{"コマンド名" = "sqlite3"; "操作種別" = "データベーススキーマ作成" } -CleanupScript {
            # 外部コマンド特有のクリーンアップ
            Write-SystemLog "外部コマンドの終了コード: $LASTEXITCODE" -Level "Info"
            
            # sqlite3コマンドは設定検証で確認済み
        }
        
        Write-SystemLog "データベースが正常に初期化されました: $DatabasePath" -Level "Success"
    }
}

# データベーススキーマのSQL文を生成（責務の分離）
function New-DatabaseSchema {
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
function Invoke-DatabaseInitializationInternal {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory = $true)]
        [array]$SqlStatements
    )
    
    $combinedSql = $SqlStatements -join "`n`n"
    
    Invoke-SqliteSchemaCommand -DatabasePath $DatabasePath -SqlContent $combinedSql
}

# SQLite3コマンドでのSQL実行（スキーマ初期化専用）
function Invoke-SqliteSchemaCommand {
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

Export-ModuleMember -Function 'Invoke-DatabaseInitialization'