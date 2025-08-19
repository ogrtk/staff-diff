# PowerShell & SQLite データ同期システム
# 統合テスト環境ヘルパーモジュール

using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"

# 共通パス管理
function Get-TestDataPath {
    param(
        [string]$SubPath = "",
        [switch]$Temp
    )
    
    $ProjectRoot = Find-ProjectRoot
    $basePath = if ($Temp) {
        Join-Path $ProjectRoot "test-data" "temp"
    } else {
        Join-Path $ProjectRoot "test-data"
    }
    
    if (-not [string]::IsNullOrEmpty($SubPath)) {
        return Join-Path $basePath $SubPath
    }
    
    return $basePath
}

# 統一一時ファイル作成
function New-TestTempPath {
    param(
        [string]$Extension = ".txt",
        [string]$Prefix = "test_",
        [switch]$UseSystemTemp
    )
    
    $tempDir = if ($UseSystemTemp) {
        [System.IO.Path]::GetTempPath()
    } else {
        Get-TestDataPath -Temp
    }
    
    # ディレクトリの作成
    if (-not (Test-Path $tempDir)) {
        New-Item -Path $tempDir -ItemType Directory -Force | Out-Null
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $randomId = Get-Random -Minimum 1000 -Maximum 9999
    $fileName = "$Prefix$timestamp$randomId$Extension"
    
    return Join-Path $tempDir $fileName
}

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
    param(
        [string]$ProjectRoot = ""
    )
    
    try {
        # プロジェクトルートを取得
        if ([string]::IsNullOrEmpty($ProjectRoot)) {
            $ProjectRoot = Find-ProjectRoot
        }

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
        $testDataPath = Get-TestDataPath -Temp
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
        [string]$ProjectRoot = ""
    )
    
    if ([string]::IsNullOrEmpty($ProjectRoot)) {
        $ProjectRoot = Find-ProjectRoot
    }
    
    $testDbPath = New-TestTempPath -Extension ".db" -Prefix "test_data_sync_" -UseSystemTemp
    
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

# テスト用CSVデータの生成
function New-TestCsvData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataType,  # "provided_data", "current_data", "mixed"
        
        [int]$RecordCount = 10,
        
        [string]$OutputPath = "",
        
        [switch]$IncludeHeader,
        
        [string[]]$ExcludeIds = @(),
        
        [switch]$IncludeJapanese
    )
    
    $data = @()
    
    switch ($DataType.ToLower()) {
        "provided_data" {
            $data = New-ProvidedDataRecords -Count $RecordCount -ExcludeIds $ExcludeIds -IncludeJapanese:$IncludeJapanese
        }
        "current_data" {
            $data = New-CurrentDataRecords -Count $RecordCount -ExcludeIds $ExcludeIds -IncludeJapanese:$IncludeJapanese
        }
        "mixed" {
            $providedCount = [Math]::Ceiling($RecordCount / 2)
            $currentCount = $RecordCount - $providedCount
            $data += New-ProvidedDataRecords -Count $providedCount -ExcludeIds $ExcludeIds -IncludeJapanese:$IncludeJapanese
            $data += New-CurrentDataRecords -Count $currentCount -ExcludeIds $ExcludeIds -IncludeJapanese:$IncludeJapanese
        }
        default {
            throw "無効なDataType: $DataType. 有効な値: provided_data, current_data, mixed"
        }
    }
    
    if (-not [string]::IsNullOrEmpty($OutputPath)) {
        # ディレクトリの作成
        $directory = Split-Path $OutputPath -Parent
        if (-not [string]::IsNullOrEmpty($directory) -and -not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        # CSVファイルとして出力
        if ($IncludeHeader) {
            $data | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8
        }
        else {
            # ヘッダーなしで出力
            $data | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $OutputPath -Encoding UTF8
        }
        
        Write-Verbose "テストCSVデータを生成しました: $OutputPath ($RecordCount 件)"
    }
    
    return $data
}

