# PowerShell & SQLite データ管理システム
# 設定検証・パラメータ解決処理スクリプト（レイヤー化版）

using module "../Utils/Foundation/CoreUtils.psm1"
using module "../Utils/Infrastructure/LoggingUtils.psm1"
using module "../Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../Utils/Infrastructure/ErrorHandlingUtils.psm1"
using module "../Utils/DataAccess/DatabaseUtils.psm1"
using module "../Utils/DataAccess/FileSystemUtils.psm1"
using module "../Utils/DataProcessing/CsvProcessingUtils.psm1"
using module "../Utils/DataProcessing/DataFilteringUtils.psm1"

# 設定検証とパラメータ解決の統合処理
function Invoke-ConfigValidation {
    param(
        [string]$DatabasePath = "",
        [string]$ProvidedDataFilePath = "",
        [string]$CurrentDataFilePath = "",
        [string]$OutputFilePath = "",
        [string]$ConfigFilePath = ""
    )
    
    return Invoke-WithErrorHandling -Category System -Operation "設定検証・パラメータ解決処理" -Context @{
        "DatabasePath"         = $DatabasePath
        "ProvidedDataFilePath" = $ProvidedDataFilePath
        "CurrentDataFilePath"  = $CurrentDataFilePath
        "OutputFilePath"       = $OutputFilePath
        "ConfigFilePath"       = $ConfigFilePath
    } -ScriptBlock {

        # DatabasePathが未指定の場合、デフォルトを設定
        $resolvedDatabasePath = $DatabasePath
        if ([string]::IsNullOrEmpty($resolvedDatabasePath)) {
            $PrjRoot = Find-ProjectRoot
            $resolvedDatabasePath = Join-Path $PrjRoot "database" "data-sync.db"
            Write-SystemLog "DatabasePathが未指定のため、デフォルトパスを使用します: $resolvedDatabasePath" -Level "Info"
        }
    
        # 1. 外部依存関係の検証
        Write-SystemLog "外部依存関係を検証中..." -Level "Info"
        $sqlite3Path = Get-Sqlite3Path
        Write-SystemLog "SQLite3コマンドが利用可能です: $($sqlite3Path.Source)" -Level "Success"
        
        # 2. 設定の検証
        Write-SystemLog "システム設定を検証中..." -Level "Info"
        $config = Get-DataSyncConfig
        Test-DataSyncConfig $config
        
        # 3. ファイルパスの解決
        Write-SystemLog "ファイルパス解決処理を開始..." -Level "Info"
        $resolvedProvidedDataPath = Resolve-FilePath -ParameterPath $ProvidedDataFilePath -ConfigKey "provided_data_file_path" -Description "提供データファイル"
        $resolvedCurrentDataPath = Resolve-FilePath -ParameterPath $CurrentDataFilePath -ConfigKey "current_data_file_path" -Description "現在データファイル"
        $resolvedOutputPath = Resolve-FilePath -ParameterPath $OutputFilePath -ConfigKey "output_file_path" -Description "出力ファイル"
        
        # 4. 解決されたパラメータのファイル存在チェック
        $resolvedParams = @{
            DatabasePath         = $resolvedDatabasePath
            ProvidedDataFilePath = $resolvedProvidedDataPath
            CurrentDataFilePath  = $resolvedCurrentDataPath
            OutputFilePath       = $resolvedOutputPath
        }
        
        Write-SystemLog "入力ファイル・出力フォルダの存在チェック中..." -Level "Info"
        Test-ResolvedFilePaths -ResolvedPaths $resolvedParams
        Write-SystemLog "ファイルパス存在チェックが完了しました" -Level "Success"

        # 5. 処理パラメータのログ出力
        Write-SystemLog "----- 処理パラメータ -----" -Level "Info"
        Write-SystemLog "Database Path: $resolvedDatabasePath" -Level "Info"
        Write-SystemLog "Provided Data File: $resolvedProvidedDataPath" -Level "Info"
        Write-SystemLog "Current Data File: $resolvedCurrentDataPath" -Level "Info"
        Write-SystemLog "Output File: $resolvedOutputPath" -Level "Info"
        Write-SystemLog "-------------------------" -Level "Info"
                        
        return $resolvedParams
    }
}

# ファイル存在チェック（設定完了後の検証）
function Test-ResolvedFilePaths {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$ResolvedPaths       
    )
    
    Invoke-WithErrorHandling -Category External -Operation "ファイルパス存在チェック" -Context $ResolvedPaths -ScriptBlock {
        # 提供データファイルの存在チェック
        if (-not (Test-Path $ResolvedPaths.ProvidedDataFilePath)) {
            throw "提供データファイルが見つかりません: $($ResolvedPaths.ProvidedDataFilePath)"
        }
        # 現在データファイルの存在チェック
        if (-not (Test-Path $ResolvedPaths.CurrentDataFilePath)) {
            throw "現在データファイルが見つかりません: $($ResolvedPaths.CurrentDataFilePath)"
        }
        # 出力ファイルのディレクトリチェック（オプション）
        $outputDir = Split-Path -Path $ResolvedPaths.OutputFilePath -Parent
        if (-not (Test-Path $outputDir)) {
            throw  "出力ディレクトリが存在しません: $outputDir"
        }
    }
}

Export-ModuleMember -Function 'Invoke-ConfigValidation'
