#!/usr/bin/env pwsh
# Infrastructure Layer (Layer 2) - ConfigurationUtils Module Tests

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 2 (Infrastructure) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "Infrastructure" -ModuleName "ConfigurationUtils"
    
    # テスト用設定ファイルの作成
    $script:TestConfigPath = Join-Path $script:TestEnv.TempDirectory.Path "test-config.json"
    $testConfig = New-MockConfiguration
    $testConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:TestConfigPath -Encoding UTF8
    
    # 実際の設定ファイルパス
    $script:RealConfigPath = Join-Path (Get-ProjectRoot) "config/data-sync-config.json"
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "ConfigurationUtils (インフラストラクチャ層) テスト" {
    
    Context "Layer Architecture Validation" {
        It "should be Layer 2 with Foundation dependencies only" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "Infrastructure" -ModuleName "ConfigurationUtils"
            $dependencies.Dependencies | Should -Contain "Foundation"
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "should use Foundation layer functions" {
            # ConfigurationUtilsがFoundation層の関数を使用することを確認
            $config = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            $config | Should -Not -BeNullOrEmpty
            
            # Get-CrossPlatformEncodingが内部で使用されることを確認
            Should -Invoke Get-CrossPlatformEncoding -ModuleName ConfigurationUtils -Times 1 -Exactly
        }
    }
    
    Context "Get-DataSyncConfig Function - Configuration Loading" {
        It "should load configuration from specified path" {
            $config = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            $config | Should -Not -BeNullOrEmpty
            $config.file_paths | Should -Not -BeNullOrEmpty
            $config.tables | Should -Not -BeNullOrEmpty
            $config.sync_config | Should -Not -BeNullOrEmpty
        }
        
        It "should cache configuration after first load" {
            # 最初の読み込み
            $config1 = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            # キャッシュからの読み込み（ConfigPathなし）
            $config2 = Get-DataSyncConfig
            
            $config1 | Should -Be $config2
            $config1.file_paths | Should -Be $config2.file_paths
        }
        
        It "should force reload with -Force parameter" {
            # 最初の読み込み
            $config1 = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            # 設定ファイルを変更
            $modifiedConfig = $config1.PSObject.Copy()
            $modifiedConfig.file_paths.timezone = "UTC"
            $modifiedConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $script:TestConfigPath -Encoding UTF8
            
            # 強制リロード
            $config2 = Get-DataSyncConfig -ConfigPath $script:TestConfigPath -Force
            
            $config2.file_paths.timezone | Should -Be "UTC"
            $config1.file_paths.timezone | Should -Be "Asia/Tokyo"  # 元の値
        }
        
        It "should throw error when configuration file not found" {
            $nonExistentPath = Join-Path $script:TestEnv.TempDirectory.Path "nonexistent.json"
            
            { Get-DataSyncConfig -ConfigPath $nonExistentPath } | Should -Throw "*設定ファイルが見つかりません*"
        }
        
        It "should throw error when called without ConfigPath if not cached" {
            # キャッシュをクリア
            $script:DataSyncConfig = $null
            
            { Get-DataSyncConfig } | Should -Throw "*設定がまだ読み込まれていません*"
        }
    }
    
    Context "Configuration File Structure Validation" {
        It "should validate required file_paths section" {
            $config = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            $config.file_paths | Should -Not -BeNullOrEmpty
            $config.file_paths.provided_data_file_path | Should -Not -BeNullOrEmpty
            $config.file_paths.current_data_file_path | Should -Not -BeNullOrEmpty  
            $config.file_paths.output_file_path | Should -Not -BeNullOrEmpty
        }
        
        It "should validate required tables section" {
            $config = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            $config.tables | Should -Not -BeNullOrEmpty
            $config.tables.provided_data | Should -Not -BeNullOrEmpty
            $config.tables.current_data | Should -Not -BeNullOrEmpty
            
            # テーブル定義の詳細検証
            $providedTable = $config.tables.provided_data
            $providedTable.columns | Should -Not -BeNullOrEmpty
            $providedTable.csv_mapping | Should -Not -BeNullOrEmpty
        }
        
        It "should validate sync_config section" {
            $config = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            $config.sync_config | Should -Not -BeNullOrEmpty
            $config.sync_config.key_columns | Should -Not -BeNullOrEmpty
            $config.sync_config.comparison_columns | Should -Not -BeNullOrEmpty
            
            # キーカラムが配列であることを確認
            $config.sync_config.key_columns | Should -BeOfType [Array]
            $config.sync_config.comparison_columns | Should -BeOfType [Array]
        }
        
        It "should handle timezone configuration" {
            $config = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            $config.file_paths.timezone | Should -Not -BeNullOrEmpty
            $config.file_paths.timezone | Should -Match "(Asia/Tokyo|UTC|GMT)"
        }
    }
    
    Context "Real Configuration File Integration" {
        It "should load the actual project configuration file" {
            if (Test-Path $script:RealConfigPath) {
                $config = Get-DataSyncConfig -ConfigPath $script:RealConfigPath -Force
                
                $config | Should -Not -BeNullOrEmpty
                $config.file_paths | Should -Not -BeNullOrEmpty
                $config.tables | Should -Not -BeNullOrEmpty
                
                # 実際のプロジェクト設定の妥当性検証
                $config.tables.provided_data.columns.employee_id | Should -Not -BeNullOrEmpty
                $config.tables.current_data.columns.employee_id | Should -Not -BeNullOrEmpty
            } else {
                Set-TestInconclusive "実際の設定ファイルが見つかりません: $script:RealConfigPath"
            }
        }
        
        It "should validate real configuration has required employee data structure" {
            if (Test-Path $script:RealConfigPath) {
                $config = Get-DataSyncConfig -ConfigPath $script:RealConfigPath -Force
                
                # 従業員データに必要なカラムが定義されていることを確認
                $requiredColumns = @("employee_id", "name")
                foreach ($column in $requiredColumns) {
                    $config.tables.provided_data.columns.$column | Should -Not -BeNullOrEmpty
                    $config.tables.current_data.columns.$column | Should -Not -BeNullOrEmpty
                }
            } else {
                Set-TestInconclusive "実際の設定ファイルが見つかりません"
            }
        }
    }
    
    Context "Configuration Error Handling" {
        It "should handle malformed JSON gracefully" {
            $malformedConfigPath = Join-Path $script:TestEnv.TempDirectory.Path "malformed.json"
            "{ invalid json }" | Out-File -FilePath $malformedConfigPath -Encoding UTF8
            
            { Get-DataSyncConfig -ConfigPath $malformedConfigPath } | Should -Throw
        }
        
        It "should handle empty configuration file" {
            $emptyConfigPath = Join-Path $script:TestEnv.TempDirectory.Path "empty.json"
            "{}" | Out-File -FilePath $emptyConfigPath -Encoding UTF8
            
            $config = Get-DataSyncConfig -ConfigPath $emptyConfigPath -Force
            $config | Should -Not -BeNullOrEmpty
            # 空の設定でも読み込みは成功すべき（後続の処理で検証される）
        }
        
        It "should handle permission denied errors" {
            # PowerShellの制限により、実際のアクセス権限エラーはテスト困難
            # 代わりに読み取り専用ファイルで代替テスト
            $readOnlyPath = Join-Path $script:TestEnv.TempDirectory.Path "readonly.json"
            $testConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $readOnlyPath -Encoding UTF8
            
            try {
                # OS固有の読み取り専用設定
                if ($IsWindows) {
                    Set-ItemProperty -Path $readOnlyPath -Name IsReadOnly -Value $true
                } else {
                    chmod u-w $readOnlyPath
                }
                $config = Get-DataSyncConfig -ConfigPath $readOnlyPath -Force
                $config | Should -Not -BeNullOrEmpty  # 読み取り専用でも読み込み可能
            }
            finally {
                # 権限を復元
                if ($IsWindows) {
                    Set-ItemProperty -Path $readOnlyPath -Name IsReadOnly -Value $false -ErrorAction SilentlyContinue
                } else {
                    chmod u+w $readOnlyPath 2>/dev/null
                }
            }
        }
    }
    
    Context "Configuration Caching Behavior" {
        It "should maintain cache across multiple function calls" {
            # キャッシュクリア
            $script:DataSyncConfig = $null
            
            # 初回ロード
            $config1 = Get-DataSyncConfig -ConfigPath $script:TestConfigPath
            
            # 複数回のキャッシュアクセス
            $config2 = Get-DataSyncConfig
            $config3 = Get-DataSyncConfig
            $config4 = Get-DataSyncConfig
            
            $config1 | Should -Be $config2
            $config2 | Should -Be $config3
            $config3 | Should -Be $config4
        }
        
        It "should handle concurrent access to cached configuration" {
            # 設定を事前にロード
            Get-DataSyncConfig -ConfigPath $script:TestConfigPath | Out-Null
            
            # 並行アクセスのシミュレーション
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    Import-Module (Join-Path $using:PSScriptRoot "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1") -Force
                    Import-Module (Join-Path $using:PSScriptRoot "../../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1") -Force
                    
                    # キャッシュされた設定の読み込み（ConfigPathなし）
                    return (Get-DataSyncConfig).file_paths.timezone
                }
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results | Should -HaveCount 5
            $results | Should -Not -Contain $null
            $results | ForEach-Object { $_ | Should -Be "Asia/Tokyo" }
        }
    }
    
    Context "UTF-8 Encoding Support" {
        It "should handle UTF-8 encoded configuration files" {
            $utf8ConfigPath = Join-Path $script:TestEnv.TempDirectory.Path "utf8-config.json"
            
            # 日本語を含む設定を作成
            $utf8Config = New-MockConfiguration
            $utf8Config.tables.provided_data.columns.name.description = "従業員名（日本語対応）"
            $utf8Config.tables.provided_data.columns.department.description = "部署名（UTF-8テスト）"
            
            $utf8Config | ConvertTo-Json -Depth 10 | Out-File -FilePath $utf8ConfigPath -Encoding UTF8
            
            $config = Get-DataSyncConfig -ConfigPath $utf8ConfigPath -Force
            $config.tables.provided_data.columns.name.description | Should -Be "従業員名（日本語対応）"
            $config.tables.provided_data.columns.department.description | Should -Be "部署名（UTF-8テスト）"
        }
        
        It "should handle BOM in UTF-8 files" {
            $bomConfigPath = Join-Path $script:TestEnv.TempDirectory.Path "bom-config.json"
            
            # BOM付きUTF-8ファイルの作成
            $utf8WithBom = [System.Text.UTF8Encoding]::new($true)
            $configJson = (New-MockConfiguration | ConvertTo-Json -Depth 10)
            [System.IO.File]::WriteAllText($bomConfigPath, $configJson, $utf8WithBom)
            
            $config = Get-DataSyncConfig -ConfigPath $bomConfigPath -Force
            $config | Should -Not -BeNullOrEmpty
            $config.file_paths | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Configuration Validation and Defaults" {
        It "should provide reasonable defaults for missing optional fields" {
            $minimalConfig = @{
                file_paths = @{
                    provided_data_file_path = "test.csv"
                    current_data_file_path = "current.csv"
                    output_file_path = "output.csv"
                }
                tables = @{
                    provided_data = @{
                        columns = @{
                            employee_id = @{ type = "TEXT"; primary_key = $true }
                        }
                    }
                    current_data = @{
                        columns = @{
                            employee_id = @{ type = "TEXT"; primary_key = $true }
                        }
                    }
                }
            }
            
            $minimalConfigPath = Join-Path $script:TestEnv.TempDirectory.Path "minimal-config.json"
            $minimalConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath $minimalConfigPath -Encoding UTF8
            
            $config = Get-DataSyncConfig -ConfigPath $minimalConfigPath -Force
            $config | Should -Not -BeNullOrEmpty
            
            # 最低限の設定でも読み込みできることを確認
            $config.file_paths.provided_data_file_path | Should -Be "test.csv"
            $config.tables.provided_data.columns.employee_id | Should -Not -BeNullOrEmpty
        }
    }
}