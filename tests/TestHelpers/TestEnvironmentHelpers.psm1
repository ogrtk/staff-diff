# PowerShell & SQLite データ同期システム
# 統合テスト環境ヘルパーモジュール

using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"

# TestEnvironmentクラス - テスト用リソースの統合管理
class TestEnvironment {
    # プロパティ
    [string]$TempDirectory
    [string]$TestInstanceId
    [hashtable]$Config
    [string]$DatabasePath
    [string]$ConfigPath
    [System.Collections.Generic.List[string]]$CreatedFiles
    [System.Collections.Generic.List[string]]$CreatedDirectories
    [bool]$IsDisposed
    
    # コンストラクタ - テスト環境の初期化
    TestEnvironment([string]$TestName = "default") {
        $this.TestInstanceId = "${TestName}_$(Get-Date -Format 'yyyyMMdd_HHmmss')_$(Get-Random -Minimum 1000 -Maximum 9999)"
        $this.CreatedFiles = [System.Collections.Generic.List[string]]::new()
        $this.CreatedDirectories = [System.Collections.Generic.List[string]]::new()
        $this.IsDisposed = $false
        
        # 一時ディレクトリの作成
        $this.TempDirectory = $this.CreateTempDirectory()
        
        # 環境初期化
        $this.InitializeEnvironment()
        
        Write-Host "✓ テスト環境を初期化しました: $($this.TestInstanceId)" -ForegroundColor Green
    }
    
    # 一時ディレクトリの作成
    hidden [string] CreateTempDirectory() {
        $projectRoot = Find-ProjectRoot
        $baseTestDataPath = Join-Path $projectRoot "tests" "data"
        $instanceTempPath = Join-Path $baseTestDataPath $this.TestInstanceId
        
        try {
            # ディレクトリ作成
            if (-not (Test-Path $instanceTempPath)) {
                $null = New-Item -Path $instanceTempPath -ItemType Directory -Force
            }
            
            # 作成したディレクトリを記録
            $this.CreatedDirectories.Add($instanceTempPath)
            
            Write-Verbose "一時ディレクトリを作成しました: $instanceTempPath"
            return $instanceTempPath
        }
        catch {
            $errorMsg = "一時ディレクトリの作成に失敗しました: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw $errorMsg
        }
    }
    
    # 環境初期化
    hidden [void] InitializeEnvironment() {
        try {
            # サブディレクトリの作成
            $this.CreateSubDirectories()
            
            Write-Verbose "テスト環境の初期化が完了しました"
        }
        catch {
            $errorMsg = "テスト環境の初期化に失敗しました: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw $errorMsg
        }
    }
    
    # サブディレクトリの作成
    hidden [void] CreateSubDirectories() {
        $subDirs = @(
            "databases",
            "csv-data", 
            "config",
            "logs",
            "provided-data-history",
            "current-data-history",
            "output-history"
        )
        
        foreach ($subDir in $subDirs) {
            $fullPath = Join-Path $this.TempDirectory $subDir
            if (-not (Test-Path $fullPath)) {
                $null = New-Item -Path $fullPath -ItemType Directory -Force
                $this.CreatedDirectories.Add($fullPath)
                Write-Verbose "サブディレクトリを作成: $subDir"
            }
        }
    }
    
    # テスト用データベースの作成
    [string] CreateDatabase([string]$DatabaseName = "test_database") {
        $this.ValidateNotDisposed()
        
        $dbFileName = "${DatabaseName}.db"
        $dbPath = Join-Path $this.TempDirectory "databases" $dbFileName
        
        try {
            # 既存ファイルがある場合は削除
            if (Test-Path $dbPath) {
                Remove-Item $dbPath -Force
            }
            
            # 空のデータベースファイルを作成
            $null = New-Item -Path $dbPath -ItemType File -Force
            
            # 作成したファイルを記録
            $this.CreatedFiles.Add($dbPath)
            $this.DatabasePath = $dbPath
            
            Write-Host "✓ テスト用データベースを作成しました: $dbFileName" -ForegroundColor Green
            return $dbPath
        }
        catch {
            $errorMsg = "テスト用データベースの作成に失敗しました: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw $errorMsg
        }
    }
    
