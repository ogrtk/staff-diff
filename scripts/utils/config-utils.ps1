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
        
        # CSVフォーマット設定の検証
        if ($config.csv_format) {
            Test-CsvFormatConfig -CsvFormatConfig $config.csv_format
        }
        
        Write-Host "設定検証が完了しました: 問題なし" -ForegroundColor Green
        return $true
        
    }
    catch {
        Write-Error "設定検証に失敗しました: $($_.Exception.Message)"
        return $false
    }
}

# CSVフォーマット設定の検証
function Test-CsvFormatConfig {
    param(
        [Parameter(Mandatory = $true)]
        $CsvFormatConfig
    )
    
    $validEncodings = @("UTF-8", "UTF-16", "UTF-16BE", "UTF-32", "SHIFT_JIS", "EUC-JP", "ASCII", "ISO-8859-1")
    $validNewlines = @("CRLF", "LF", "CR")
    
    foreach ($configType in @("provided_data", "current_data", "output")) {
        if ($CsvFormatConfig.$configType) {
            $config = $CsvFormatConfig.$configType
            
            # エンコーディング検証
            if ($config.encoding -and $config.encoding -notin $validEncodings) {
                Write-Warning "無効なエンコーディングが指定されています ($configType): $($config.encoding)"
            }
            
            # 改行コード検証
            if ($config.newline -and $config.newline -notin $validNewlines) {
                Write-Warning "無効な改行コードが指定されています ($configType): $($config.newline)"
            }
            
            # 区切り文字の長さチェック
            if ($config.delimiter -and $config.delimiter.Length -gt 1) {
                Write-Warning "区切り文字は1文字である必要があります ($configType): '$($config.delimiter)'"
            }
            
            # 実装されていない設定項目の警告
            if ($config.PSObject.Properties.Name -contains "quote_char") {
                Write-Warning "[$configType] 'quote_char' 設定は PowerShell の Import-Csv/Export-Csv では使用できません。設定から削除することを推奨します。"
            }
            
            if ($config.PSObject.Properties.Name -contains "escape_char") {
                Write-Warning "[$configType] 'escape_char' 設定は PowerShell の Import-Csv/Export-Csv では使用できません。設定から削除することを推奨します。"
            }
            
            if ($config.PSObject.Properties.Name -contains "quote_all") {
                Write-Warning "[$configType] 'quote_all' 設定は PowerShell の Export-Csv では使用できません。設定から削除することを推奨します。"
            }
            
            # ヘッダー設定の検証
            if ($configType -in @("provided_data", "current_data")) {
                if (-not ($config.PSObject.Properties.Name -contains "has_header")) {
                    Write-Warning "[$configType] 'has_header' 設定が見つかりません。デフォルトで true として処理されます。"
                }
            }
            
            if ($configType -eq "output") {
                if (-not ($config.PSObject.Properties.Name -contains "include_header")) {
                    Write-Warning "[$configType] 'include_header' 設定が見つかりません。デフォルトで true として処理されます。"
                }
            }
        }
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