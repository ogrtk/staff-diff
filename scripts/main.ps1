# PowerShell & SQLite 職員データ管理システム
# メインスクリプト（設定ベース版）

param(
    [string]$StaffInfoFilePath = "",
    
    [string]$StaffMasterFilePath = "",
    
    [string]$OutputFilePath = "",
    
    [string]$DatabasePath = ""
)

# スクリプトの実行パスを取得
$ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
$ProjectRoot = Split-Path -Parent $ScriptPath

# DatabasePathが空の場合はデフォルトパスを設定
if ([string]::IsNullOrEmpty($DatabasePath)) {
    $DatabasePath = Join-Path $ProjectRoot "database\staff.db"
}

# 共通ユーティリティと他のスクリプトファイルをインポート
. "$ScriptPath\common-utils.ps1"
. "$ScriptPath\database.ps1"
. "$ScriptPath\csv-utils.ps1"
. "$ScriptPath\sync-data.ps1"

function Main {
    param(
        [string]$StaffInfoFilePath,
        [string]$StaffMasterFilePath,
        [string]$OutputFilePath,
        [string]$DatabasePath
    )
    
    # DatabasePathが空の場合はデフォルトパスを設定
    if ([string]::IsNullOrEmpty($DatabasePath)) {
        $ScriptPath = Split-Path -Parent $MyInvocation.MyCommand.Definition
        $ProjectRoot = Split-Path -Parent $ScriptPath
        $DatabasePath = Join-Path $ProjectRoot "database\staff.db"
    }
    
    Write-SystemLog "=== 職員データ管理システム 開始 ===" -Level "Success"
    
    try {
        # 1. 設定の検証とファイルパス設定の取得
        Write-SystemLog "スキーマ設定を検証中..." -Level "Info"
        if (-not (Test-SchemaConfig)) {
            throw "スキーマ設定の検証に失敗しました"
        }
        
        # ファイルパス設定を取得
        $filePathConfig = Get-FilePathConfig
        
        # 入力ファイルパスの解決
        $resolvedStaffInfoPath = Resolve-InputFilePath -ParameterPath $StaffInfoFilePath -ConfigPath $filePathConfig.staff_info_file_path -FileType "職員情報"
        $resolvedStaffMasterPath = Resolve-InputFilePath -ParameterPath $StaffMasterFilePath -ConfigPath $filePathConfig.staff_master_file_path -FileType "職員マスタ"
        
        Write-SystemLog "データベースを初期化中..." -Level "Info"
        Write-SystemLog "Database Path: $DatabasePath" -Level "Info"
        Write-SystemLog "Staff Info File: $resolvedStaffInfoPath" -Level "Info"
        Write-SystemLog "Staff Master File: $resolvedStaffMasterPath" -Level "Info"
        Write-SystemLog "Output File: $OutputFilePath" -Level "Info"
        Write-SystemLog "Output History Directory: $($filePathConfig.output_history_directory)" -Level "Info"
        
        Initialize-Database -DatabasePath $DatabasePath
        
        # 2. 職員情報CSVの読み込み・格納（単一ファイル + 履歴保存）
        Write-SystemLog "職員情報CSVを読み込み中..." -Level "Info"
        Import-StaffInfoCsv -CsvPath $resolvedStaffInfoPath -DatabasePath $DatabasePath
        
        # 3. 職員マスタデータCSVの読み込み・格納（単一ファイル + 履歴保存）
        Write-SystemLog "職員マスタデータCSVを読み込み中..." -Level "Info"
        Import-StaffMasterCsv -CsvPath $resolvedStaffMasterPath -DatabasePath $DatabasePath
        
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
        Export-SyncResult -DatabasePath $DatabasePath -OutputFilePath $OutputFilePath
        
        # 同期レポートの表示
        Get-SyncReport -DatabasePath $DatabasePath
        
        # データベース情報の表示
        Show-DatabaseInfo -DatabasePath $DatabasePath
        
        Write-SystemLog "=== 職員データ管理システム 完了 ===" -Level "Success"
        
    } catch {
        Write-SystemLog "エラーが発生しました: $($_.Exception.Message)" -Level "Error"
        Write-SystemLog "スタックトレース: $($_.ScriptStackTrace)" -Level "Error"
        throw
    }
}

# メイン処理実行
Main -StaffInfoFilePath $StaffInfoFilePath -StaffMasterFilePath $StaffMasterFilePath -OutputFilePath $OutputFilePath -DatabasePath $DatabasePath