# 提供データレコードの生成
function New-ProvidedDataRecords {
    param(
        [int]$Count = 10,
        [string[]]$ExcludeIds = @(),
        [switch]$IncludeJapanese
    )
    
    $records = @()
    $usedIds = @()
    
    # 日本語名前のサンプル
    $japaneseNames = @(
        "田中太郎", "佐藤花子", "鈴木一郎", "高橋美咲", "渡辺健太",
        "伊藤由美", "山田悟", "中村理恵", "小林大輔", "加藤真由美"
    )
    
    # 英語名前のサンプル
    $englishNames = @(
        "John Smith", "Mary Johnson", "Robert Brown", "Patricia Davis", "Michael Wilson",
        "Linda Moore", "William Taylor", "Elizabeth Anderson", "David Thomas", "Jennifer Jackson"
    )
    
    $departments = @("営業部", "開発部", "総務部", "人事部", "経理部", "企画部")
    $positions = @("部長", "課長", "主任", "係長", "一般", "マネージャー")
    
    for ($i = 1; $i -le $Count; $i++) {
        do {
            $employeeId = "E{0:D4}" -f (Get-Random -Minimum 1000 -Maximum 9999)
        } while ($employeeId -in $usedIds -or $employeeId -in $ExcludeIds)
        
        $usedIds += $employeeId
        
        # 名前の選択
        if ($IncludeJapanese) {
            $name = $japaneseNames | Get-Random
        }
        else {
            $name = $englishNames | Get-Random
        }
        
        $record = [PSCustomObject]@{
            employee_id = $employeeId
            card_number = "C{0:D6}" -f (Get-Random -Minimum 100000 -Maximum 999999)
            name = $name
            department = $departments | Get-Random
            position = $positions | Get-Random
            email = "$($name.Replace(' ', '.').ToLower())@company.com"
            phone = "0{0}-{1}-{2}" -f (Get-Random -Minimum 10 -Maximum 99), (Get-Random -Minimum 1000 -Maximum 9999), (Get-Random -Minimum 1000 -Maximum 9999)
            hire_date = (Get-Date).AddDays(-(Get-Random -Minimum 30 -Maximum 3650)).ToString("yyyy-MM-dd")
        }
        
        $records += $record
    }
    
    return $records
}

# 現在データレコードの生成
function New-CurrentDataRecords {
    param(
        [int]$Count = 10,
        [string[]]$ExcludeIds = @(),
        [switch]$IncludeJapanese
    )
    
    $records = @()
    $usedIds = @()
    
    # 日本語名前のサンプル
    $japaneseNames = @(
        "池田次郎", "松本愛子", "青木正夫", "福田美穂", "岡田和也",
        "石川恵子", "上田龍也", "森本彩香", "原田誠", "村田優子"
    )
    
    # 英語名前のサンプル
    $englishNames = @(
        "Christopher Lee", "Sarah White", "Daniel Harris", "Michelle Martin", "Anthony Thompson",
        "Deborah Garcia", "Mark Martinez", "Lisa Robinson", "Paul Clark", "Nancy Lewis"
    )
    
    $departments = @("製造部", "品質管理部", "研究開発部", "マーケティング部", "法務部", "IT部")
    $positions = @("主査", "主事", "主任", "リーダー", "エキスパート", "スペシャリスト")
    
    for ($i = 1; $i -le $Count; $i++) {
        do {
            $userId = "U{0:D4}" -f (Get-Random -Minimum 2000 -Maximum 9999)
        } while ($userId -in $usedIds -or $userId -in $ExcludeIds)
        
        $usedIds += $userId
        
        # 名前の選択
        if ($IncludeJapanese) {
            $name = $japaneseNames | Get-Random
        }
        else {
            $name = $englishNames | Get-Random
        }
        
        $record = [PSCustomObject]@{
            user_id = $userId
            card_number = "C{0:D6}" -f (Get-Random -Minimum 200000 -Maximum 899999)
            name = $name
            department = $departments | Get-Random
            position = $positions | Get-Random
            email = "$($name.Replace(' ', '.').ToLower())@company.com"
            phone = "0{0}-{1}-{2}" -f (Get-Random -Minimum 10 -Maximum 99), (Get-Random -Minimum 1000 -Maximum 9999), (Get-Random -Minimum 1000 -Maximum 9999)
            hire_date = (Get-Date).AddDays(-(Get-Random -Minimum 60 -Maximum 3000)).ToString("yyyy-MM-dd")
        }
        
        $records += $record
    }
    
    return $records
}

