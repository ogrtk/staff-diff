# PowerShell & SQLite データ同期システム
# 統合テスト（フルシステムワークフロー）

# テストヘルパーの読み込み
using module "../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../TestHelpers/MockHelpers.psm1"
using module "../../scripts/modules/Utils/Foundation/CoreUtils.psm1"

Describe "フルシステム統合テスト" {
    
    BeforeAll {
        $script:ProjectRoot = Find-ProjectRoot
        $script:MainScriptPath = Join-Path $script:ProjectRoot "scripts" "main.ps1"        

        # TestEnvironmentクラスを使用したテスト環境の初期化
        $script:TestEnv = New-TestEnvironment -TestName "FullSystemIntegration"
        
        # TestEnvironmentから必要なパスを取得
        $script:TestDataDir = $script:TestEnv.GetTempDirectory()
        $script:TestDatabasePath = $script:TestEnv.CreateDatabase("integration-test")
        
        # TestEnvironmentクラスを使用したテスト用設定ファイルの作成
        $customSettings = @{
            file_paths     = @{
                provided_data_file_path         = Join-Path $script:TestDataDir "csv-data" "provided.csv"
                current_data_file_path          = Join-Path $script:TestDataDir "csv-data" "current.csv"
                output_file_path                = Join-Path $script:TestDataDir "csv-data" "output.csv"
                provided_data_history_directory = Join-Path $script:TestDataDir "provided-data-history"
                current_data_history_directory  = Join-Path $script:TestDataDir "current-data-history"
                output_history_directory        = Join-Path $script:TestDataDir "output-history"
            }
            sync_rules     = @{
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
                    description = "sync_resultテーブルへの格納項目対応付け"
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
                sync_action_labels  = @{
                    mappings = @{
                        ADD    = @{ value = "1"; enabled = $true; description = "新規追加" }
                        UPDATE = @{ value = "2"; enabled = $true; description = "更新" }
                        DELETE = @{ value = "3"; enabled = $true; description = "削除" }
                        KEEP   = @{ value = "9"; enabled = $true; description = "変更なし" }
                    }
                }
            }
            data_filters   = @{
                provided_data = @{
                    enabled = $true
                    rules   = @(
                        @{ field = "employee_id"; type = "exclude"; glob = "Z*"; description = "Z始まりの職員IDを除外" }
                    )
                }
                current_data  = @{
                    enabled                 = $true
                    rules                   = @(
                        @{ field = "user_id"; type = "exclude"; glob = "Z*"; description = "Z始まりのユーザーIDを除外" }
                    )
                    output_excluded_as_keep = @{
                        enabled = $true
                    }
                }
            }
            error_handling = @{
                enabled           = $true
                retry_settings    = @{
                    enabled = $false  # 統合テストではリトライを無効化
                }
                continue_on_error = @{
                    System   = $false
                    Data     = $true
                    External = $false
                }
            }
        }
        
        # TestEnvironmentクラスを使用して設定ファイルを作成
        $script:TestConfigPath = $script:TestEnv.CreateConfigFile($customSettings, "integration-test-config")
        $script:TestConfig = $script:TestEnv.GetConfig()
    }
    
    AfterAll {
        # TestEnvironmentクラスを使用したテスト環境のクリーンアップ
        if ($script:TestEnv) {
            $script:TestEnv.Dispose()
        }
    }
    
    BeforeEach {
        # TestEnvironmentクラスを使用して各テスト前のクリーンアップを実行
        # データベースの再作成
        $script:TestDatabasePath = $script:TestEnv.CreateDatabase("integration-test")
        
        # CSVファイルのパスを取得（TestEnvironmentの構造に合わせる）
        $csvDataDir = Join-Path $script:TestDataDir "csv-data"
        $csvFiles = @(
            (Join-Path $csvDataDir "provided.csv"),
            (Join-Path $csvDataDir "current.csv"),
            (Join-Path $csvDataDir "output.csv"),
            (Join-Path $csvDataDir "param-provided.csv"),
            (Join-Path $csvDataDir "param-current.csv"),
            (Join-Path $csvDataDir "param-output.csv")
        )
        foreach ($csvFile in $csvFiles) {
            if (Test-Path $csvFile) {
                Remove-Item $csvFile -Force -ErrorAction SilentlyContinue
            }
        }
        
        # 履歴ディレクトリのクリーンアップ（TestEnvironmentの構造に合わせる）
        $historyDirs = @(
            (Join-Path $script:TestDataDir "provided-data-history"),
            (Join-Path $script:TestDataDir "current-data-history"),
            (Join-Path $script:TestDataDir "output-history")
        )
        foreach ($dir in $historyDirs) {
            if (Test-Path $dir) {
                Remove-Item $dir -Recurse -Force -ErrorAction SilentlyContinue
            }
        }
    }

    Context "基本的なデータ同期フロー" {
        
        It "完全なデータ同期処理が正常に実行される" {
            # Arrange
            # 提供データ（新規、更新対象、フィルタ対象含む）
            $providedData = @(
                [PSCustomObject]@{ employee_id = "E001"; card_number = "C001"; name = "田中太郎"; department = "営業部"; position = "課長"; email = "tanaka@company.com"; phone = "03-1234-5678"; hire_date = "2020-01-15" }
                [PSCustomObject]@{ employee_id = "E002"; card_number = "C002"; name = "佐藤花子"; department = "開発部"; position = "主任"; email = "sato@company.com"; phone = "03-1234-5679"; hire_date = "2021-03-20" }
                [PSCustomObject]@{ employee_id = "E003"; card_number = "C003"; name = "鈴木一郎"; department = "総務部"; position = "一般"; email = "suzuki@company.com"; phone = "03-1234-5680"; hire_date = "2022-05-10" }
                [PSCustomObject]@{ employee_id = "Z999"; card_number = "C999"; name = "除外対象"; department = "テスト部"; position = "テスト"; email = "test@company.com"; phone = "03-9999-9999"; hire_date = "2023-01-01" }
            )
            
            # 現在データ（更新前、削除対象、保持対象含む）
            $currentData = @(
                [PSCustomObject]@{ user_id = "E002"; card_number = "C002"; name = "佐藤花子"; department = "開発部"; position = "一般"; email = "sato.old@company.com"; phone = "03-1234-0000"; hire_date = "2021-03-20" }
                [PSCustomObject]@{ user_id = "E004"; card_number = "C004"; name = "高橋美咲"; department = "人事部"; position = "係長"; email = "takahashi@company.com"; phone = "03-1234-5681"; hire_date = "2019-12-01" }
                [PSCustomObject]@{ user_id = "E005"; card_number = "C005"; name = "渡辺健太"; department = "経理部"; position = "主任"; email = "watanabe@company.com"; phone = "03-1234-5682"; hire_date = "2020-08-15" }
                [PSCustomObject]@{ user_id = "Z888"; card_number = "C888"; name = "除外KEEP対象"; department = "テスト部"; position = "テスト"; email = "keep@company.com"; phone = "03-8888-8888"; hire_date = "2023-02-01" }
            )
            
            # TestEnvironmentを使用してCSVファイルを作成
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $providedCsvPath = Join-Path $csvDataDir "provided.csv"
            $currentCsvPath = Join-Path $csvDataDir "current.csv"
            $outputCsvPath = Join-Path $csvDataDir "output.csv"
            
            # 提供データ（ヘッダーなし）
            $providedData | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $providedCsvPath -Encoding UTF8
            
            # 現在データ（ヘッダーあり）
            $currentData | Export-Csv -Path $currentCsvPath -NoTypeInformation -Encoding UTF8
            
            # SQLite3コマンドのモック化（実際のSQLiteを使用）
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            # メインスクリプトの実行
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $providedCsvPath -CurrentDataFilePath $currentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1
            
            # Assert
            # 出力ファイルが生成されていることを確認
            Test-Path $outputCsvPath | Should -Be $true
            
            # 出力内容の確認
            $outputData = Import-Csv $outputCsvPath -Encoding UTF8
            $outputData | Should -Not -BeNullOrEmpty
            
            # 同期アクションの確認
            $addActions = $outputData | Where-Object { $_.sync_action -eq "1" }  # ADD
            $updateActions = $outputData | Where-Object { $_.sync_action -eq "2" }  # UPDATE
            $deleteActions = $outputData | Where-Object { $_.sync_action -eq "3" }  # DELETE
            $keepActions = $outputData | Where-Object { $_.sync_action -eq "9" }  # KEEP
            
            # 新規追加（E001, E003）
            $addActions.Count | Should -BeGreaterOrEqual 2
            ($addActions | Where-Object { $_.syokuin_no -eq "E001" }) | Should -Not -BeNullOrEmpty
            ($addActions | Where-Object { $_.syokuin_no -eq "E003" }) | Should -Not -BeNullOrEmpty
            
            # 更新（E002）
            $updateActions.Count | Should -BeGreaterOrEqual 1
            ($updateActions | Where-Object { $_.syokuin_no -eq "E002" }) | Should -Not -BeNullOrEmpty
            
            # 削除（E004, E005）
            $deleteActions.Count | Should -BeGreaterOrEqual 2
            
            # KEEP（除外されたZ888がKEEPとして出力される）
            ($keepActions | Where-Object { $_.syokuin_no -eq "Z888" }) | Should -Not -BeNullOrEmpty
            
            # フィルタ除外（Z999は出力されない）
            ($outputData | Where-Object { $_.syokuin_no -eq "Z999" }) | Should -BeNullOrEmpty
        }
        
        It "空のデータファイルでも正常に処理される" {
            # Arrange
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $providedCsvPath = Join-Path $csvDataDir "empty-provided.csv"
            $currentCsvPath = Join-Path $csvDataDir "empty-current.csv"
            $outputCsvPath = Join-Path $csvDataDir "empty-output.csv"
            
            # 空のCSVファイル（ヘッダーのみ）
            "user_id,card_number,name,department,position,email,phone,hire_date" | Out-File -FilePath $currentCsvPath -Encoding UTF8
            # 提供データは空ファイル（ヘッダーなし設定のため）
            New-Item -Path $providedCsvPath -ItemType File -Force | Out-Null
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $providedCsvPath -CurrentDataFilePath $currentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1
            
            # Assert
            Test-Path $outputCsvPath | Should -Be $true
            $outputData = Import-Csv $outputCsvPath -Encoding UTF8
            $outputData.Count | Should -Be 0
        }
    }

    Context "履歴保存機能" {
        
        It "処理されたファイルが履歴ディレクトリに自動保存される" {
            # Arrange
            $providedData = @(
                [PSCustomObject]@{ employee_id = "E001"; card_number = "C001"; name = "履歴テスト"; department = "テスト部"; position = "テスト"; email = "test@company.com"; phone = "03-1234-5678"; hire_date = "2023-01-01" }
            )
            $currentData = @(
                [PSCustomObject]@{ user_id = "E002"; card_number = "C002"; name = "現在データ"; department = "テスト部"; position = "テスト"; email = "current@company.com"; phone = "03-1234-5679"; hire_date = "2023-01-02" }
            )
            
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $providedCsvPath = Join-Path $csvDataDir "history-provided.csv"
            $currentCsvPath = Join-Path $csvDataDir "history-current.csv"
            $outputCsvPath = Join-Path $csvDataDir "history-output.csv"
            
            $providedData | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $providedCsvPath -Encoding UTF8
            $currentData | Export-Csv -Path $currentCsvPath -NoTypeInformation -Encoding UTF8
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $providedCsvPath -CurrentDataFilePath $currentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1

            # Assert
            # 履歴ディレクトリが作成されていることを確認（TestEnvironmentの構造に合わせる）
            $providedHistoryDir = Join-Path $script:TestDataDir "provided-data-history"
            $currentHistoryDir = Join-Path $script:TestDataDir "current-data-history"
            $outputHistoryDir = Join-Path $script:TestDataDir "output-history"
            
            Test-Path $providedHistoryDir | Should -Be $true
            Test-Path $currentHistoryDir | Should -Be $true
            Test-Path $outputHistoryDir | Should -Be $true
            
            # 履歴ファイルが保存されていることを確認
            $providedHistoryFiles = Get-ChildItem $providedHistoryDir -Filter "*.csv"
            $currentHistoryFiles = Get-ChildItem $currentHistoryDir -Filter "*.csv"
            $outputHistoryFiles = Get-ChildItem $outputHistoryDir -Filter "*.csv"
            
            $providedHistoryFiles.Count | Should -BeGreaterOrEqual 1
            $currentHistoryFiles.Count | Should -BeGreaterOrEqual 1
            $outputHistoryFiles.Count | Should -BeGreaterOrEqual 1
            
            # ファイル名にタイムスタンプが含まれていることを確認
            $providedHistoryFiles[0].Name | Should -Match "\d{8}_\d{6}"
            $currentHistoryFiles[0].Name | Should -Match "\d{8}_\d{6}"
            $outputHistoryFiles[0].Name | Should -Match "\d{8}_\d{6}"
        }
    }

    Context "データフィルタリング機能" {
        
        It "GLOBパターンによるフィルタリングが正常に動作する" {
            # Arrange
            $providedData = @(
                [PSCustomObject]@{ employee_id = "E001"; card_number = "C001"; name = "通常データ1"; department = "営業部"; position = "課長"; email = "normal1@company.com"; phone = "03-1234-5678"; hire_date = "2020-01-15" }
                [PSCustomObject]@{ employee_id = "E002"; card_number = "C002"; name = "通常データ2"; department = "開発部"; position = "主任"; email = "normal2@company.com"; phone = "03-1234-5679"; hire_date = "2021-03-20" }
                [PSCustomObject]@{ employee_id = "Z001"; card_number = "C901"; name = "除外データ1"; department = "テスト部"; position = "テスト"; email = "exclude1@company.com"; phone = "03-9999-0001"; hire_date = "2023-01-01" }
                [PSCustomObject]@{ employee_id = "Z002"; card_number = "C902"; name = "除外データ2"; department = "テスト部"; position = "テスト"; email = "exclude2@company.com"; phone = "03-9999-0002"; hire_date = "2023-01-02" }
            )
            
            $currentData = @(
                [PSCustomObject]@{ user_id = "E003"; card_number = "C003"; name = "現在データ1"; department = "人事部"; position = "係長"; email = "current1@company.com"; phone = "03-1234-5680"; hire_date = "2019-12-01" }
                [PSCustomObject]@{ user_id = "Z003"; card_number = "C903"; name = "除外KEEP対象"; department = "テスト部"; position = "テスト"; email = "keep@company.com"; phone = "03-9999-0003"; hire_date = "2023-02-01" }
            )
            
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $providedCsvPath = Join-Path $csvDataDir "filter-provided.csv"
            $currentCsvPath = Join-Path $csvDataDir "filter-current.csv"
            $outputCsvPath = Join-Path $csvDataDir "filter-output.csv"
            
            $providedData | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $providedCsvPath -Encoding UTF8
            $currentData | Export-Csv -Path $currentCsvPath -NoTypeInformation -Encoding UTF8
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $providedCsvPath -CurrentDataFilePath $currentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1
            
            # Assert
            $outputData = Import-Csv $outputCsvPath -Encoding UTF8
            
            # Z*パターンで除外されたデータが処理されていないことを確認
            ($outputData | Where-Object { $_.syokuin_no -match "^Z" -and $_.sync_action -ne "9" }) | Should -BeNullOrEmpty
            
            # 通常データ（E*）は処理されていることを確認
            ($outputData | Where-Object { $_.syokuin_no -match "^E" }) | Should -Not -BeNullOrEmpty
            
            # 除外されたcurrent_dataがKEEPアクションで出力されていることを確認（output_excluded_as_keep設定による）
            $excludedKeepData = $outputData | Where-Object { $_.syokuin_no -eq "Z003" -and $_.sync_action -eq "9" }
            $excludedKeepData | Should -Not -BeNullOrEmpty
            $excludedKeepData.name | Should -Be "除外KEEP対象"
        }
    }

    Context "エラーハンドリング" {
        
        It "不正なCSVファイルでもエラーハンドリングされて処理が継続される" {
            # Arrange
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $invalidProvidedCsvPath = Join-Path $csvDataDir "invalid-provided.csv"
            $validCurrentCsvPath = Join-Path $csvDataDir "valid-current.csv"
            $outputCsvPath = Join-Path $csvDataDir "error-output.csv"
            
            # 不正なCSVファイル（カラム数不一致）
            @"
E001,C001,田中太郎,営業部
E002,C002,佐藤花子,開発部,主任,extra_column
E003,C003
"@ | Out-File -FilePath $invalidProvidedCsvPath -Encoding UTF8
            
            # 有効なcurrent_data
            $validCurrentData = @(
                [PSCustomObject]@{ user_id = "E004"; card_number = "C004"; name = "有効データ"; department = "総務部"; position = "一般"; email = "valid@company.com"; phone = "03-1234-5680"; hire_date = "2022-01-01" }
            )
            $validCurrentData | Export-Csv -Path $validCurrentCsvPath -NoTypeInformation -Encoding UTF8
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act & Assert
            # エラーが発生しても処理が完全停止しないことを確認
            $ErrorActionPreference = "Continue"
            try {
                $result = & pwsh $script:MainScriptPath -ProvidedDataFilePath $invalidProvidedCsvPath -CurrentDataFilePath $validCurrentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1
                
                # エラーログが出力されているかどうかを確認
                $result | Should -Not -BeNullOrEmpty
            }
            finally {
                $ErrorActionPreference = $script:OriginalErrorActionPreference
            }
        }
    }

    Context "設定ファイルのバリエーション" {
        
        It "フィルタリング無効設定で全データが処理される" {
            # Arrange
            # フィルタリング無効の設定
            $noFilterConfig = $script:TestConfig.Clone()
            $noFilterConfig.data_filters.provided_data.enabled = $false
            $noFilterConfig.data_filters.current_data.enabled = $false
            # sync_action_labelsが存在することを確認し、すべてのアクションを有効化
            # sync_rulesを確実に初期化してから設定
            $noFilterConfig.sync_rules.sync_action_labels = @{
                mappings = @{
                    ADD    = @{ value = "1"; enabled = $true; description = "新規追加" }
                    UPDATE = @{ value = "2"; enabled = $true; description = "更新" }
                    DELETE = @{ value = "3"; enabled = $true; description = "削除" }
                    KEEP   = @{ value = "9"; enabled = $true; description = "変更なし" }
                }
            }
            
            $configDir = Join-Path $script:TestDataDir "config"
            $noFilterConfigPath = Join-Path $configDir "no-filter-config.json"
            $noFilterConfig | ConvertTo-Json -Depth 15 | Out-File -FilePath $noFilterConfigPath -Encoding UTF8
            
            $providedData = @(
                [PSCustomObject]@{ employee_id = "E001"; card_number = "C001"; name = "通常データ"; department = "営業部"; position = "課長"; email = "normal@company.com"; phone = "03-1234-5678"; hire_date = "2020-01-15" }
                [PSCustomObject]@{ employee_id = "Z001"; card_number = "C901"; name = "除外対象外データ"; department = "テスト部"; position = "テスト"; email = "no_exclude@company.com"; phone = "03-9999-0001"; hire_date = "2023-01-01" }
            )
            
            $currentData = @(
                [PSCustomObject]@{ user_id = "E002"; card_number = "C002"; name = "現在データ"; department = "開発部"; position = "主任"; email = "current@company.com"; phone = "03-1234-5679"; hire_date = "2021-03-20" }
            )
            
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $providedCsvPath = Join-Path $csvDataDir "no-filter-provided.csv"
            $currentCsvPath = Join-Path $csvDataDir "no-filter-current.csv"
            $outputCsvPath = Join-Path $csvDataDir "no-filter-output.csv"
            
            $providedData | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $providedCsvPath -Encoding UTF8
            $currentData | Export-Csv -Path $currentCsvPath -NoTypeInformation -Encoding UTF8
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $providedCsvPath -CurrentDataFilePath $currentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $noFilterConfigPath 2>&1
            
            # Assert
            $outputData = Import-Csv $outputCsvPath -Encoding UTF8
            
            # Z*データも処理されていることを確認（フィルタリング無効のため）
            ($outputData | Where-Object { $_.syokuin_no -eq "Z001" }) | Should -Not -BeNullOrEmpty
        }
    }

    Context "パフォーマンスと大量データ" {
        
        It "中程度のデータ量（100件）で正常に処理される" {
            # Arrange
            # TestEnvironmentのCSV作成機能を使用
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $providedCsvPath = $script:TestEnv.CreateCsvFile("provided_data", 50, @{ IncludeJapanese = $true; CustomFileName = "large-provided.csv"; IncludeHeader = $false })
            $currentCsvPath = $script:TestEnv.CreateCsvFile("current_data", 50, @{ IncludeJapanese = $true; CustomFileName = "large-current.csv"; IncludeHeader = $true })
            $outputCsvPath = Join-Path $csvDataDir "large-output.csv"
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            $startTime = Get-Date
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $providedCsvPath -CurrentDataFilePath $currentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            Test-Path $outputCsvPath | Should -Be $true
            $outputData = Import-Csv $outputCsvPath -Encoding UTF8
            $outputData | Should -Not -BeNullOrEmpty
            
            # パフォーマンス確認（100件程度なら30秒以内で完了すべき）
            $duration | Should -BeLessThan 30
            
            # データ整合性確認
            $totalOutputCount = $outputData.Count
            $totalOutputCount | Should -BeGreaterThan 0
            
            # 各sync_actionが適切に設定されていることを確認
            $validActions = @("1", "2", "3", "9")
            foreach ($record in $outputData) {
                $record.sync_action | Should -BeIn $validActions
            }
        }
    }

    Context "ログとデバッグ情報" {
        
        It "ログファイルが適切に生成される" {
            # Arrange
            $providedData = @(
                [PSCustomObject]@{ employee_id = "E001"; card_number = "C001"; name = "ログテスト"; department = "テスト部"; position = "テスト"; email = "log@company.com"; phone = "03-1234-5678"; hire_date = "2023-01-01" }
            )
            
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $providedCsvPath = Join-Path $csvDataDir "log-provided.csv"
            $currentCsvPath = Join-Path $csvDataDir "log-current.csv"
            $outputCsvPath = Join-Path $csvDataDir "log-output.csv"
            
            $providedData | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $providedCsvPath -Encoding UTF8
            "user_id,card_number,name,department,position,email,phone,hire_date" | Out-File -FilePath $currentCsvPath -Encoding UTF8
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $providedCsvPath -CurrentDataFilePath $currentCsvPath -OutputFilePath $outputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1
            
            # Assert
            # ログディレクトリが作成されていることを確認（TestEnvironmentの構造に合わせる）
            $logDir = Join-Path $script:TestDataDir "logs"
            if (Test-Path $logDir) {
                $logFiles = Get-ChildItem $logDir -Filter "*.log"
                $logFiles.Count | Should -BeGreaterOrEqual 1
                
                # ログファイル内容の確認
                if ($logFiles.Count -gt 0) {
                    $logContent = Get-Content $logFiles[0].FullName -Raw
                    $logContent | Should -Not -BeNullOrEmpty
                    $logContent | Should -Match "データ同期処理を開始します"
                }
            }
        }
    }

    Context "設定とパラメータの組み合わせテスト" {
        
        It "コマンドラインパラメータが設定ファイルより優先される" {
            # Arrange
            $providedData = @(
                [PSCustomObject]@{ employee_id = "E001"; card_number = "C001"; name = "パラメータテスト"; department = "テスト部"; position = "テスト"; email = "param@company.com"; phone = "03-1234-5678"; hire_date = "2023-01-01" }
            )
            
            # 設定ファイルとは異なるパスをパラメータで指定
            $csvDataDir = Join-Path $script:TestDataDir "csv-data"
            $paramProvidedCsvPath = Join-Path $csvDataDir "param-provided.csv"
            $paramCurrentCsvPath = Join-Path $csvDataDir "param-current.csv"
            $paramOutputCsvPath = Join-Path $csvDataDir "param-output.csv"
            
            $providedData | ConvertTo-Csv -NoTypeInformation | Select-Object -Skip 1 | Out-File -FilePath $paramProvidedCsvPath -Encoding UTF8
            "user_id,card_number,name,department,position,email,phone,hire_date" | Out-File -FilePath $paramCurrentCsvPath -Encoding UTF8
            
            if (-not (Get-Command sqlite3 -ErrorAction SilentlyContinue)) {
                New-MockSqliteCommand -ReturnValue "" -ExitCode 0
            }
            
            # Act
            & pwsh $script:MainScriptPath -ProvidedDataFilePath $paramProvidedCsvPath -CurrentDataFilePath $paramCurrentCsvPath -OutputFilePath $paramOutputCsvPath -DatabasePath $script:TestDatabasePath -ConfigFilePath $script:TestConfigPath 2>&1

            # Assert
            # パラメータで指定したパスに出力ファイルが生成されることを確認
            Test-Path $paramOutputCsvPath | Should -Be $true
            
            # 設定ファイルで指定されたパスには出力されないことを確認
            $configOutputPath = $script:TestConfig.file_paths.output_file_path
            if ($configOutputPath -ne $paramOutputCsvPath) {
                Test-Path $configOutputPath | Should -Be $false
            }
        }
    }
}