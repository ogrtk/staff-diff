# PowerShell & SQLite データ同期システム
# 設定管理ライブラリ

# クロスプラットフォーム対応エンコーディング取得（内部関数）
function Get-CrossPlatformEncoding {
    if ($PSVersionTable.PSVersion.Major -ge 6) {
        return [System.Text.Encoding]::UTF8
    }
    else {
        return [System.Text.UTF8Encoding]::new($true)
    }
}

# グローバル変数
$Global:DataSyncConfig = $null

# データ同期設定の読み込み
function Get-DataSyncConfig {
    param(
        [string]$ConfigPath = (Join-Path $PSScriptRoot "..\..\config\data-sync-config.json")
    )
    
    if ($null -eq $Global:DataSyncConfig) {
        try {
            if (-not (Test-Path $ConfigPath)) {
                throw "設定ファイルが見つかりません: $ConfigPath"
            }
            
            $encoding = Get-CrossPlatformEncoding
            $configContent = Get-Content -Path $ConfigPath -Raw -Encoding $encoding
            $Global:DataSyncConfig = $configContent | ConvertFrom-Json
            
            Write-Host "データ同期設定を読み込みました: $ConfigPath" -ForegroundColor Green
            
        }
        catch {
            Write-Error "データ同期設定の読み込みに失敗しました: $($_.Exception.Message)"
            throw
        }
    }
    
    return $Global:DataSyncConfig
}

# ファイルパス設定の取得
function Get-FilePathConfig {
    $config = Get-DataSyncConfig
    return $config.file_paths
}

# 同期ルール設定の取得
function Get-SyncRulesConfig {
    $config = Get-DataSyncConfig
    return $config.sync_rules
}

# 設定の検証
function Test-DataSyncConfig {
    try {
        $config = Get-DataSyncConfig
        
        Write-Host "設定検証を実行中..." -ForegroundColor Cyan
        
        # 基本構造の検証
        if (-not $config.tables) {
            throw "テーブル定義が見つかりません"
        }
        
        # 各テーブルの検証
        foreach ($tableName in $config.tables.PSObject.Properties.Name) {
            $table = $config.tables.$tableName
            
            if (-not $table.columns -or $table.columns.Count -eq 0) {
                throw "テーブル '$tableName' のカラム定義が不正です"
            }
            
            # 必須カラムの存在確認
            $idColumn = $table.columns | Where-Object { $_.name -eq "id" }
            if (-not $idColumn) {
                Write-Warning "テーブル '$tableName' にidカラムがありません"
            }
        }
        
        # 同期ルールの基本検証
        if ($config.sync_rules) {
            if (-not $config.sync_rules.column_mappings -or -not $config.sync_rules.column_mappings.mappings) {
                Write-Warning "column_mappings が設定されていません"
            }
        }
        
        Write-Host "設定検証が完了しました: 問題なし" -ForegroundColor Green
        return $true
        
    }
    catch {
        Write-Error "設定検証に失敗しました: $($_.Exception.Message)"
        return $false
    }
}

# ログ設定の取得
function Get-LoggingConfig {
    $config = Get-DataSyncConfig
    
    if (-not $config.logging) {
        # デフォルト設定を返す
        return @{
            enabled          = $false
            log_directory    = "./logs/"
            log_file_name    = "staff-management.log"
            max_file_size_mb = 10
            max_files        = 5
            levels           = @("Info", "Warning", "Error", "Success")
        }
    }
    
    return $config.logging
}

# データフィルタ設定の取得
function Get-DataFilterConfig {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TableName
    )
    
    $config = Get-DataSyncConfig
    
    if (-not $config.data_filters -or -not $config.data_filters.$TableName) {
        return $null
    }
    
    return $config.data_filters.$TableName
}