#!/usr/bin/env pwsh
# データ処理層 (Layer 4) - DataFilteringUtils モジュールテスト

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 4 (DataProcessing) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "DataProcessing" -ModuleName "DataFilteringUtils"
    
    # モック設定とテストデータ
    $script:TestEnv.ConfigurationMock = New-MockConfiguration
    
    # テスト用一時ディレクトリとデータベース
    $script:TestDatabasePath = Join-Path $script:TestEnv.TempDirectory.Path "test.db"
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "DataFilteringUtils (データ処理層) テスト" {
    
    Context "レイヤーアーキテクチャ検証" {
        It "Layer 4 ですべての下位層依存関係を持つこと" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "DataProcessing" -ModuleName "DataFilteringUtils"
            $dependencies.Dependencies | Should -Contain "Foundation"
            $dependencies.Dependencies | Should -Contain "Infrastructure"
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "下位層関数を使用すること" {
            # DataFilteringUtilsが下位レイヤの関数を使用することを確認
            $config = Get-DataSyncConfig
            $config | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "New-TempTableName 関数" {
        It "ベーステーブル名から一時テーブル名を生成すること" {
            $tempName = New-TempTableName -BaseTableName "provided_data"
            $tempName | Should -Be "provided_data_temp"
        }
        
        It "異なるテーブル名でも正しく生成すること" {
            $tempName = New-TempTableName -BaseTableName "sync_result"
            $tempName | Should -Be "sync_result_temp"
        }
        
        It "空白を含むテーブル名を適切に処理すること" {
            $tempName = New-TempTableName -BaseTableName "test table"
            $tempName | Should -Be "test table_temp"
        }
    }
    
    Context "Show-FilteringStatistics 関数" {
        BeforeEach {
            # 出力をキャプチャするためのストリーム準備
            $script:CapturedOutput = @()
        }
        
        It "フィルタ適用時の統計を正しく表示すること" {
            # モック関数でログ出力をキャプチャ
            Mock Write-SystemLog { 
                $script:CapturedOutput += $Message 
            } -ModuleName "DataFilteringUtils"
            
            Show-FilteringStatistics -TableName "test_table" -TotalCount 100 -FilteredCount 80 -WhereClause "id NOT LIKE 'Z%'"
            
            $script:CapturedOutput | Should -Contain "データフィルタ処理結果: test_table"
            $script:CapturedOutput | Should -Contain "総件数: 100"
            $script:CapturedOutput | Should -Contain "通過件数: 80 (通過率: 80%)"
            $script:CapturedOutput | Should -Contain "除外件数: 20"
        }
        
        It "フィルタなしの場合の統計を正しく表示すること" {
            Mock Write-SystemLog { 
                $script:CapturedOutput += $Message 
            } -ModuleName "DataFilteringUtils"
            
            Show-FilteringStatistics -TableName "test_table" -TotalCount 50 -FilteredCount 50
            
            $script:CapturedOutput | Should -Contain "適用フィルタ: なし（全件通過）"
            $script:CapturedOutput | Should -Contain "処理件数: 50"
        }
        
        It "ゼロ件データの統計を正しく処理すること" {
            Mock Write-SystemLog { 
                $script:CapturedOutput += $Message 
            } -ModuleName "DataFilteringUtils"
            
            Show-FilteringStatistics -TableName "empty_table" -TotalCount 0 -FilteredCount 0
            
            $script:CapturedOutput | Should -Contain "処理件数: 0"
        }
    }
    
    Context "Save-ExcludedDataForKeep 関数 - 統合テスト" {
        BeforeEach {
            # テスト用データベースの初期化
            if (Test-Path $script:TestDatabasePath) {
                Remove-Item $script:TestDatabasePath -Force
            }
            
            # テーブル作成
            $createTableSql = @"
CREATE TABLE test_source (
    id INTEGER PRIMARY KEY,
    employee_id TEXT NOT NULL,
    name TEXT NOT NULL
);
"@
            Invoke-SqliteCommand -DatabasePath $script:TestDatabasePath -Query $createTableSql
            
            # テストデータ挿入
            $insertSql = @"
INSERT INTO test_source (employee_id, name) VALUES 
('E001', '田中太郎'),
('E002', '佐藤花子'),
('Z001', 'テスト太郎'),
('Z002', 'テスト花子');
"@
            Invoke-SqliteCommand -DatabasePath $script:TestDatabasePath -Query $insertSql
        }
        
        It "除外データのテーブル保存が正常に動作すること" {
            # モック関数を設定
            Mock New-FilterWhereClause { 
                return "employee_id NOT LIKE 'Z%'" 
            } -ModuleName "DataFilteringUtils"
            
            Mock New-CreateTempTableSql { 
                return "CREATE TABLE test_excluded AS SELECT * FROM test_source WHERE 1=0;" 
            } -ModuleName "DataFilteringUtils"
            
            Mock Get-CsvColumns { 
                return @("employee_id", "name") 
            } -ModuleName "DataFilteringUtils"
            
            # テスト実行
            { Save-ExcludedDataForKeep -DatabasePath $script:TestDatabasePath -SourceTableName "test_source" -ExcludedTableName "test_excluded" -FilterConfigTableName "test_source" } | Should -Not -Throw
            
            # 結果確認：除外データが保存されているか
            $excludedData = Invoke-SqliteCommand -DatabasePath $script:TestDatabasePath -Query "SELECT COUNT(*) as count FROM test_excluded;"
            $excludedData[0].count | Should -BeGreaterThan 0
        }
        
        It "フィルタ条件がない場合にスキップすること" {
            Mock New-FilterWhereClause { 
                return "" 
            } -ModuleName "DataFilteringUtils"
            
            Mock Write-SystemLog { 
                $script:CapturedOutput += $Message 
            } -ModuleName "DataFilteringUtils"
            
            Save-ExcludedDataForKeep -DatabasePath $script:TestDatabasePath -SourceTableName "test_source" -ExcludedTableName "test_excluded" -FilterConfigTableName "test_source"
            
            $script:CapturedOutput | Should -Contain "フィルタ条件がないため、除外データ保存をスキップします: test_source"
        }
    }
    
    Context "エラーハンドリングと境界値テスト" {
        It "New-TempTableName が必須パラメータを要求すること" {
            { New-TempTableName -BaseTableName $null } | Should -Throw
        }
        
        It "Show-FilteringStatistics が無効なパラメータで例外を発生すること" {
            # 空文字列パラメータで例外が発生することを確認
            { Show-FilteringStatistics -TableName "" -TotalCount -1 -FilteredCount -1 } | Should -Throw
            
            # 有効なパラメータでは正常動作することを確認
            Mock Write-SystemLog { } -ModuleName "DataFilteringUtils"
            { Show-FilteringStatistics -TableName "valid_table" -TotalCount 0 -FilteredCount 0 } | Should -Not -Throw
        }
        
        It "統計計算で正しい比率を計算すること" {
            Mock Write-SystemLog { 
                $script:CapturedOutput += $Message 
            } -ModuleName "DataFilteringUtils"
            
            # 66.7%のケース
            Show-FilteringStatistics -TableName "test" -TotalCount 3 -FilteredCount 2 -WhereClause "test_filter"
            $script:CapturedOutput -join " " | Should -Match "通過率: 66\.7%"
        }
    }
    
    Context "パフォーマンステスト" {
        It "大量データでのShow-FilteringStatisticsが効率的に動作すること" {
            Mock Write-SystemLog { } -ModuleName "DataFilteringUtils"
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            Show-FilteringStatistics -TableName "large_table" -TotalCount 100000 -FilteredCount 80000 -WhereClause "complex_filter"
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000  # 1秒以内
        }
    }
    
    Context "統合テストシナリオ" {
        It "基盤層のユーティリティを使用すること" {
            # Get-Timestampの動作確認
            $timestamp = Get-Timestamp
            $timestamp | Should -Not -BeNullOrEmpty
            $timestamp | Should -Match "^\d{8}_\d{6}$"
        }
        
        It "ログ機能が正常に動作すること" {
            Mock Write-SystemLog { 
                $script:CapturedOutput += "$Level`: $Message" 
            } -ModuleName "DataFilteringUtils"
            
            Show-FilteringStatistics -TableName "integration_test" -TotalCount 10 -FilteredCount 8
            
            $script:CapturedOutput | Where-Object { $_ -match "Info:" } | Should -Not -BeNullOrEmpty
        }
    }
}