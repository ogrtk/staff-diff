# PowerShell & SQLite データ同期システム
# レイヤアーキテクチャ対応テストヘルパーモジュール

using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"

# テスト環境設定
function Initialize-TestEnvironment {
    param(
        [string]$TestConfigPath = "",
        [switch]$CreateTempDatabase,
        [switch]$CleanupBefore
    )
    
    # 環境変数設定（Pesterテスト実行中であることを示す）
    $env:PESTER_TEST = "1"
    
    # プロジェクトルートを取得
    $ProjectRoot = Find-ProjectRoot
    
    # テスト用設定ファイルの設定
    if ([string]::IsNullOrEmpty($TestConfigPath)) {
        $TestConfigPath = Join-Path $ProjectRoot "config" "data-sync-config.json"
    }
    
    # クリーンアップ処理
    if ($CleanupBefore) {
        Clear-TestEnvironment -ProjectRoot $ProjectRoot
    }
    
    # テスト用データベースの作成
    $testDatabasePath = $null
    if ($CreateTempDatabase) {
        $testDatabasePath = New-TestDatabase -ProjectRoot $ProjectRoot
    }
    
    # 設定の初期化
    try {
        if (Test-Path $TestConfigPath) {
            Get-DataSyncConfig -ConfigPath $TestConfigPath | Out-Null
            Write-Host "✓ テスト設定を読み込みました: $TestConfigPath" -ForegroundColor Green
        }
        else {
            Write-Warning "テスト設定ファイルが見つかりません。デフォルト設定を使用します: $TestConfigPath"
        }
    }
    catch {
        Write-Warning "設定の読み込みに失敗しました。デフォルト設定を使用します: $($_.Exception.Message)"
    }
    
    return @{
        ProjectRoot      = $ProjectRoot
        TestConfigPath   = $TestConfigPath
        TestDatabasePath = $testDatabasePath
    }
}

# テスト環境のクリーンアップ
function Clear-TestEnvironment {
    
    try {
        # プロジェクトルートを取得
        $ProjectRoot = Find-ProjectRoot

        # 一時ファイルのクリーンアップ
        $tempPath = [System.IO.Path]::GetTempPath()
        $testFiles = Get-ChildItem -Path $tempPath -Filter "*test*.db" -ErrorAction SilentlyContinue
        foreach ($file in $testFiles) {
            try {
                Remove-Item $file.FullName -Force -ErrorAction SilentlyContinue
                Write-Verbose "テスト用一時ファイルを削除: $($file.FullName)"
            }
            catch {
                Write-Warning "一時ファイルの削除に失敗: $($file.FullName)"
            }
        }
        
        # テスト用データディレクトリのクリーンアップ
        $testDataPath = Join-Path $ProjectRoot "test-data" "temp"
        if (Test-Path $testDataPath) {
            Remove-Item $testDataPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Verbose "テスト用データディレクトリを削除: $testDataPath"
        }
        
        # 設定キャッシュのリセット
        if (Get-Command "Reset-DataSyncConfig" -ErrorAction SilentlyContinue) {
            Reset-DataSyncConfig
        }
        
        # 環境変数のクリーンアップ
        Remove-Item Env:PESTER_TEST -ErrorAction SilentlyContinue
        
        Write-Host "✓ テスト環境をクリーンアップしました" -ForegroundColor Green
    }
    catch {
        Write-Warning "テスト環境のクリーンアップ中にエラーが発生しました: $($_.Exception.Message)"
    }
}

# テスト用データベースの作成
function New-TestDatabase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )
    
    $tempDir = [System.IO.Path]::GetTempPath()
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $testDbName = "test_data_sync_$timestamp.db"
    $testDbPath = Join-Path $tempDir $testDbName
    
    try {
        # 既存ファイルがある場合は削除
        if (Test-Path $testDbPath) {
            Remove-Item $testDbPath -Force
        }
        
        # 空のデータベースファイルを作成
        $null = New-Item -Path $testDbPath -ItemType File -Force
        
        Write-Host "✓ テスト用データベースを作成しました: $testDbPath" -ForegroundColor Green
        return $testDbPath
    }
    catch {
        Write-Error "テスト用データベースの作成に失敗しました: $($_.Exception.Message)"
        throw
    }
}

Export-ModuleMember -Function @(
    'Import-LayeredModules',
    'Initialize-TestEnvironment',
    'Clear-TestEnvironment',
    'New-TestDatabase'
)