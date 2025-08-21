# PowerShell & SQLite データ同期システム
# Infrastructure/ConfigurationUtils.psm1 ユニットテスト

# テスト環境の設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName
$ModulePath = Join-Path $ProjectRoot "scripts" "modules" "Utils" "Infrastructure" "ConfigurationUtils.psm1"
$TestHelpersPath = Join-Path $ProjectRoot "tests" "TestHelpers"

# 依存モジュールの読み込み
Import-Module (Join-Path $ProjectRoot "scripts" "modules" "Utils" "Foundation" "CoreUtils.psm1") -Force

# テストヘルパーの読み込み
Import-Module (Join-Path $TestHelpersPath "TestEnvironmentHelpers.psm1") -Force
Import-Module (Join-Path $TestHelpersPath "MockHelpers.psm1") -Force

# テスト対象モジュールの読み込み
Import-Module $ModulePath -Force

Describe "ConfigurationUtils モジュール" {
    
    BeforeAll {
        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment -ProjectRoot $ProjectRoot
        $script:OriginalErrorActionPreference = $ErrorActionPreference
        
        # テスト用設定データの準備
        $script:ValidTestConfig = New-TestConfig
        $script:TestConfigPath = New-TempTestFile -Content ($script:ValidTestConfig | ConvertTo-Json -Depth 10) -Extension ".json" -Prefix "test_config_"
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment -ProjectRoot $ProjectRoot
        $ErrorActionPreference = $script:OriginalErrorActionPreference
        
        # 一時ファイルのクリーンアップ
        if (Test-Path $script:TestConfigPath) {
            Remove-Item $script:TestConfigPath -Force -ErrorAction SilentlyContinue
        }
    }
    
    BeforeEach {
        # モックのリセットは不要。Pesterが自動で管理。
        # 設定キャッシュのリセット
        if (Get-Command "Reset-DataSyncConfig" -ErrorAction SilentlyContinue) {
            Reset-DataSyncConfig
        }
    }

    Context "Get-DataSyncConfig 関数" {
        
        It "初回読み込み時、設定ファイルから正しく設定を読み込む" {
            # Arrange
            New-MockFileSystemOperations -FileExists @{ $script:TestConfigPath = $true } -FileContent @{ $script:TestConfigPath = ($script:ValidTestConfig | ConvertTo-Json -Depth 10) }
            New-MockLoggingSystem -SuppressOutput
            
            # Act
            $result = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.version | Should -Be "1.0.0"
            $result.tables.provided_data | Should -Not -BeNullOrEmpty
            $result.tables.current_data | Should -Not -BeNullOrEmpty
            $result.tables.sync_result | Should -Not -BeNullOrEmpty
        }
        
        It "キャッシュされた設定がある場合、ファイルを再読み込みしない" {
            # Arrange
            # $cachedConfig = [PSCustomObject]@{ version = "cached"; test = "data" }
            New-MockLoggingSystem -SuppressOutput
            
            # 初回読み込み
            New-MockFileSystemOperations -FileExists @{ $script:TestConfigPath = $true } -FileContent @{ $script:TestConfigPath = ($script:ValidTestConfig | ConvertTo-Json -Depth 10) }
            Get-DataSyncConfig -ConfigPath $script:TestConfigPath | Out-Null
            
            # ファイルシステムモックをリセット（2回目の呼び出しでファイル読み込みがないことを確認）
            # Pesterのモック機能で既存のモックを上書きする
            New-MockCommand -CommandName "Test-Path" -MockScript { throw "ファイルアクセスが発生した" }
            New-MockCommand -CommandName "Get-Content" -MockScript { throw "ファイル読み込みが発生した" }
            
            # Act
            $result = Get-DataSyncConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.version | Should -Be "1.0.0"
        }
        
        It "Forceスイッチ使用時、キャッシュを無視して再読み込みする" {
            # Arrange
            New-MockFileSystemOperations -FileExists @{ $script:TestConfigPath = $true } -FileContent @{ $script:TestConfigPath = ($script:ValidTestConfig | ConvertTo-Json -Depth 10) }
            New-MockLoggingSystem -SuppressOutput
            
            # 初回読み込み
            Get-DataSyncConfig -ConfigPath $script:TestConfigPath | Out-Null
            
            # Forceで再読み込み時、新しい設定内容
            $updatedConfig = $script:ValidTestConfig.Clone()
            $updatedConfig.version = "2.0.0"
            New-MockFileSystemOperations -FileExists @{ $script:TestConfigPath = $true } -FileContent @{ $script:TestConfigPath = ($updatedConfig | ConvertTo-Json -Depth 10) }
            
            # Act
            $result = Get-DataSyncConfig -ConfigPath $script:TestConfigPath -Force
            
            # Assert
            $result.version | Should -Be "2.0.0"
        }
        
        It "設定ファイルが存在しない場合、エラーをスローする" {
            # Arrange
            $nonExistentPath = "/path/to/nonexistent.json"
            New-MockFileSystemOperations -FileExists @{ $nonExistentPath = $false }
            
            # Act & Assert
            { Get-DataSyncConfig -ConfigPath $nonExistentPath } | Should -Throw "*設定ファイルが見つかりません*"
        }
        
        It "テスト環境で設定パスが未指定の場合、デフォルト設定を使用する" {
            # Arrange
            $env:PESTER_TEST = "1"
            New-MockCommand -CommandName "Get-Command" -ReturnValue @{ Name = "Describe" }
            
            # Act
            $result = Get-DataSyncConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.tables.provided_data | Should -Not -BeNullOrEmpty
            $result.tables.current_data | Should -Not -BeNullOrEmpty
            
            # クリーンアップ
            Remove-Item Env:PESTER_TEST -ErrorAction SilentlyContinue
        }
        
        It "非テスト環境で設定パス未指定の場合、エラーをスローする" {
            # Arrange
            Remove-Item Env:PESTER_TEST -ErrorAction SilentlyContinue
            New-MockCommand -CommandName "Get-Command" -ReturnValue $null
            
            # Act & Assert
            { Get-DataSyncConfig } | Should -Throw "*設定がまだ読み込まれていません*"
        }
        
        It "JSON解析エラーの場合、適切なエラーをスローする" {
            # Arrange
            $invalidJsonPath = "/path/to/invalid.json"
            $invalidJson = "{ invalid json content"
            New-MockFileSystemOperations -FileExists @{ $invalidJsonPath = $true } -FileContent @{ $invalidJsonPath = $invalidJson }
            
            # Act & Assert
            { Get-DataSyncConfig -ConfigPath $invalidJsonPath } | Should -Throw
        }
    }

    Context "Get-FilePathConfig 関数" {
        
        It "file_paths設定が存在する場合、その設定を返す" {
            # Arrange
            $configWithPaths = $script:ValidTestConfig.Clone()
            $configWithPaths.file_paths = @{
                provided_data_history_directory = "./custom/provided/"
                current_data_history_directory  = "./custom/current/"
                output_history_directory        = "./custom/output/"
                timezone                        = "UTC"
            }
            Mock-ConfigurationSystem -MockConfig $configWithPaths
            
            # Act
            $result = Get-FilePathConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.provided_data_history_directory | Should -Be "./custom/provided/"
            $result.current_data_history_directory | Should -Be "./custom/current/"
            $result.output_history_directory | Should -Be "./custom/output/"
            $result.timezone | Should -Be "UTC"
        }
        
        It "file_paths設定が存在しない場合、デフォルト値を生成する" {
            # Arrange
            $configWithoutPaths = @{ version = "1.0.0"; tables = @{} }
            Mock-ConfigurationSystem -MockConfig $configWithoutPaths
            
            # Act
            $result = Get-FilePathConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.provided_data_history_directory | Should -Be "./data/provided-data/"
            $result.current_data_history_directory | Should -Be "./data/current-data/"
            $result.output_history_directory | Should -Be "./data/output/"
            $result.timezone | Should -Be "Asia/Tokyo"
        }
        
        It "部分的なfile_paths設定の場合、欠損項目にデフォルト値を設定する" {
            # Arrange
            $partialConfig = @{
                file_paths = @{
                    provided_data_history_directory = "./custom/provided/"
                    # current_data_history_directory と output_history_directory は未設定
                    timezone                        = "UTC"
                }
            }
            Mock-ConfigurationSystem -MockConfig $partialConfig
            
            # Act
            $result = Get-FilePathConfig
            
            # Assert
            $result.provided_data_history_directory | Should -Be "./custom/provided/"
            $result.current_data_history_directory | Should -Be "./data/current-data/"
            $result.output_history_directory | Should -Be "./data/output/"
            $result.timezone | Should -Be "UTC"
        }
    }

    Context "Get-LoggingConfig 関数" {
        
        It "logging設定が存在する場合、その設定を返す" {
            # Arrange
            $configWithLogging = $script:ValidTestConfig.Clone()
            Mock-ConfigurationSystem -MockConfig $configWithLogging
            
            # Act
            $result = Get-LoggingConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.enabled | Should -Be $true
            $result.log_directory | Should -Be "./test-data/temp/logs/"
            $result.log_file_name | Should -Be "test-system.log"
            $result.max_file_size_mb | Should -Be 5
            $result.max_files | Should -Be 3
        }
        
        It "logging設定が存在しない場合、デフォルト値を生成する" {
            # Arrange
            $configWithoutLogging = @{ version = "1.0.0" }
            Mock-ConfigurationSystem -MockConfig $configWithoutLogging
            
            # Act
            $result = Get-LoggingConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.enabled | Should -Be $true
            $result.log_directory | Should -Be "./logs/"
            $result.log_file_name | Should -Be "data-sync-system.log"
            $result.max_file_size_mb | Should -Be 10
            $result.max_files | Should -Be 5
        }
    }

    Context "Get-DataFilterConfig 関数" {
        
        It "指定されたテーブルのフィルタ設定が存在する場合、その設定を返す" {
            # Arrange
            $configWithFilters = @{
                data_filters = @{
                    provided_data = @{
                        enabled = $true
                        rules   = @(
                            @{ field = "employee_id"; type = "exclude"; glob = "Z*" }
                        )
                    }
                }
            }
            Mock-ConfigurationSystem -MockConfig $configWithFilters
            
            # Act
            $result = Get-DataFilterConfig -TableName "provided_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.enabled | Should -Be $true
            $result.rules | Should -Not -BeNullOrEmpty
            $result.rules[0].field | Should -Be "employee_id"
        }
        
        It "指定されたテーブルのフィルタ設定が存在しない場合、nullを返す" {
            # Arrange
            $configWithoutFilters = @{ version = "1.0.0" }
            Mock-ConfigurationSystem -MockConfig $configWithoutFilters
            
            # Act
            $result = Get-DataFilterConfig -TableName "nonexistent_table"
            
            # Assert
            $result | Should -BeNullOrEmpty
        }
        
        It "data_filters設定自体が存在しない場合、nullを返す" {
            # Arrange
            $configWithoutDataFilters = @{ version = "1.0.0" }
            Mock-ConfigurationSystem -MockConfig $configWithoutDataFilters
            
            # Act
            $result = Get-DataFilterConfig -TableName "provided_data"
            
            # Assert
            $result | Should -BeNullOrEmpty
        }
    }

    Context "Get-SyncResultMappingConfig 関数" {
        
        It "sync_result_mapping設定が存在する場合、その設定を返す" {
            # Arrange
            Mock-ConfigurationSystem -MockConfig $script:ValidTestConfig
            
            # Act
            $result = Get-SyncResultMappingConfig
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.mappings | Should -Not -BeNullOrEmpty
        }
        
        It "sync_result_mapping設定が存在しない場合、エラーをスローする" {
            # Arrange
            $configWithoutMapping = @{ sync_rules = @{} }
            Mock-ConfigurationSystem -MockConfig $configWithoutMapping
            
            # Act & Assert
            { Get-SyncResultMappingConfig } | Should -Throw "*sync_result_mapping設定が見つかりません*"
        }
        
        It "sync_rules設定自体が存在しない場合、エラーをスローする" {
            # Arrange
            $configWithoutSyncRules = @{ version = "1.0.0" }
            Mock-ConfigurationSystem -MockConfig $configWithoutSyncRules
            
            # Act & Assert
            { Get-SyncResultMappingConfig } | Should -Throw "*sync_result_mapping設定が見つかりません*"
        }
    }

    Context "Test-DataSyncConfig 関数" {
        
        It "有効な設定の場合、エラーなく完了する" {
            # Arrange
            New-MockLoggingSystem -SuppressOutput
            
            # Act & Assert
            { Test-DataSyncConfig -Config $script:ValidTestConfig } | Should -Not -Throw
        }
        
        It "tables設定が存在しない場合、エラーをスローする" {
            # Arrange
            $invalidConfig = @{ version = "1.0.0" }
            
            # Act & Assert
            { Test-DataSyncConfig -Config $invalidConfig } | Should -Throw "*テーブル定義が見つかりません*"
        }
        
        It "必須テーブルが不足している場合、エラーをスローする" {
            # Arrange
            $incompleteConfig = @{
                tables     = @{
                    provided_data = @{ columns = @() }
                    # current_data と sync_result が不足
                }
                sync_rules = @{
                    column_mappings     = @{ mappings = @{} }
                    key_columns         = @{}
                    sync_result_mapping = @{ mappings = @{} }
                }
                csv_format = @{}
                logging    = @{ levels = @("Info") }
            }
            New-MockLoggingSystem -SuppressOutput
            
            # Act & Assert
            { Test-DataSyncConfig -Config $incompleteConfig } | Should -Throw "*必須テーブル*定義が見つかりません*"
        }
        
        It "テーブルのカラム定義が空の場合、エラーをスローする" {
            # Arrange
            $configWithEmptyColumns = @{
                tables = @{
                    provided_data = @{ columns = @() }  # 空のカラム定義
                    current_data  = @{ columns = @() }
                    sync_result   = @{ columns = @() }
                }
            }
            
            # Act & Assert
            { Test-DataSyncConfig -Config $configWithEmptyColumns } | Should -Throw "*カラムが定義されていません*"
        }
    }

    Context "Test-CsvFormatConfig 関数" {
        
        It "有効なCSVフォーマット設定の場合、エラーなく完了する" {
            # Arrange
            $validCsvConfig = @{
                csv_format = @{
                    provided_data = @{
                        encoding   = "UTF-8"
                        delimiter  = ","
                        newline    = "LF"
                        has_header = $false
                    }
                    current_data  = @{
                        encoding   = "UTF-8"
                        delimiter  = ","
                        newline    = "CRLF"
                        has_header = $true
                    }
                    output        = @{
                        encoding       = "UTF-8"
                        delimiter      = ","
                        newline        = "CRLF"
                        include_header = $true
                    }
                }
            }
            
            # Act & Assert
            { Test-CsvFormatConfig -Config $validCsvConfig } | Should -Not -Throw
        }
        
        It "csv_format設定が存在しない場合、エラーをスローする" {
            # Arrange
            $configWithoutCsvFormat = @{ version = "1.0.0" }
            
            # Act & Assert
            { Test-CsvFormatConfig -Config $configWithoutCsvFormat } | Should -Throw "*csv_format設定が見つかりません*"
        }
        
        It "無効なエンコーディングの場合、警告を出力する" {
            # Arrange
            $configWithInvalidEncoding = @{
                csv_format = @{
                    provided_data = @{
                        encoding   = "INVALID-ENCODING"
                        has_header = $true
                    }
                }
            }
            
            # モック化してWarningをキャプチャ
            $warningMessages = @()
            New-MockCommand -CommandName "Write-Warning" -MockScript {
                param($Message)
                $script:warningMessages += $Message
            }
            
            # Act
            Test-CsvFormatConfig -Config $configWithInvalidEncoding
            
            # Assert
            $warningMessages | Should -Contain "*無効なエンコーディング*"
        }
        
        It "has_header設定が不足している場合（provided_data, current_data）、エラーをスローする" {
            # Arrange
            $configWithoutHasHeader = @{
                csv_format = @{
                    provided_data = @{
                        encoding  = "UTF-8"
                        delimiter = ","
                        # has_header が不足
                    }
                }
            }
            
            # Act & Assert
            { Test-CsvFormatConfig -Config $configWithoutHasHeader } | Should -Throw "*has_header*設定が必要です*"
        }
        
        It "include_header設定が不足している場合（output）、エラーをスローする" {
            # Arrange
            $configWithoutIncludeHeader = @{
                csv_format = @{
                    output = @{
                        encoding  = "UTF-8"
                        delimiter = ","
                        # include_header が不足
                    }
                }
            }
            
            # Act & Assert
            { Test-CsvFormatConfig -Config $configWithoutIncludeHeader } | Should -Throw "*include_header*設定が必要です*"
        }
    }

    Context "Reset-DataSyncConfig 関数" {
        
        It "設定キャッシュが正しくクリアされる" {
            # Arrange
            New-MockLoggingSystem -SuppressOutput
            New-MockFileSystemOperations -FileExists @{ $script:TestConfigPath = $true } -FileContent @{ $script:TestConfigPath = ($script:ValidTestConfig | ConvertTo-Json -Depth 10) }
            
            # 設定をキャッシュ
            Get-DataSyncConfig -ConfigPath $script:TestConfigPath | Out-Null
            
            # Act
            Reset-DataSyncConfig
            
            # キャッシュクリア後は設定パスが必要
            { Get-DataSyncConfig } | Should -Throw "*設定がまだ読み込まれていません*"
        }
    }

    Context "関数のエクスポート確認" {
        
        It "すべての期待される関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'Get-DataSyncConfig',
                'Get-FilePathConfig',
                'Get-LoggingConfig',
                'Get-DataFilterConfig',
                'Get-SyncResultMappingConfig',
                'Test-DataSyncConfig',
                'Reset-DataSyncConfig'
            )
            
            # Act
            $module = Get-Module -Name ConfigurationUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($expectedFunction in $expectedFunctions) {
                $exportedFunctions | Should -Contain $expectedFunction
            }
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "巨大な設定ファイルの処理" {
            # Arrange
            $largeConfig = $script:ValidTestConfig.Clone()
            # 大量のダミーデータを追加
            $largeConfig.large_data = @{}
            for ($i = 1; $i -le 1000; $i++) {
                $largeConfig.large_data["item_$i"] = "value_$i"
            }
            
            $largeConfigJson = $largeConfig | ConvertTo-Json -Depth 15
            $largePath = New-TempTestFile -Content $largeConfigJson -Extension ".json" -Prefix "large_config_"
            
            New-MockFileSystemOperations -FileExists @{ $largePath = $true } -FileContent @{ $largePath = $largeConfigJson }
            New-MockLoggingSystem -SuppressOutput
            
            try {
                # Act
                $result = Get-DataSyncConfig -ConfigPath $largePath
                
                # Assert
                $result | Should -Not -BeNullOrEmpty
                $result.version | Should -Be "1.0.0"
                $result.large_data.item_1 | Should -Be "value_1"
            }
            finally {
                if (Test-Path $largePath) {
                    Remove-Item $largePath -Force -ErrorAction SilentlyContinue
                }
            }
        }
        
        It "並行アクセス時の設定キャッシュの動作" {
            # Arrange
            New-MockFileSystemOperations -FileExists @{ $script:TestConfigPath = $true } -FileContent @{ $script:TestConfigPath = ($script:ValidTestConfig | ConvertTo-Json -Depth 10) }
            New-MockLoggingSystem -SuppressOutput
            
            # Act - 複数回の同時アクセスをシミュレート
            $results = @()
            for ($i = 1; $i -le 5; $i++) {
                $results += Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            }
            
            # Assert
            $results.Count | Should -Be 5
            foreach ($result in $results) {
                $result.version | Should -Be "1.0.0"
            }
        }
        
        It "不正なJSON構造の詳細なエラー処理" {
            # Arrange
            $malformedConfigs = @(
                '{"version": "1.0.0", "tables": }', # 構文エラー
                '{"version": 1.0.0}', # 型エラー（文字列ではなく数値）
                '{"version": "1.0.0", "tables": null}'  # null値
            )
            
            foreach ($malformedJson in $malformedConfigs) {
                $malformedPath = New-TempTestFile -Content $malformedJson -Extension ".json" -Prefix "malformed_"
                New-MockFileSystemOperations -FileExists @{ $malformedPath = $true } -FileContent @{ $malformedPath = $malformedJson }
                
                # Act & Assert
                { Get-DataSyncConfig -ConfigPath $malformedPath } | Should -Throw
                
                # クリーンアップ
                if (Test-Path $malformedPath) {
                    Remove-Item $malformedPath -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    
}