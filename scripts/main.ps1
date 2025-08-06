# PowerShell & SQLite 職員データ管理システム
# メインスクリプト（設定ベース版）

param(
    [string]$ProvidedDataFilePath = "",
    
    [string]$CurrentDataFilePath = "",
    
    [string]$OutputFilePath = "",
    
    [string]$DatabasePath = ""
)

# スクリプトの実行パスを取得
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptPath

# 共通ユーティリティと他のスクリプトファイルをインポート
. "$ScriptPath\config-utils.ps1"
. "$ScriptPath\sql-utils.ps1"
. "$ScriptPath\file-utils.ps1"
. "$ScriptPath\data-filter-utils.ps1"
. "$ScriptPath\common-utils.ps1"
. "$ScriptPath\database.ps1"
. "$ScriptPath\csv-utils.ps1"
. "$ScriptPath\sync-data.ps1"

function Main {
    param(
        [string]$ProvidedDataFilePath,
        [string]$CurrentDataFilePath,
        [string]$OutputFilePath,
        [string]$DatabasePath
    )
    # DatabasePathが空の場合はデフォルトパスを設定
    if ([string]::IsNullOrEmpty($DatabasePath)) {
        $DatabasePath = Join-Path $ProjectRoot "database" "data-sync.db"
    }
    
    Write-SystemLog "=== 職員データ管理システム 開始 ===" -Level "Success"
    
    try {
        # 1. 設定の検証とファイルパス設定の取得
        Write-SystemLog "データ同期設定を検証中..." -Level "Info"
        if (-not (Test-DataSyncConfig)) {
            throw "データ同期設定の検証に失敗しました"
        }
        
        # ファイルパス設定を取得
        $filePathConfig = Get-FilePathConfig
        
        # 入力ファイルパスの解決
        $resolvedProvidedDataPath = Resolve-FilePath -ParameterPath $ProvidedDataFilePath -ConfigKey "provided_data_file_path" -Description "提供データファイル"
        $resolvedCurrentDataPath = Resolve-FilePath -ParameterPath $CurrentDataFilePath -ConfigKey "current_data_file_path" -Description "現在データファイル"
        
        # 出力ファイルパスの解決
        $resolvedOutputPath = Resolve-FilePath -ParameterPath $OutputFilePath -ConfigKey "output_file_path" -Description "出力ファイル"
        
        Write-SystemLog "データベースを初期化中..." -Level "Info"
        Write-SystemLog "Database Path: $DatabasePath" -Level "Info"
        Write-SystemLog "Provided Data File: $resolvedProvidedDataPath" -Level "Info"
        Write-SystemLog "Current Data File: $resolvedCurrentDataPath" -Level "Info"
        Write-SystemLog "Output File: $resolvedOutputPath" -Level "Info"
        Write-SystemLog "Output History Directory: $($filePathConfig.output_history_directory)" -Level "Info"
        
        # 1. DBの初期化
        Initialize-Database -DatabasePath $DatabasePath
        
        # 2. 提供データCSVの読み込み・格納（単一ファイル + 履歴保存）
        Write-SystemLog "提供データCSVを読み込み中..." -Level "Info"
        Import-ProvidedDataCsv -CsvPath $resolvedProvidedDataPath -DatabasePath $DatabasePath
        
        # 3. 現在データCSVの読み込み・格納（単一ファイル + 履歴保存）
        Write-SystemLog "現在データCSVを読み込み中..." -Level "Info"
        Import-CurrentDataCsv -CsvPath $resolvedCurrentDataPath -DatabasePath $DatabasePath
        
        # 4. データ比較・同期処理
        Write-SystemLog "データ同期処理を実行中..." -Level "Info"
        Sync-StaffData -DatabasePath $DatabasePath
        
        # データ整合性チェック
        Write-SystemLog "データ整合性をチェック中..." -Level "Info"
        if (-not (Test-DataConsistency -DatabasePath $DatabasePath)) {
            Write-SystemLog "データ整合性エラーが検出されました" -Level "Warning"
        }
        
        # 5. 結果をCSVファイルに出力（外部パス + 履歴保存）
        Write-SystemLog "結果をCSVファイルに出力中..." -Level "Info"
        Export-SyncResult -DatabasePath $DatabasePath -OutputFilePath $resolvedOutputPath
        
        # 同期レポートの表示
        Get-SyncReport -DatabasePath $DatabasePath
        
        # データベース情報の表示
        Show-DatabaseInfo -DatabasePath $DatabasePath
        
        Write-SystemLog "=== 職員データ管理システム 完了 ===" -Level "Success"
        
    }
    catch {
        Write-SystemLog "エラーが発生しました: $($_.Exception.Message)" -Level "Error"
        Write-SystemLog "スタックトレース: $($_.ScriptStackTrace)" -Level "Error"
        throw
    }
}

# メイン処理実行
Main -ProvidedDataFilePath $ProvidedDataFilePath -CurrentDataFilePath $CurrentDataFilePath -OutputFilePath $OutputFilePath -DatabasePath $DatabasePath