# 同期結果データの生成
function New-SyncResultRecords {
    param(
        [int]$AddCount = 3,
        [int]$UpdateCount = 2,
        [int]$DeleteCount = 1,
        [int]$KeepCount = 4,
        [switch]$IncludeJapanese
    )
    
    $records = @()
    $actionValues = @{
        "ADD" = "1"
        "UPDATE" = "2"  
        "DELETE" = "3"
        "KEEP" = "9"
    }
    
    # 追加レコード
    for ($i = 1; $i -le $AddCount; $i++) {
        $records += New-SyncResultRecord -Action "ADD" -ActionValue $actionValues.ADD -Index $i -IncludeJapanese:$IncludeJapanese
    }
    
    # 更新レコード
    for ($i = 1; $i -le $UpdateCount; $i++) {
        $records += New-SyncResultRecord -Action "UPDATE" -ActionValue $actionValues.UPDATE -Index ($AddCount + $i) -IncludeJapanese:$IncludeJapanese
    }
    
    # 削除レコード
    for ($i = 1; $i -le $DeleteCount; $i++) {
        $records += New-SyncResultRecord -Action "DELETE" -ActionValue $actionValues.DELETE -Index ($AddCount + $UpdateCount + $i) -IncludeJapanese:$IncludeJapanese
    }
    
    # 保持レコード
    for ($i = 1; $i -le $KeepCount; $i++) {
        $records += New-SyncResultRecord -Action "KEEP" -ActionValue $actionValues.KEEP -Index ($AddCount + $UpdateCount + $DeleteCount + $i) -IncludeJapanese:$IncludeJapanese
    }
    
    return $records
}

# 単一同期結果レコードの生成
function New-SyncResultRecord {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Action,
        
        [Parameter(Mandatory = $true)]
        [string]$ActionValue,
        
        [int]$Index = 1,
        
        [switch]$IncludeJapanese
    )
    
    $names = if ($IncludeJapanese) {
        @("山田太郎", "佐藤花子", "田中一郎", "鈴木美咲", "高橋健太")
    } else {
        @("John Doe", "Jane Smith", "Mike Johnson", "Lisa Brown", "Tom Wilson")
    }
    
    $departments = @("営業部", "開発部", "総務部", "人事部", "経理部")
    $positions = @("部長", "課長", "主任", "一般", "マネージャー")
    
    return [PSCustomObject]@{
        syokuin_no = "S{0:D4}" -f ($Index + 1000)
        card_number = "C{0:D6}" -f ($Index + 100000)
        name = $names[($Index - 1) % $names.Length]
        position = $positions[($Index - 1) % $positions.Length]
        email = "user$Index@company.com"
        phone = "999-9999-9999"  # 固定値（設定による）
        hire_date = (Get-Date).AddDays(-($Index * 30)).ToString("yyyy-MM-dd")
        sync_action = $ActionValue
    }
}