    # テスト用CSVファイルの作成
    [string] CreateCsvFile([string]$DataType, [int]$RecordCount = 10, [hashtable]$Options = @{}) {
        $this.ValidateNotDisposed()
        
        # デフォルトオプション
        $defaultOptions = @{
            IncludeHeader   = $true
            IncludeJapanese = $false
            ExcludeIds      = @()
            CustomFileName  = ""
        }
        
        # オプションのマージ
        foreach ($key in $Options.Keys) {
            $defaultOptions[$key] = $Options[$key]
        }
        
        # ファイル名の決定
        $fileName = if (-not [string]::IsNullOrEmpty($defaultOptions.CustomFileName)) {
            $defaultOptions.CustomFileName
        }
        else {
            "${DataType}_${RecordCount}records.csv"
        }
        
        $csvPath = Join-Path $this.TempDirectory "csv-data" $fileName
        
        try {
            # CSVデータの生成（既存の実装を再利用）
            $data = $this.GenerateTestData($DataType, $RecordCount, $defaultOptions)
            
            # CSVファイルとして出力
            if ($defaultOptions.IncludeHeader) {
                $data | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
            }
            else {
                # ヘッダーなしで出力
                $data | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $csvPath -Encoding UTF8
            }
            
            # 作成したファイルを記録
            $this.CreatedFiles.Add($csvPath)
            
            Write-Host "✓ テスト用CSVファイルを作成しました: $fileName ($RecordCount 件)" -ForegroundColor Green
            return $csvPath
        }
        catch {
            $errorMsg = "テスト用CSVファイルの作成に失敗しました: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw $errorMsg
        }
    }
    
    # テストデータの生成（既存の実装を統合）
    hidden [System.Collections.Generic.List[PSCustomObject]] GenerateTestData([string]$DataType, [int]$RecordCount, [hashtable]$Options) {
        $result = [System.Collections.Generic.List[PSCustomObject]]::new()
        
        switch ($DataType.ToLower()) {
            "provided_data" {
                $result = $this.GenerateProvidedDataRecords($RecordCount, $Options)
            }
            "current_data" {
                $result = $this.GenerateCurrentDataRecords($RecordCount, $Options)
            }
            "mixed" {
                $providedCount = [Math]::Ceiling($RecordCount / 2)
                $currentCount = $RecordCount - $providedCount
                $result.AddRange($this.GenerateProvidedDataRecords($providedCount, $Options))
                $result.AddRange($this.GenerateCurrentDataRecords($currentCount, $Options))
            }
            default {
                throw "無効なDataType: $DataType. 有効な値: provided_data, current_data, mixed"
            }
        }
        
        return $result
    }
    
    # 提供データレコードの生成
    hidden [System.Collections.Generic.List[PSCustomObject]] GenerateProvidedDataRecords([int]$Count, [hashtable]$Options) {
        $records = [System.Collections.Generic.List[PSCustomObject]]::new()
        $usedIds = [System.Collections.Generic.HashSet[string]]::new()
        
        # 名前サンプル
        $names = if ($Options.IncludeJapanese) {
            @("田中太郎", "佐藤花子", "鈴木一郎", "高橋美咲", "渡辺健太", "伊藤由美", "山田悟", "中村理恵", "小林大輔", "加藤真由美")
        }
        else {
            @("John Smith", "Mary Johnson", "Robert Brown", "Patricia Davis", "Michael Wilson", "Linda Moore", "William Taylor", "Elizabeth Anderson", "David Thomas", "Jennifer Jackson")
        }
        
        $departments = @("営業部", "開発部", "総務部", "人事部", "経理部", "企画部")
        $positions = @("部長", "課長", "主任", "係長", "一般", "マネージャー")
        
        for ($i = 1; $i -le $Count; $i++) {
            $employeeId = $null
            do {
                $employeeId = "E{0:D4}" -f (Get-Random -Minimum 1000 -Maximum 9999)
            } while ($usedIds.Contains($employeeId) -or $employeeId -in $Options.ExcludeIds)
            
            $null = $usedIds.Add($employeeId)
            
            $record = [PSCustomObject]@{
                employee_id = $employeeId
                card_number = "C{0:D6}" -f (Get-Random -Minimum 100000 -Maximum 999999)
                name        = $names | Get-Random
                department  = $departments | Get-Random
                position    = $positions | Get-Random
                email       = "user$(Get-Random -Max 9999)@company.com"
                phone       = "0{0}-{1}-{2}" -f (Get-Random -Minimum 10 -Maximum 99), (Get-Random -Minimum 1000 -Maximum 9999), (Get-Random -Minimum 1000 -Maximum 9999)
                hire_date   = (Get-Date).AddDays( - (Get-Random -Minimum 30 -Maximum 3650)).ToString("yyyy-MM-dd")
            }
            
            $records.Add($record)
        }
        
        return $records
    }
    
