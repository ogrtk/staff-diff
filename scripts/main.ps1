# PowerShell & SQLite データ同期システム
# メインスクリプト（エントリーポイント）

using module "./modules/Utils/Foundation/CoreUtils.psm1"
using module "./modules/Utils/Infrastructure/LoggingUtils.psm1"
using module "./modules/Utils/Infrastructure/ConfigurationUtils.psm1"
using module "./modules/Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "./modules/Utils/DataAccess/DatabaseUtils.psm1"
using module "./modules/Utils/DataAccess/FileSystemUtils.psm1"
using module "./modules/Utils/DataProcessing/CsvProcessingUtils.psm1"
using module "./modules/Utils/DataProcessing/DataFilteringUtils.psm1"
using module "./modules/Process/Invoke-ConfigValidation.psm1"
using module "./modules/Process/Invoke-CsvExport.psm1"
using module "./modules/Process/Invoke-CsvImport.psm1"
using module "./modules/Process/Invoke-DatabaseInitialization.psm1"
using module "./modules/Process/Invoke-DataSync.psm1"
using module "./modules/Process/Show-SyncResult.psm1"
using module "./modules/Process/Test-DataConsistency.psm1"

# パラメータ定義
param(
    [string]$ProvidedDataFilePath = "",
    [string]$CurrentDataFilePath = "",
    [string]$OutputFilePath = "",
    [string]$DatabasePath = "",
    [string]$ConfigFilePath = ""
)

# 堅牢なエラーハンドリング
$ErrorActionPreference = "Stop"

try {
    # --- 初期設定: 設定ファイルの読み込み ---
    # 全ての処理に先立ち、設定ファイルを読み込んでキャッシュする
    Get-DataSyncConfig -ConfigPath $ConfigFilePath | Out-Null

    # --- 処理開始 ---
    Write-SystemLog "======================================" -Level "Info"
    Write-SystemLog "===== データ同期処理を開始します =====" -Level "Info"
    Write-SystemLog "======================================" -Level "Info"
    $startTime = Get-Date

    # 1. 設定検証とパラメータ解決
    $params = Invoke-ConfigValidation -DatabasePath $DatabasePath -ProvidedDataFilePath $ProvidedDataFilePath -CurrentDataFilePath $CurrentDataFilePath -OutputFilePath $OutputFilePath -ConfigFilePath $configPath

    # 2. データベースの初期化
    Invoke-DatabaseInitialization -DatabasePath $params.DatabasePath

    # 3. 提供データのインポート
    Invoke-CsvImport -CsvPath $params.ProvidedDataFilePath -DatabasePath $params.DatabasePath -DataType "provided_data"

    # 4. 現在データのインポート
    Invoke-CsvImport -CsvPath $params.CurrentDataFilePath -DatabasePath $params.DatabasePath -DataType "current_data"

    # 5. データ同期
    Invoke-DataSync -DatabasePath $params.DatabasePath

    # 6. データ整合性チェック
    Test-DataConsistency -DatabasePath $params.DatabasePath

    # 7. 同期結果のエクスポート
    Invoke-CsvExport -DatabasePath $params.DatabasePath -OutputFilePath $params.OutputFilePath

    # 8. 統合同期結果の表示
    Show-SyncResult -DatabasePath $params.DatabasePath -ProvidedDataFilePath $params.ProvidedDataFilePath -CurrentDataFilePath $params.CurrentDataFilePath

    # --- 処理終了 ---
    $endTime = Get-Date
    $duration = New-TimeSpan -Start $startTime -End $endTime
    Write-SystemLog "すべての処理が正常に完了しました。" -Level "Success"
    Write-SystemLog "合計処理時間: $($duration.TotalSeconds) 秒" -Level "Info"

    Write-SystemLog "======================================" -Level "Info"
    Write-SystemLog "===== データ同期処理を終了します =====" -Level "Info"
    Write-SystemLog "======================================" -Level "Info"

}
catch {
    # 致命的なエラー処理
    Write-SystemLog "スクリプトの実行中に致命的なエラーが発生しました: $($_.Exception.Message)" -Level "Error"
    if ($_.ScriptStackTrace) {
        Write-SystemLog "スタックトレース: `n$($_.ScriptStackTrace)" -Level "Error"
    }
    exit 1
} 