# テスト用設定ファイルの生成
function New-TestConfig {
    param(
        [string]$OutputPath = "",
        [hashtable]$CustomSettings = @{}
    )
    
    # デフォルト設定
    $defaultConfig = @{
        version = "1.0.0"
        description = "テスト用設定ファイル"
        file_paths = @{
            provided_data_file_path = (Get-TestDataPath -SubPath "test-provided.csv")
            current_data_file_path = (Get-TestDataPath -SubPath "test-current.csv")
            output_file_path = (Get-TestDataPath -SubPath "test-output.csv")
            provided_data_history_directory = (Get-TestDataPath -SubPath "temp/provided-data/" -Temp)
            current_data_history_directory = (Get-TestDataPath -SubPath "temp/current-data/" -Temp)
            output_history_directory = (Get-TestDataPath -SubPath "temp/output/" -Temp)
            timezone = "Asia/Tokyo"
        }
        csv_format = @{
            provided_data = @{
                encoding = "UTF-8"
                delimiter = ","
                newline = "LF"
                has_header = $false
                null_values = @("", "NULL", "null")
                allow_empty_file = $true  # テスト環境では空ファイルを許可
            }
            current_data = @{
                encoding = "UTF-8"
                delimiter = ","
                newline = "LF"
                has_header = $true
                null_values = @("", "NULL", "null")
                allow_empty_file = $true
            }
            output = @{
                encoding = "UTF-8"
                delimiter = ","
                newline = "CRLF"
                include_header = $true
            }
        }
        tables = @{
            provided_data = @{
                description = "提供データテーブル"
                table_constraints = @(
                    @{
                        name = "uk_provided_employee_id"
                        type = "UNIQUE"
                        columns = @("employee_id")
                        description = "職員IDの一意制約（明示的定義）"
                    }
                )
                columns = @(
                    @{ name = "id"; type = "INTEGER"; constraints = "PRIMARY KEY AUTOINCREMENT"; csv_include = $false; description = "内部ID" }
                    @{ name = "employee_id"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "職員ID" }
                    @{ name = "card_number"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "カード番号" }
                    @{ name = "name"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "氏名" }
                    @{ name = "department"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "部署" }
                    @{ name = "position"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "役職" }
                    @{ name = "email"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "メールアドレス" }
                    @{ name = "phone"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "電話番号" }
                    @{ name = "hire_date"; type = "DATE"; constraints = ""; csv_include = $true; required = $false; description = "入社日" }
                )
                indexes = @(
                    @{
                        name = "idx_provided_employee_id"
                        columns = @("employee_id")
                        description = "職員ID検索用インデックス（大量データ時の比較処理高速化）"
                    }
                )
            }
            current_data = @{
                description = "現在データテーブル"
                table_constraints = @(
                    @{
                        name = "uk_current_user_id"
                        type = "UNIQUE"
                        columns = @("user_id")
                        description = "利用者IDの一意制約（明示的定義）"
                    }
                )
                columns = @(
                    @{ name = "id"; type = "INTEGER"; constraints = "PRIMARY KEY AUTOINCREMENT"; csv_include = $false; description = "内部ID" }
                    @{ name = "user_id"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "利用者ID" }
                    @{ name = "card_number"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "カード番号" }
                    @{ name = "name"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "氏名" }
                    @{ name = "department"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "部署" }
                    @{ name = "position"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "役職" }
                    @{ name = "email"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "メールアドレス" }
                    @{ name = "phone"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "電話番号" }
                    @{ name = "hire_date"; type = "DATE"; constraints = ""; csv_include = $true; required = $false; description = "入社日" }
                )
                indexes = @(
                    @{
                        name = "idx_current_user_id"
                        columns = @("user_id")
                        description = "利用者ID検索用インデックス（大量データ時の比較処理高速化）"
                    }
                )
            }
            sync_result = @{
                description = "同期結果テーブル"
                table_constraints = @(
                    @{
                        name = "uk_sync_result_syokuin_no"
                        type = "UNIQUE"
                        columns = @("syokuin_no")
                        description = "職員番号の一意制約（重複レコード防止）"
                    }
                )
                columns = @(
                    @{ name = "id"; type = "INTEGER"; constraints = "PRIMARY KEY AUTOINCREMENT"; csv_include = $false; description = "内部ID" }
                    @{ name = "syokuin_no"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "職員ID" }
                    @{ name = "card_number"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "カード番号" }
                    @{ name = "name"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "氏名" }
                    @{ name = "department"; type = "TEXT"; constraints = ""; csv_include = $false; required = $false; description = "部署" }
                    @{ name = "position"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "役職" }
                    @{ name = "email"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "メールアドレス" }
                    @{ name = "phone"; type = "TEXT"; constraints = ""; csv_include = $true; required = $false; description = "電話番号" }
                    @{ name = "hire_date"; type = "DATE"; constraints = ""; csv_include = $true; required = $false; description = "入社日" }
                    @{ name = "sync_action"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "同期アクション (ADD, UPDATE, DELETE, KEEP)" }
                )
                indexes = @()
            }
        }
        sync_rules = @{
            key_columns = @{
                provided_data = @("employee_id")
                current_data = @("user_id")
                sync_result = @("syokuin_no")
            }
            column_mappings = @{
                description = "テーブル間の比較項目対応付け（provided_dataの項目:current_dataの項目）"
                mappings = @{
                    employee_id = "user_id"
                    card_number = "card_number"
                    name = "name"
                    department = "department"
                    position = "position"
                    email = "email"
                    phone = "phone"
                    hire_date = "hire_date"
                }
            }
            sync_result_mapping = @{
                description = "sync_resultテーブルへの格納項目対応付け（テスト用完全版）"
                mappings = @{
                    syokuin_no = @{
                        description = "職員番号"
                        sources = @(
                            @{
                                type = "provided_data"
                                field = "employee_id"
                                priority = 1
                                description = "提供データの職員ID（最優先）"
                            }
                            @{
                                type = "current_data"
                                field = "user_id"
                                priority = 2
                                description = "現在データの利用者ID（フォールバック）"
                            }
                        )
                    }
                    card_number = @{
                        description = "カード番号"
                        sources = @(
                            @{
                                type = "provided_data"
                                field = "card_number"
                                priority = 1
                                description = "提供データのカード番号（最優先）"
                            }
                            @{
                                type = "current_data"
                                field = "card_number"
                                priority = 2
                                description = "現在データのカード番号（フォールバック）"
                            }
                        )
                    }
                    name = @{
                        description = "氏名"
                        sources = @(
                            @{
                                type = "provided_data"
                                field = "name"
                                priority = 1
                                description = "提供データの氏名（最優先）"
                            }
                            @{
                                type = "current_data"
                                field = "name"
                                priority = 2
                                description = "現在データの氏名（フォールバック）"
                            }
                        )
                    }
                    department = @{
                        description = "部署"
                        sources = @(
                            @{
                                type = "provided_data"
                                field = "department"
                                priority = 1
                                description = "提供データの部署（最優先）"
                            }
                            @{
                                type = "current_data"
                                field = "department"
                                priority = 2
                                description = "現在データの部署（フォールバック）"
                            }
                            @{
                                type = "fixed_value"
                                value = "未設定"
                                priority = 3
                                description = "デフォルト部署名（最終フォールバック）"
                            }
                        )
                    }
                    position = @{
                        description = "役職"
                        sources = @(
                            @{
                                type = "provided_data"
                                field = "position"
                                priority = 1
                                description = "提供データの役職（最優先）"
                            }
                            @{
                                type = "current_data"
                                field = "position"
                                priority = 2
                                description = "現在データの役職（フォールバック）"
                            }
                        )
                    }
                    email = @{
                        description = "メールアドレス"
                        sources = @(
                            @{
                                type = "provided_data"
                                field = "email"
                                priority = 1
                                description = "提供データのメールアドレス（最優先）"
                            }
                            @{
                                type = "current_data"
                                field = "email"
                                priority = 2
                                description = "現在データのメールアドレス（フォールバック）"
                            }
                        )
                    }
                    phone = @{
                        description = "電話番号"
                        sources = @(
                            @{
                                type = "fixed_value"
                                value = "999-9999-9999"
                                priority = 1
                                description = "固定値"
                            }
                        )
                    }
                    hire_date = @{
                        description = "入社日"
                        sources = @(
                            @{
                                type = "provided_data"
                                field = "hire_date"
                                priority = 1
                                description = "提供データの入社日（最優先）"
                            }
                            @{
                                type = "current_data"
                                field = "hire_date"
                                priority = 2
                                description = "現在データの入社日（フォールバック）"
                            }
                        )
                    }
                }
            }
            sync_action_labels = @{
                mappings = @{
                    ADD = @{ value = "1"; description = "新規追加" }
                    UPDATE = @{ value = "2"; description = "更新" }
                    DELETE = @{ value = "3"; description = "削除" }
                    KEEP = @{ value = "9"; description = "変更なし" }
                }
            }
        }
        data_filters = @{
            provided_data = @{
                enabled = $false
                rules = @()
            }
            current_data = @{
                enabled = $false
                rules = @()
                output_excluded_as_keep = @{
                    enabled = $false
                }
            }
        }
        logging = @{
            enabled = $true
            log_directory = (Get-TestDataPath -SubPath "temp/logs/" -Temp)
            log_file_name = "test-system.log"
            max_file_size_mb = 5
            max_files = 3
            levels = @("Info", "Warning", "Error", "Success")
        }
        performance_settings = @{
            description = "性能最適化設定"
            index_threshold = 100000
            batch_size = 1000
            auto_optimization = $true
            sqlite_pragmas = @{
                journal_mode = "WAL"
                synchronous = "NORMAL"
                temp_store = "MEMORY"
                cache_size = 10000
            }
        }
        error_handling = @{
            enabled = $true
            log_stack_trace = $true
            retry_settings = @{
                enabled = $false
                max_attempts = 1
                delay_seconds = @(1)
                retryable_categories = @()
            }
            error_levels = @{
                description = "エラーカテゴリ別のログレベル設定"
                System = "Error"
                Data = "Warning"
                External = "Error"
            }
            continue_on_error = @{
                System = $false
                Data = $true
                External = $false
            }
            cleanup_on_error = $true
        }
    }
    
    # カスタム設定のマージ
    $mergedConfig = Merge-Hashtables -Target $defaultConfig -Source $CustomSettings
    
    # ファイル出力
    if (-not [string]::IsNullOrEmpty($OutputPath)) {
        $directory = Split-Path $OutputPath -Parent
        if (-not [string]::IsNullOrEmpty($directory) -and -not (Test-Path $directory)) {
            New-Item -Path $directory -ItemType Directory -Force | Out-Null
        }
        
        $mergedConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Verbose "テスト設定ファイルを生成しました: $OutputPath"
    }
    
    return $mergedConfig
}