    # 現在データレコードの生成
    hidden [System.Collections.Generic.List[PSCustomObject]] GenerateCurrentDataRecords([int]$Count, [hashtable]$Options) {
        $records = [System.Collections.Generic.List[PSCustomObject]]::new()
        $usedIds = [System.Collections.Generic.HashSet[string]]::new()
        
        # 名前サンプル
        $names = if ($Options.IncludeJapanese) {
            @("池田次郎", "松本愛子", "青木正夫", "福田美穂", "岡田和也", "石川恵子", "上田龍也", "森本彩香", "原田誠", "村田優子")
        }
        else {
            @("Christopher Lee", "Sarah White", "Daniel Harris", "Michelle Martin", "Anthony Thompson", "Deborah Garcia", "Mark Martinez", "Lisa Robinson", "Paul Clark", "Nancy Lewis")
        }
        
        $departments = @("製造部", "品質管理部", "研究開発部", "マーケティング部", "法務部", "IT部")
        $positions = @("主査", "主事", "主任", "リーダー", "エキスパート", "スペシャリスト")
        
        for ($i = 1; $i -le $Count; $i++) {
            $userId = $null
            do {
                $userId = "U{0:D4}" -f (Get-Random -Minimum 2000 -Maximum 9999)
            } while ($usedIds.Contains($userId) -or $userId -in $Options.ExcludeIds)
            
            $null = $usedIds.Add($userId)
            
            $record = [PSCustomObject]@{
                user_id     = $userId
                card_number = "C{0:D6}" -f (Get-Random -Minimum 200000 -Maximum 899999)
                name        = $names | Get-Random
                department  = $departments | Get-Random
                position    = $positions | Get-Random
                email       = "user$(Get-Random -Max 9999)@company.com"
                phone       = "0{0}-{1}-{2}" -f (Get-Random -Minimum 10 -Maximum 99), (Get-Random -Minimum 1000 -Maximum 9999), (Get-Random -Minimum 1000 -Maximum 9999)
                hire_date   = (Get-Date).AddDays( - (Get-Random -Minimum 60 -Maximum 3000)).ToString("yyyy-MM-dd")
            }
            
            $records.Add($record)
        }
        
        return $records
    }
    
    # sync_resultテーブル用テストデータの生成
    [System.Collections.Generic.List[PSCustomObject]] CreateSyncResultData([hashtable]$ActionCounts = @{}, [hashtable]$Options = @{}) {
        $this.ValidateNotDisposed()
        
        # デフォルトのアクション件数
        $defaultCounts = @{
            ADD = 3
            UPDATE = 2  
            DELETE = 1
            KEEP = 4
        }
        
        # アクション件数のマージ
        foreach ($action in $defaultCounts.Keys) {
            if (-not $ActionCounts.ContainsKey($action)) {
                $ActionCounts[$action] = $defaultCounts[$action]
            }
        }
        
        # デフォルトオプション
        $defaultOptions = @{
            IncludeJapanese = $false
            StartId = 1000
        }
        
        # オプションのマージ
        foreach ($key in $Options.Keys) {
            $defaultOptions[$key] = $Options[$key]
        }
        
        $records = [System.Collections.Generic.List[PSCustomObject]]::new()
        $actionValues = @{
            ADD = "1"
            UPDATE = "2"  
            DELETE = "3"
            KEEP = "9"
        }
        
        $currentId = $defaultOptions.StartId
        
        # 各アクションのレコードを生成
        foreach ($action in @('ADD', 'UPDATE', 'DELETE', 'KEEP')) {
            $count = $ActionCounts[$action]
            if ($count -gt 0) {
                for ($i = 1; $i -le $count; $i++) {
                    $record = $this.GenerateSyncResultRecord($action, $actionValues[$action], $currentId, $defaultOptions)
                    $records.Add($record)
                    $currentId++
                }
            }
        }
        
        return $records
    }
    
    # 単一sync_resultレコードの生成
    hidden [PSCustomObject] GenerateSyncResultRecord([string]$Action, [string]$ActionValue, [int]$IdBase, [hashtable]$Options) {
        $names = if ($Options.IncludeJapanese) {
            @("山田太郎", "佐藤花子", "田中一郎", "鈴木美咲", "高橋健太", "伊藤由美", "渡辺悟", "中村理恵", "小林大輔", "加藤真由美")
        } else {
            @("John Doe", "Jane Smith", "Mike Johnson", "Lisa Brown", "Tom Wilson", "Sarah Davis", "Robert Miller", "Emily Jones", "David Garcia", "Jennifer Martin")
        }
        
        $departments = @("営業部", "開発部", "総務部", "人事部", "経理部", "企画部")
        $positions = @("部長", "課長", "主任", "一般", "マネージャー", "リーダー")
        
        return [PSCustomObject]@{
            syokuin_no = "S{0:D4}" -f $IdBase
            card_number = "C{0:D6}" -f ($IdBase + 100000)
            name = $names[($IdBase - 1000) % $names.Length]
            department = $departments[($IdBase - 1000) % $departments.Length]
            position = $positions[($IdBase - 1000) % $positions.Length]
            email = "user$IdBase@company.com"
            phone = "999-9999-9999"  # 固定値（設定による）
            hire_date = (Get-Date).AddDays(-($IdBase % 365)).ToString("yyyy-MM-dd")
            sync_action = $ActionValue
        }
    }
    
