# PowerShell & SQLite 職員データ管理システム
# CSV処理ユーティリティスクリプト（設定ベース版）

# 共通ユーティリティの読み込み
. (Join-Path $PSScriptRoot "common-utils.ps1")

# 職員情報CSVをデータベースにインポート（単一ファイル + 履歴保存対応）
function Import-StaffInfoCsv {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    if (-not (Test-Path $CsvPath)) {
        throw "CSVファイルが見つかりません: $CsvPath"
    }
    
    try {
        Write-SystemLog "職員情報CSVをインポート中: $CsvPath" -Level "Info"
        
        # ファイルパス設定を取得
        $filePathConfig = Get-FilePathConfig
        
        # 履歴ディレクトリにコピー保存
        $historyPath = Copy-InputFileToHistory -SourceFilePath $CsvPath -HistoryDirectory $filePathConfig.staff_info_history_directory -FileType "職員情報"
        
        # CSVフォーマットの検証
        if (-not (Test-CsvFormat -CsvPath $CsvPath -TableName "staff_info")) {
            throw "CSVフォーマットの検証に失敗しました"
        }
        
        # CSVファイルを読み込み
        $csvData = Import-Csv -Path $CsvPath -Encoding UTF8
        
        # データフィルタリングを適用
        $filteredData = Invoke-DataFiltering -TableName "staff_info" -Data $csvData
        
        # 既存データをクリア
        Clear-Table -DatabasePath $DatabasePath -TableName "staff_info"
        
        # 設定ベースでフィルタリング済みデータをデータベースに挿入
        foreach ($row in $filteredData) {
            $data = @{}
            foreach ($property in $row.PSObject.Properties) {
                $data[$property.Name] = $property.Value
            }
            
            $query = New-InsertSql -TableName "staff_info" -Data $data
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
        }
        
        Write-SystemLog "職員情報CSVのインポートが完了しました。処理件数: $($filteredData.Count) / 読み込み件数: $($csvData.Count)" -Level "Success"
        
    } catch {
        Write-SystemLog "職員情報CSVのインポートに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 職員マスタCSVをデータベースにインポート（単一ファイル + 履歴保存対応）
function Import-StaffMasterCsv {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath
    )
    
    if (-not (Test-Path $CsvPath)) {
        throw "CSVファイルが見つかりません: $CsvPath"
    }
    
    try {
        Write-SystemLog "職員マスタCSVをインポート中: $CsvPath" -Level "Info"
        
        # ファイルパス設定を取得
        $filePathConfig = Get-FilePathConfig
        
        # 履歴ディレクトリにコピー保存
        $historyPath = Copy-InputFileToHistory -SourceFilePath $CsvPath -HistoryDirectory $filePathConfig.staff_master_history_directory -FileType "職員マスタ"
        
        # CSVフォーマットの検証
        if (-not (Test-CsvFormat -CsvPath $CsvPath -TableName "staff_master")) {
            throw "CSVフォーマットの検証に失敗しました"
        }
        
        # CSVファイルを読み込み
        $csvData = Import-Csv -Path $CsvPath -Encoding UTF8
        
        # データフィルタリングを適用
        $filteredData = Invoke-DataFiltering -TableName "staff_master" -Data $csvData
        
        # 既存データをクリア
        Clear-Table -DatabasePath $DatabasePath -TableName "staff_master"
        
        # 設定ベースでフィルタリング済みデータをデータベースに挿入
        foreach ($row in $filteredData) {
            $data = @{}
            foreach ($property in $row.PSObject.Properties) {
                $data[$property.Name] = $property.Value
            }
            
            $query = New-InsertSql -TableName "staff_master" -Data $data
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
        }
        
        Write-SystemLog "職員マスタCSVのインポートが完了しました。処理件数: $($filteredData.Count) / 読み込み件数: $($csvData.Count)" -Level "Success"
        
    } catch {
        Write-SystemLog "職員マスタCSVのインポートに失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 同期結果をCSVファイルにエクスポート（外部パス出力 + 履歴保存対応）
function Export-SyncResult {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [string]$OutputFilePath = ""
    )
    
    try {
        $filePathConfig = Get-FilePathConfig
        
        # 出力ファイルパスの解決
        $resolvedOutputPath = ""
        if (-not [string]::IsNullOrEmpty($OutputFilePath)) {
            $resolvedOutputPath = $OutputFilePath
            Write-SystemLog "出力: パラメータで指定されたパス: $resolvedOutputPath" -Level "Info"
        } elseif (-not [string]::IsNullOrEmpty($filePathConfig.output_file_path)) {
            $resolvedOutputPath = $filePathConfig.output_file_path
            Write-SystemLog "出力: 設定ファイルで指定されたパス: $resolvedOutputPath" -Level "Info"
        } else {
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
        
    } catch {
        Write-SystemLog "CSVファイルの出力に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 同期結果をファイルにエクスポート（内部関数）
function Export-SyncResultToFile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DatabasePath,
        
        [Parameter(Mandatory=$true)]
        [string]$OutputPath
    )
    
    try {
        # 出力ディレクトリが存在しない場合は作成
        $outputDir = Split-Path -Parent $OutputPath
        if (-not (Test-Path $outputDir)) {
            New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
        }
        
        # 設定ベースで同期結果を取得
        $query = New-SelectSql -TableName "sync_result" -OrderBy "employee_id"
        
        # SQLite結果をCSVとして直接エクスポート
        $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if ($sqlite3Path) {
            # 設定ベースでCSVヘッダーを生成
            $headers = New-CsvHeader -TableName "sync_result"
            $headers | Out-File -FilePath $OutputPath -Encoding UTF8
            
            & sqlite3 -csv $DatabasePath $query | Out-File -FilePath $OutputPath -Append -Encoding UTF8
        } else {
            # PowerShellでの処理
            $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $query
            $result | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        }
        
        Write-SystemLog "同期結果をCSVファイルに出力しました: $OutputPath" -Level "Success"
        
    } catch {
        Write-SystemLog "CSVファイルの出力に失敗しました: $($_.Exception.Message)" -Level "Error"
        throw
    }
}

# 同期統計情報の表示
function Show-SyncStatistics {
    param(
        [Parameter(Mandatory=$true)]
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
        
        # SQLite3コマンドラインでCSV形式で結果を取得
        $sqlite3Path = Get-Command sqlite3 -ErrorAction SilentlyContinue
        if ($sqlite3Path) {
            $result = & sqlite3 -csv $DatabasePath $statsQuery
        } else {
            $result = Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $statsQuery
        }
        
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
        } else {
            Write-Host "統計データがありません" -ForegroundColor Gray
        }
        Write-Host "=====================" -ForegroundColor Yellow
        
    } catch {
        Write-Warning "統計情報の取得に失敗しました: $($_.Exception.Message)"
    }
}

# CSVファイルのバリデーション（設定ベース版）
function Test-CsvFormat {
    param(
        [Parameter(Mandatory=$true)]
        [string]$CsvPath,
        
        [Parameter(Mandatory=$true)]
        [string]$TableName
    )
    
    try {
        $csvData = Import-Csv -Path $CsvPath -Encoding UTF8
        $headers = $csvData[0].PSObject.Properties.Name
        
        # 設定ベースで必要カラムを取得
        $requiredColumns = Get-RequiredColumns -TableName $TableName
        
        $missingColumns = $requiredColumns | Where-Object { $_ -notin $headers }
        
        if ($missingColumns.Count -gt 0) {
            Write-SystemLog "必要なカラムが不足しています: $($missingColumns -join ', ')" -Level "Warning"
            return $false
        }
        
        Write-SystemLog "CSVフォーマットの検証が完了しました: $(Split-Path -Leaf $CsvPath)" -Level "Success"
        return $true
        
    } catch {
        Write-SystemLog "CSVファイルの検証に失敗しました: $($_.Exception.Message)" -Level "Error"
        return $false
    }
}