# ハッシュテーブルの深いマージ
function Merge-Hashtables {
    param(
        [hashtable]$Target,
        [hashtable]$Source
    )
    
    $result = $Target.Clone()
    
    foreach ($key in $Source.Keys) {
        if ($result.ContainsKey($key)) {
            if ($result[$key] -is [hashtable] -and $Source[$key] -is [hashtable]) {
                $result[$key] = Merge-Hashtables -Target $result[$key] -Source $Source[$key]
            }
            else {
                $result[$key] = $Source[$key]
            }
        }
        else {
            $result[$key] = $Source[$key]
        }
    }
    
    return $result
}

# 一時テストファイルの作成
function New-TempTestFile {
    param(
        [string]$Content = "",
        [string]$Extension = ".txt",
        [string]$Prefix = "test_"
    )
    
    $filePath = New-TestTempPath -Extension $Extension -Prefix $Prefix
    
    if (-not [string]::IsNullOrEmpty($Content)) {
        $Content | Out-File -FilePath $filePath -Encoding UTF8
    }
    else {
        New-Item -Path $filePath -ItemType File -Force | Out-Null
    }
    
    return $filePath
}

Export-ModuleMember -Function @(
    'Get-TestDataPath',
    'New-TestTempPath',
    'Initialize-TestEnvironment',
    'Clear-TestEnvironment',
    'New-TestDatabase',
    'New-TestCsvData',
    'New-ProvidedDataRecords',
    'New-CurrentDataRecords',
    'New-SyncResultRecords',
    'New-TestConfig',
    'New-TempTestFile'
)