    # sync_resultテーブルの作成とデータ挿入
    [void] PopulateSyncResultTable([string]$DatabasePath, [hashtable]$ActionCounts = @{}, [hashtable]$Options = @{}) {
        $this.ValidateNotDisposed()
        
        try {
            # sync_resultテーブル用データ生成
            $syncData = $this.CreateSyncResultData($ActionCounts, $Options)
            
            # データベースにテーブル作成とデータ挿入
            # CoreUtilsのInvoke-SqliteCommand関数を使用
            $createTableSql = @"
CREATE TABLE IF NOT EXISTS sync_result (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    syokuin_no TEXT NOT NULL UNIQUE,
    card_number TEXT,
    name TEXT NOT NULL,
    department TEXT,
    position TEXT,
    email TEXT,
    phone TEXT,
    hire_date DATE,
    sync_action TEXT NOT NULL
);
"@
            
            Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $createTableSql
            
            # データ挿入
            foreach ($record in $syncData) {
                $insertSql = @"
INSERT OR REPLACE INTO sync_result 
(syokuin_no, card_number, name, department, position, email, phone, hire_date, sync_action)
VALUES ('$($record.syokuin_no)', '$($record.card_number)', '$($record.name)', '$($record.department)', '$($record.position)', '$($record.email)', '$($record.phone)', '$($record.hire_date)', '$($record.sync_action)');
"@
                
                Invoke-SqliteCommand -DatabasePath $DatabasePath -Query $insertSql
            }
            
            Write-Host "✓ sync_resultテーブルに $($syncData.Count) 件のテストデータを挿入しました" -ForegroundColor Green
        }
        catch {
            $errorMsg = "sync_resultテーブルの作成・データ挿入に失敗しました: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw $errorMsg
        }
    }
    
    # テスト用設定ファイルの作成
    [string] CreateConfigFile([hashtable]$CustomSettings = @{}, [string]$ConfigName = "test-config") {
        $this.ValidateNotDisposed()
        
        $configFileName = "${ConfigName}.json"
        $tmpConfigPath = Join-Path $this.TempDirectory "config" $configFileName
        
        try {
            # デフォルト設定の生成（既存実装を再利用）
            $defaultConfig = $this.GenerateDefaultTestConfig()
            
            # カスタム設定のマージ
            $mergedConfig = $this.MergeHashtables($defaultConfig, $CustomSettings)
            
            # パスの調整（一時ディレクトリベースに変更）
            $this.AdjustConfigPaths($mergedConfig)
            
            # JSONファイルとして出力
            $mergedConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $tmpConfigPath -Encoding UTF8
            
            # 作成したファイルを記録
            $this.CreatedFiles.Add($tmpConfigPath)
            $this.ConfigPath = $tmpConfigPath
            $this.Config = $mergedConfig
            
            Write-Host "✓ テスト用設定ファイルを作成しました: $configFileName" -ForegroundColor Green
            return $tmpConfigPath
        }
        catch {
            $errorMsg = "テスト用設定ファイルの作成に失敗しました: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw $errorMsg
        }
    }
    
