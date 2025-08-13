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
. "$ScriptPath\utils\config-utils.ps1"
. "$ScriptPath\utils\sql-utils.ps1"
. "$ScriptPath\utils\file-utils.ps1"
. "$ScriptPath\utils\data-filter-utils.ps1"
. "$ScriptPath\utils\common-utils.ps1"
. "$ScriptPath\utils\error-handling-utils.ps1"
. "$ScriptPath\database.ps1"
. "$ScriptPath\utils\csv-utils.ps1"
. "$ScriptPath\sync-data.ps1"

function Main {
    param(
        [string]$DatabasePath,
        [string]$ProvidedDataFilePath,
        [string]$CurrentDataFilePath,
        [string]$OutputFilePath
    )

    # ログファイルの初期化（最初に実行）
    Initialize-LogFile

    Write-SystemLog "=== 同期データ比較システム 開始 ===" -Level "Success"
        
    # 統合エラーハンドリングでメイン処理を実行
    Invoke-WithErrorHandling -Category System -Operation "メイン処理" -Context @{
        "DatabasePath"         = $DatabasePath
        "ProvidedDataFilePath" = $ProvidedDataFilePath
        "CurrentDataFilePath"  = $CurrentDataFilePath
        "OutputFilePath"       = $OutputFilePath
    } -ScriptBlock {

        # DatabasePathが未指定の場合、デフォルトを設定
        if ([string]::IsNullOrEmpty($DatabasePath)) {
            $DatabasePath = Join-Path $ProjectRoot "database" "data-sync.db"
            Write-SystemLog "DatabasePathが未指定のため、デフォルトパスを使用します: $DatabasePath" -Level "Info"
        }
    
        # 1. 設定の検証とファイルパス設定の取得
        Invoke-WithErrorHandling -Category System -Operation "設定の検証" -ScriptBlock {
            if (-not (Test-DataSyncConfig)) {
                throw "設定の検証に失敗しました"
            }
        }
        
        # ファイルパス設定を取得
        $filePathConfig = Get-FilePathConfig
        
        # 入力ファイルパスの解決
        $resolvedProvidedDataPath = Invoke-WithErrorHandling -ScriptBlock {
            Resolve-FilePath -ParameterPath $ProvidedDataFilePath -ConfigKey "provided_data_file_path" -Description "提供データファイル"
        } -Category External -Operation "提供データファイルパス解決"
        
        $resolvedCurrentDataPath = Invoke-WithErrorHandling -ScriptBlock {
            Resolve-FilePath -ParameterPath $CurrentDataFilePath -ConfigKey "current_data_file_path" -Description "現在データファイル"
        } -Category External -Operation "現在データファイルパス解決"
        
        # 出力ファイルパスの解決
        $resolvedOutputPath = Invoke-WithErrorHandling -ScriptBlock {
            Resolve-FilePath -ParameterPath $OutputFilePath -ConfigKey "output_file_path" -Description "出力ファイル"
        } -Category External -Operation "出力ファイルパス解決"
        
        Write-SystemLog "データベースを初期化中..." -Level "Info"
        Write-SystemLog "Database Path: $DatabasePath" -Level "Info"
        Write-SystemLog "Provided Data File: $resolvedProvidedDataPath" -Level "Info"
        Write-SystemLog "Current Data File: $resolvedCurrentDataPath" -Level "Info"
        Write-SystemLog "Output File: $resolvedOutputPath" -Level "Info"
        Write-SystemLog "Output History Directory: $($filePathConfig.output_history_directory)" -Level "Info"
        
        # 1. DBの初期化
        Invoke-WithErrorHandling -ScriptBlock {
            Initialize-Database -DatabasePath $DatabasePath
        } -Category External -Operation "データベース初期化"
        
        # 2. 提供データCSVの読み込み・格納（単一ファイル + 履歴保存）
        Write-SystemLog "提供データCSVを読み込み中..." -Level "Info"
        Import-DataCsvByType -CsvPath $resolvedProvidedDataPath -DatabasePath $DatabasePath -DataType "provided_data"
        
        # 3. 現在データCSVの読み込み・格納（単一ファイル + 履歴保存）
        Write-SystemLog "現在データCSVを読み込み中..." -Level "Info"
        Import-DataCsvByType -CsvPath $resolvedCurrentDataPath -DatabasePath $DatabasePath -DataType "current_data"
        
        # 4. データ比較・同期処理
        Invoke-WithErrorHandling -ScriptBlock {
            Write-SystemLog "データ同期処理を実行中..." -Level "Info"
            Sync-Data -DatabasePath $DatabasePath
        } -Category External -Operation "データ同期処理"
        
        # データ整合性チェック
        Invoke-SafeOperation -Operation {
            Write-SystemLog "データ整合性をチェック中..." -Level "Info"
            if (-not (Test-DataConsistency -DatabasePath $DatabasePath)) {
                Write-SystemLog "データ整合性エラーが検出されました" -Level "Warning"
                return "整合性エラー検出"
            }
            else {
                return "整合性チェック完了"
            }
        } -OperationName "データ整合性チェック" -Category Data -DefaultReturn "整合性チェックスキップ" | Out-Null
        
        # 5. 結果をCSVファイルに出力（外部パス + 履歴保存）
        Write-SystemLog "結果をCSVファイルに出力中..." -Level "Info"
        Invoke-WithErrorHandling -ScriptBlock {
            Export-SyncResult -DatabasePath $DatabasePath -OutputFilePath $resolvedOutputPath
        } -Category External -Operation "同期結果CSV出力"
        
        # 同期レポートの表示
        Invoke-SafeOperation -Operation {
            Get-SyncReport -DatabasePath $DatabasePath
            return "レポート表示完了"
        } -OperationName "同期レポート表示" -Category Data -DefaultReturn "レポート表示スキップ" | Out-Null
        
        # データベース情報の表示
        Invoke-SafeOperation -Operation {
            Show-DatabaseInfo -DatabasePath $DatabasePath
            return "表示完了"  # 明示的に成功を示す戻り値
        } -OperationName "データベース情報表示" -Category System -DefaultReturn "表示スキップ" | Out-Null
                
    } 

    Write-SystemLog "=== 同期データ比較システム 完了 ===" -Level "Success"

}

# メイン処理実行
Main -ProvidedDataFilePath $ProvidedDataFilePath -CurrentDataFilePath $CurrentDataFilePath -OutputFilePath $OutputFilePath -DatabasePath $DatabasePath