    # デフォルトテスト設定の生成
    hidden [hashtable] GenerateDefaultTestConfig() {
        return @{
            version     = "1.0.0"
            description = "TestEnvironmentクラス用自動生成設定"
            file_paths  = @{
                provided_data_file_path         = Join-Path $this.TempDirectory "csv-data" "provided_data.csv"
                current_data_file_path          = Join-Path $this.TempDirectory "csv-data" "current_data.csv"
                output_file_path                = Join-Path $this.TempDirectory "csv-data" "output.csv"
                provided_data_history_directory = Join-Path $this.TempDirectory "provided-data-history"
                current_data_history_directory  = Join-Path $this.TempDirectory "current-data-history"
                output_history_directory        = Join-Path $this.TempDirectory "output-history"
                timezone                        = "Asia/Tokyo"
            }
            csv_format  = @{
                provided_data = @{
                    encoding         = "UTF-8"
                    delimiter        = ","
                    newline          = "LF"
                    has_header       = $false
                    null_values      = @("", "NULL", "null")
                    allow_empty_file = $true
                }
                current_data  = @{
                    encoding         = "UTF-8"
                    delimiter        = ","
                    newline          = "LF"
                    has_header       = $true
                    null_values      = @("", "NULL", "null")
                    allow_empty_file = $true
                }
                output        = @{
                    encoding       = "UTF-8"
                    delimiter      = ","
                    newline        = "CRLF"
                    include_header = $true
                }
            }
            tables      = @{
                provided_data = @{
                    description = "提供データテーブル"
                    table_constraints = @(
                        @{
                            name = "uk_provided_employee_id"
                            type = "UNIQUE"
                            columns = @("employee_id")
                            description = "職員IDの一意制約"
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
                            description = "職員ID検索用インデックス"
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
                            description = "利用者IDの一意制約"
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
                            description = "利用者ID検索用インデックス"
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
                            description = "職員番号の一意制約"
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
                        @{ name = "sync_action"; type = "TEXT"; constraints = "NOT NULL"; csv_include = $true; required = $true; description = "同期アクション" }
                    )
                    indexes = @()
                }
            }
            sync_rules  = @{
                key_columns = @{
                    provided_data = @("employee_id")
                    current_data  = @("user_id")
                    sync_result   = @("syokuin_no")
                }
                column_mappings = @{
                    description = "テーブル間の比較項目対応付け"
                    mappings    = @{
                        employee_id = "user_id"
                        card_number = "card_number"
                        name        = "name"
                        department  = "department"
                        position    = "position"
                        email       = "email"
                        phone       = "phone"
                        hire_date   = "hire_date"
                    }
                }
                sync_action_labels = @{
                    mappings = @{
                        ADD    = @{ value = "1"; enabled = $true; description = "新規追加" }
                        UPDATE = @{ value = "2"; enabled = $true; description = "更新" }
                        DELETE = @{ value = "3"; enabled = $true; description = "削除" }
                        KEEP   = @{ value = "9"; enabled = $true; description = "変更なし" }
                    }
                }
            }
            logging     = @{
                enabled          = $true
                log_directory    = Join-Path $this.TempDirectory "logs"
                log_file_name    = "test-system.log"
                max_file_size_mb = 5
                max_files        = 3
                levels           = @("Info", "Warning", "Error", "Success")
            }
        }
    }
    
    # 設定パスの調整
    hidden [void] AdjustConfigPaths([hashtable]$Config) {
        if ($Config.ContainsKey("file_paths")) {
            $Config.file_paths.provided_data_file_path = Join-Path $this.TempDirectory "csv-data" "provided_data.csv"
            $Config.file_paths.current_data_file_path = Join-Path $this.TempDirectory "csv-data" "current_data.csv"
            $Config.file_paths.output_file_path = Join-Path $this.TempDirectory "csv-data" "output.csv"
            $Config.file_paths.provided_data_history_directory = Join-Path $this.TempDirectory "provided-data-history"
            $Config.file_paths.current_data_history_directory = Join-Path $this.TempDirectory "current-data-history"
            $Config.file_paths.output_history_directory = Join-Path $this.TempDirectory "output-history"
        }
        
        if ($Config.ContainsKey("logging")) {
            $Config.logging.log_directory = Join-Path $this.TempDirectory "logs"
        }
    }
    
    # ハッシュテーブルのマージ（既存実装を再利用）
    hidden [hashtable] MergeHashtables([hashtable]$Target, [hashtable]$Source) {
        $result = $Target.Clone()
        
        foreach ($key in $Source.Keys) {
            if ($result.ContainsKey($key)) {
                if ($result[$key] -is [hashtable] -and $Source[$key] -is [hashtable]) {
                    $result[$key] = $this.MergeHashtables($result[$key], $Source[$key])
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
    
    # 一時ファイルの作成
    [string] CreateTempFile([string]$Content = "", [string]$Extension = ".txt", [string]$Prefix = "temp_") {
        $this.ValidateNotDisposed()
        
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $randomId = Get-Random -Minimum 1000 -Maximum 9999
        $fileName = "$Prefix$timestamp$randomId$Extension"
        $filePath = Join-Path $this.TempDirectory $fileName
        
        try {
            if (-not [string]::IsNullOrEmpty($Content)) {
                $Content | Out-File -FilePath $filePath -Encoding UTF8
            }
            else {
                $null = New-Item -Path $filePath -ItemType File -Force
            }
            
            $this.CreatedFiles.Add($filePath)
            return $filePath
        }
        catch {
            $errorMsg = "一時ファイルの作成に失敗しました: $($_.Exception.Message)"
            Write-Error $errorMsg
            throw $errorMsg
        }
    }
    
    # パス取得メソッド群
    [string] GetDatabasePath() { return $this.DatabasePath }
    [string] GetConfigPath() { return $this.ConfigPath }
    [string] GetTempDirectory() { return $this.TempDirectory }
    [string] GetTestInstanceId() { return $this.TestInstanceId }
    [hashtable] GetConfig() { return $this.Config }
    
    # バリデーション
    hidden [void] ValidateNotDisposed() {
        if ($this.IsDisposed) {
            throw "TestEnvironmentオブジェクトは既に破棄されています。"
        }
    }
    
    # リソースのクリーンアップ（Disposeパターン）
    [void] Dispose() {
        if ($this.IsDisposed) {
            return
        }
        
        try {
            Write-Verbose "TestEnvironment[$($this.TestInstanceId)]のクリーンアップを開始します..."
            
            # 作成したファイルを削除（逆順で安全に削除）
            for ($i = $this.CreatedFiles.Count - 1; $i -ge 0; $i--) {
                $filePath = $this.CreatedFiles[$i]
                if (Test-Path $filePath) {
                    try {
                        Remove-Item $filePath -Force -ErrorAction SilentlyContinue
                        Write-Verbose "ファイルを削除: $filePath"
                    }
                    catch {
                        Write-Warning "ファイルの削除に失敗: $filePath - $($_.Exception.Message)"
                    }
                }
            }
            
            # 作成したディレクトリを削除（逆順で安全に削除）
            for ($i = $this.CreatedDirectories.Count - 1; $i -ge 0; $i--) {
                $dirPath = $this.CreatedDirectories[$i]
                if (Test-Path $dirPath) {
                    try {
                        Remove-Item $dirPath -Recurse -Force -ErrorAction SilentlyContinue
                        Write-Verbose "ディレクトリを削除: $dirPath"
                    }
                    catch {
                        Write-Warning "ディレクトリの削除に失敗: $dirPath - $($_.Exception.Message)"
                    }
                }
            }
            
            # メインの一時ディレクトリを削除
            if ($this.TempDirectory -and (Test-Path $this.TempDirectory)) {
                try {
                    Remove-Item $this.TempDirectory -Recurse -Force
                    Write-Verbose "メイン一時ディレクトリを削除: $($this.TempDirectory)"
                }
                catch {
                    Write-Warning "メイン一時ディレクトリの削除に失敗: $($this.TempDirectory) - $($_.Exception.Message)"
                }
            }
            
            # プロパティをクリア
            $this.CreatedFiles.Clear()
            $this.CreatedDirectories.Clear()
            $this.Config = @{}
            
            $this.IsDisposed = $true
            Write-Host "✓ TestEnvironment[$($this.TestInstanceId)]のクリーンアップが完了しました" -ForegroundColor Green
        }
        catch {
            Write-Warning "TestEnvironmentのクリーンアップ中にエラーが発生しました: $($_.Exception.Message)"
        }
    }
    
    # オブジェクト破棄時の自動クリーンアップ（フィナライザーパターン）
    [void] Finalize() {
        $this.Dispose()
    }
}

# 共通パス管理
function Get-TestDataPath {
    param(
        [string]$SubPath = "",
        [switch]$Temp
    )
    
    $ProjectRoot = Find-ProjectRoot
    $basePath = if ($Temp) {
        Join-Path $ProjectRoot "test-data" "temp"
    }
    else {
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
    }
    else {
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
        [string]$DataType, # "provided_data", "current_data", "mixed"
        
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
            name        = $name
            department  = $departments | Get-Random
            position    = $positions | Get-Random
            email       = "$($name.Replace(' ', '.').ToLower())@company.com"
            phone       = "0{0}-{1}-{2}" -f (Get-Random -Minimum 10 -Maximum 99), (Get-Random -Minimum 1000 -Maximum 9999), (Get-Random -Minimum 1000 -Maximum 9999)
            hire_date   = (Get-Date).AddDays( - (Get-Random -Minimum 30 -Maximum 3650)).ToString("yyyy-MM-dd")
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
            user_id     = $userId
            card_number = "C{0:D6}" -f (Get-Random -Minimum 200000 -Maximum 899999)
            name        = $name
            department  = $departments | Get-Random
            position    = $positions | Get-Random
            email       = "$($name.Replace(' ', '.').ToLower())@company.com"
            phone       = "0{0}-{1}-{2}" -f (Get-Random -Minimum 10 -Maximum 99), (Get-Random -Minimum 1000 -Maximum 9999), (Get-Random -Minimum 1000 -Maximum 9999)
            hire_date   = (Get-Date).AddDays( - (Get-Random -Minimum 60 -Maximum 3000)).ToString("yyyy-MM-dd")
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
        "ADD"    = "1"
        "UPDATE" = "2"  
        "DELETE" = "3"
        "KEEP"   = "9"
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
    }
    else {
        @("John Doe", "Jane Smith", "Mike Johnson", "Lisa Brown", "Tom Wilson")
    }
    
    $positions = @("部長", "課長", "主任", "一般", "マネージャー")
    
    return [PSCustomObject]@{
        syokuin_no  = "S{0:D4}" -f ($Index + 1000)
        card_number = "C{0:D6}" -f ($Index + 100000)
        name        = $names[($Index - 1) % $names.Length]
        position    = $positions[($Index - 1) % $positions.Length]
        email       = "user$Index@company.com"
        phone       = "999-9999-9999"  # 固定値（設定による）
        hire_date   = (Get-Date).AddDays( - ($Index * 30)).ToString("yyyy-MM-dd")
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
        version              = "1.0.0"
        description          = "テスト用設定ファイル"
        file_paths           = @{
            provided_data_file_path         = (Get-TestDataPath -SubPath "test-provided.csv")
            current_data_file_path          = (Get-TestDataPath -SubPath "test-current.csv")
            output_file_path                = (Get-TestDataPath -SubPath "test-output.csv")
            provided_data_history_directory = (Get-TestDataPath -SubPath "temp/provided-data/" -Temp)
            current_data_history_directory  = (Get-TestDataPath -SubPath "temp/current-data/" -Temp)
            output_history_directory        = (Get-TestDataPath -SubPath "temp/output/" -Temp)
            timezone                        = "Asia/Tokyo"
        }
        csv_format           = @{
            provided_data = @{
                encoding         = "UTF-8"
                delimiter        = ","
                newline          = "LF"
                has_header       = $false
                null_values      = @("", "NULL", "null")
                allow_empty_file = $true  # テスト環境では空ファイルを許可
            }
            current_data  = @{
                encoding         = "UTF-8"
                delimiter        = ","
                newline          = "LF"
                has_header       = $true
                null_values      = @("", "NULL", "null")
                allow_empty_file = $true
            }
            output        = @{
                encoding       = "UTF-8"
                delimiter      = ","
                newline        = "CRLF"
                include_header = $true
            }
        }
        tables               = @{
            provided_data = @{
                description       = "提供データテーブル"
                table_constraints = @(
                    @{
                        name        = "uk_provided_employee_id"
                        type        = "UNIQUE"
                        columns     = @("employee_id")
                        description = "職員IDの一意制約（明示的定義）"
                    }
                )
                columns           = @(
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
                indexes           = @(
                    @{
                        name        = "idx_provided_employee_id"
                        columns     = @("employee_id")
                        description = "職員ID検索用インデックス（大量データ時の比較処理高速化）"
                    }
                )
            }
            current_data  = @{
                description       = "現在データテーブル"
                table_constraints = @(
                    @{
                        name        = "uk_current_user_id"
                        type        = "UNIQUE"
                        columns     = @("user_id")
                        description = "利用者IDの一意制約（明示的定義）"
                    }
                )
                columns           = @(
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
                indexes           = @(
                    @{
                        name        = "idx_current_user_id"
                        columns     = @("user_id")
                        description = "利用者ID検索用インデックス（大量データ時の比較処理高速化）"
                    }
                )
            }
            sync_result   = @{
                description       = "同期結果テーブル"
                table_constraints = @(
                    @{
                        name        = "uk_sync_result_syokuin_no"
                        type        = "UNIQUE"
                        columns     = @("syokuin_no")
                        description = "職員番号の一意制約（重複レコード防止）"
                    }
                )
                columns           = @(
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
                indexes           = @()
            }
        }
        sync_rules           = @{
            key_columns         = @{
                provided_data = @("employee_id")
                current_data  = @("user_id")
                sync_result   = @("syokuin_no")
            }
            column_mappings     = @{
                description = "テーブル間の比較項目対応付け（provided_dataの項目:current_dataの項目）"
                mappings    = @{
                    employee_id = "user_id"
                    card_number = "card_number"
                    name        = "name"
                    department  = "department"
                    position    = "position"
                    email       = "email"
                    phone       = "phone"
                    hire_date   = "hire_date"
                }
            }
            sync_result_mapping = @{
                description = "sync_resultテーブルへの格納項目対応付け（テスト用完全版）"
                mappings    = @{
                    syokuin_no  = @{
                        description = "職員番号"
                        sources     = @(
                            @{
                                type        = "provided_data"
                                field       = "employee_id"
                                priority    = 1
                                description = "提供データの職員ID（最優先）"
                            }
                            @{
                                type        = "current_data"
                                field       = "user_id"
                                priority    = 2
                                description = "現在データの利用者ID（フォールバック）"
                            }
                        )
                    }
                    card_number = @{
                        description = "カード番号"
                        sources     = @(
                            @{
                                type        = "provided_data"
                                field       = "card_number"
                                priority    = 1
                                description = "提供データのカード番号（最優先）"
                            }
                            @{
                                type        = "current_data"
                                field       = "card_number"
                                priority    = 2
                                description = "現在データのカード番号（フォールバック）"
                            }
                        )
                    }
                    name        = @{
                        description = "氏名"
                        sources     = @(
                            @{
                                type        = "provided_data"
                                field       = "name"
                                priority    = 1
                                description = "提供データの氏名（最優先）"
                            }
                            @{
                                type        = "current_data"
                                field       = "name"
                                priority    = 2
                                description = "現在データの氏名（フォールバック）"
                            }
                        )
                    }
                    department  = @{
                        description = "部署"
                        sources     = @(
                            @{
                                type        = "provided_data"
                                field       = "department"
                                priority    = 1
                                description = "提供データの部署（最優先）"
                            }
                            @{
                                type        = "current_data"
                                field       = "department"
                                priority    = 2
                                description = "現在データの部署（フォールバック）"
                            }
                            @{
                                type        = "fixed_value"
                                value       = "未設定"
                                priority    = 3
                                description = "デフォルト部署名（最終フォールバック）"
                            }
                        )
                    }
                    position    = @{
                        description = "役職"
                        sources     = @(
                            @{
                                type        = "provided_data"
                                field       = "position"
                                priority    = 1
                                description = "提供データの役職（最優先）"
                            }
                            @{
                                type        = "current_data"
                                field       = "position"
                                priority    = 2
                                description = "現在データの役職（フォールバック）"
                            }
                        )
                    }
                    email       = @{
                        description = "メールアドレス"
                        sources     = @(
                            @{
                                type        = "provided_data"
                                field       = "email"
                                priority    = 1
                                description = "提供データのメールアドレス（最優先）"
                            }
                            @{
                                type        = "current_data"
                                field       = "email"
                                priority    = 2
                                description = "現在データのメールアドレス（フォールバック）"
                            }
                        )
                    }
                    phone       = @{
                        description = "電話番号"
                        sources     = @(
                            @{
                                type        = "fixed_value"
                                value       = "999-9999-9999"
                                priority    = 1
                                description = "固定値"
                            }
                        )
                    }
                    hire_date   = @{
                        description = "入社日"
                        sources     = @(
                            @{
                                type        = "provided_data"
                                field       = "hire_date"
                                priority    = 1
                                description = "提供データの入社日（最優先）"
                            }
                            @{
                                type        = "current_data"
                                field       = "hire_date"
                                priority    = 2
                                description = "現在データの入社日（フォールバック）"
                            }
                        )
                    }
                }
            }
            sync_action_labels = @{
                mappings = @{
                    ADD    = @{ value = "1"; enabled = $true; description = "新規追加" }
                    UPDATE = @{ value = "2"; enabled = $true; description = "更新" }
                    DELETE = @{ value = "3"; enabled = $true; description = "削除" }
                    KEEP   = @{ value = "9"; enabled = $true; description = "変更なし" }
                }
            }
        }
        data_filters         = @{
            provided_data = @{
                enabled = $false
                rules   = @()
            }
            current_data  = @{
                enabled                 = $false
                rules                   = @()
                output_excluded_as_keep = @{
                    enabled = $false
                }
            }
        }
        logging              = @{
            enabled          = $true
            log_directory    = (Get-TestDataPath -SubPath "temp/logs/" -Temp)
            log_file_name    = "test-system.log"
            max_file_size_mb = 5
            max_files        = 3
            levels           = @("Info", "Warning", "Error", "Success")
        }
        performance_settings = @{
            description       = "性能最適化設定"
            index_threshold   = 100000
            batch_size        = 1000
            auto_optimization = $true
            sqlite_pragmas    = @{
                journal_mode = "WAL"
                synchronous  = "NORMAL"
                temp_store   = "MEMORY"
                cache_size   = 10000
            }
        }
        error_handling       = @{
            enabled           = $true
            log_stack_trace   = $true
            retry_settings    = @{
                enabled              = $false
                max_attempts         = 1
                delay_seconds        = @(1)
                retryable_categories = @()
            }
            error_levels      = @{
                description = "エラーカテゴリ別のログレベル設定"
                System      = "Error"
                Data        = "Warning"
                External    = "Error"
            }
            continue_on_error = @{
                System   = $false
                Data     = $true
                External = $false
            }
            cleanup_on_error  = $true
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

# 既存関数の互換性ラッパー（TestEnvironmentクラス使用に移行するまでの間）

# 簡易初期化関数（レガシー互換）
function Initialize-TestEnvironment {
    param(
        [string]$TestConfigPath = "",
        [switch]$CreateTempDatabase,
        [switch]$CleanupBefore
    )
    
    Write-Warning "Initialize-TestEnvironment関数は非推奨です。TestEnvironmentクラスの使用を推奨します。"
    
    # プロジェクトルートを取得
    $ProjectRoot = Find-ProjectRoot
    
    # 旧来の方式でクリーンアップ
    if ($CleanupBefore) {
        Clear-TestEnvironment -ProjectRoot $ProjectRoot
    }
    
    # テスト用データベースの作成（旧来の方式）
    $testDatabasePath = $null
    if ($CreateTempDatabase) {
        $testDatabasePath = New-TestDatabase -ProjectRoot $ProjectRoot
    }
    
    return @{
        ProjectRoot      = $ProjectRoot
        TestConfigPath   = $TestConfigPath
        TestDatabasePath = $testDatabasePath
    }
}

# TestEnvironmentクラス用の新しい初期化関数
function New-TestEnvironment {
    param(
        [string]$TestName = "default"
    )
    
    return [TestEnvironment]::new($TestName)
}

# レガシー互換のCSVデータ生成
function New-TestCsvData {
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataType,
        [int]$RecordCount = 10,
        [string]$OutputPath = "",
        [switch]$IncludeHeader,
        [string[]]$ExcludeIds = @(),
        [switch]$IncludeJapanese
    )
    
    Write-Warning "New-TestCsvData関数は非推奨です。TestEnvironmentクラスのCreateCsvFileメソッドの使用を推奨します。"
    
    # 既存の実装を維持（後方互換性のため）
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
    'New-TempTestFile',
    'New-TestEnvironment'
)