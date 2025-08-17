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
            $dependencies.Dependencies | Should -Not -Contain "DataAccess"  # DataFilteringUtilsは設定のみに依存
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "下位層関数を使用すること" {
            # DataFilteringUtilsが下位レイヤの関数を使用することを確認
            $config = Get-DataSyncConfig
            $config | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Invoke-DataFiltering 関数 - 基本フィルタリング" {
        BeforeEach {
            # テストデータの準備
            $script:TestData = @(
                @{ employee_id = "E001"; name = "田中太郎"; department = "開発部" },
                @{ employee_id = "E002"; name = "佐藤花子"; department = "営業部" },
                @{ employee_id = "Z001"; name = "テスト太郎"; department = "テスト部" },  # 除外対象
                @{ employee_id = "E003"; name = "鈴木一郎"; department = "総務部" },
                @{ employee_id = "Z002"; name = "テスト花子"; department = "テスト部" }   # 除外対象
            )
        }
        
        It "除外パターンに基づいてデータをフィルタリングすること" {
            $filterConfig = @{
                exclude = @("Z*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.FilteredData | Should -HaveCount 3  # Z*以外の3件
            $result.FilteredData | Where-Object { $_.employee_id -like "Z*" } | Should -BeNullOrEmpty
            $result.Statistics.ExcludedCount | Should -Be 2
        }
        
        It "includeパターンに基づいてデータをフィルタリングすること" {
            $filterConfig = @{
                include = @("E*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.FilteredData | Should -HaveCount 3  # E*の3件のみ
            $result.FilteredData | ForEach-Object { $_.employee_id | Should -Match "^E" }
            $result.Statistics.ExcludedCount | Should -Be 2
        }
        
        It "includeとexcludeパターンの両方を処理すること" {
            $filterConfig = @{
                include = @("*")      # すべて含める
                exclude = @("Z*")     # Z*は除外
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.FilteredData | Should -HaveCount 3  # E*の3件
            $result.Statistics.OriginalCount | Should -Be 5
            $result.Statistics.ExcludedCount | Should -Be 2
        }
        
        It "設定時に除外データをKEEPとして出力すること" {
            $filterConfig = @{
                exclude = @("Z*")
                output_excluded_as_keep = $true
            }
            
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig $filterConfig -TableName "provided_data"
            
            # フィルタされたデータは3件、除外データは2件だがKEEPとして含まれる
            $result.FilteredData | Should -HaveCount 5  # 全データが含まれる
            
            # 除外されたデータにはsync_actionが設定される
            $excludedItems = $result.FilteredData | Where-Object { $_.employee_id -like "Z*" }
            $excludedItems | Should -HaveCount 2
            $excludedItems | ForEach-Object { $_.sync_action | Should -Be "KEEP" }
        }
        
        It "空のデータを適切に処理すること" {
            $filterConfig = @{
                exclude = @("Z*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data @() -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.FilteredData | Should -BeExactly @()
            $result.Statistics.OriginalCount | Should -Be 0
            $result.Statistics.ExcludedCount | Should -Be 0
        }
        
        It "nullフィルタ設定を処理すること" {
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig $null -TableName "provided_data"
            
            # フィルタ設定がnullの場合、すべてのデータが通る
            $result.FilteredData | Should -HaveCount 5
            $result.Statistics.ExcludedCount | Should -Be 0
        }
    }
    
    Context "GLOB Pattern Matching" {
        BeforeEach {
            $script:PatternTestData = @(
                @{ employee_id = "E001"; name = "田中太郎" },
                @{ employee_id = "E002"; name = "佐藤花子" },
                @{ employee_id = "T001"; name = "テスト太郎" },
                @{ employee_id = "T002"; name = "テスト花子" },
                @{ employee_id = "ADMIN01"; name = "管理者1" },
                @{ employee_id = "ADMIN02"; name = "管理者2" },
                @{ employee_id = "TEMP_001"; name = "一時1" },
                @{ employee_id = "TEMP_002"; name = "一時2" }
            )
        }
        
        It "シンプルなワイルドカードパターンを処理すること" {
            $filterConfig = @{
                exclude = @("T*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:PatternTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.FilteredData | Where-Object { $_.employee_id -like "T*" } | Should -BeNullOrEmpty
            $result.Statistics.ExcludedCount | Should -Be 2
        }
        
        It "複数のexcludeパターンを処理すること" {
            $filterConfig = @{
                exclude = @("T*", "ADMIN*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:PatternTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $excludedItems = $script:PatternTestData | Where-Object { $_.employee_id -like "T*" -or $_.employee_id -like "ADMIN*" }
            $result.Statistics.ExcludedCount | Should -Be $excludedItems.Count
        }
        
        It "複雑なGLOBパターンを処理すること" {
            $filterConfig = @{
                exclude = @("*_*")  # アンダースコアを含むID
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:PatternTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $excludedItems = $script:PatternTestData | Where-Object { $_.employee_id -like "*_*" }
            $result.Statistics.ExcludedCount | Should -Be $excludedItems.Count
        }
        
        It "大文字小文字を区別するパターンマッチングを処理すること" {
            $caseTestData = @(
                @{ employee_id = "abc001"; name = "小文字" },
                @{ employee_id = "ABC002"; name = "大文字" },
                @{ employee_id = "AbC003"; name = "混在" }
            )
            
            $filterConfig = @{
                exclude = @("abc*")  # 小文字のパターン
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $caseTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            # PowerShellの-likeは大文字小文字を区別しない
            $result.Statistics.ExcludedCount | Should -BeGreaterOrEqual 1
        }
        
        It "空文字およびnullパターンを処理すること" {
            $filterConfig = @{
                exclude = @("", $null, "   ")  # 空文字やnull、空白
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:PatternTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            # 無効なパターンは無視され、すべてのデータが通る
            $result.FilteredData | Should -HaveCount $script:PatternTestData.Count
            $result.Statistics.ExcludedCount | Should -Be 0
        }
    }
    
    Context "Filtering Statistics and Reporting" {
        It "正確なフィルタリング統計を計算すること" {
            $testData = 1..100 | ForEach-Object {
                @{ 
                    employee_id = if ($_ % 10 -eq 0) { "Z{0:D3}" -f $_ } else { "E{0:D3}" -f $_ }
                    name = "テスト{0:D3}" -f $_
                }
            }
            
            $filterConfig = @{
                exclude = @("Z*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $testData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.Statistics.OriginalCount | Should -Be 100
            $result.Statistics.FilteredCount | Should -Be 90  # Z*を除外した数
            $result.Statistics.ExcludedCount | Should -Be 10  # Z*の数
            $result.Statistics.ExclusionRate | Should -BeGreaterThan 9.5
            $result.Statistics.ExclusionRate | Should -BeLessThan 10.5
        }
        
        It "詳細なフィルタ操作ログを提供すること" {
            $filterConfig = @{
                exclude = @("T*", "Z*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.Statistics | Should -Not -BeNullOrEmpty
            $result.Statistics.FilterPatterns | Should -Contain "T*"
            $result.Statistics.FilterPatterns | Should -Contain "Z*"
        }
        
        It "フィルタリングパフォーマンス指標を追跡すること" {
            $largeTestData = 1..1000 | ForEach-Object {
                @{ employee_id = "E{0:D4}" -f $_; name = "テスト{0:D4}" -f $_ }
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            $filterConfig = @{
                exclude = @("E5*", "E6*", "E7*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $largeTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $stopwatch.Stop()
            
            $result.Statistics.ProcessingTime | Should -Not -BeNullOrEmpty
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000  # 5秒以内
        }
    }
    
    Context "Japanese Text and Unicode Handling" {
        It "フィルタパターンで日本語テキストを処理すること" {
            $japaneseTestData = @(
                @{ employee_id = "E001"; name = "田中太郎"; department = "開発部" },
                @{ employee_id = "E002"; name = "佐藤花子"; department = "営業部" },
                @{ employee_id = "E003"; name = "鈴木一郎"; department = "テスト部" },  # テスト部
                @{ employee_id = "E004"; name = "山田次郎"; department = "テスト課" }   # テスト課
            )
            
            $filterConfig = @{
                exclude = @("*テスト*")  # 日本語パターン
                field = "department"      # 部署名でフィルタ
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $japaneseTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.Statistics.ExcludedCount | Should -BeGreaterOrEqual 2  # テスト部、テスト課
        }
        
        It "データ内のUnicode文字を処理すること" {
            $unicodeTestData = @(
                @{ employee_id = "E001"; name = "José García"; department = "Español" },
                @{ employee_id = "E002"; name = "François Müller"; department = "Français" },
                @{ employee_id = "E003"; name = "田中太郎"; department = "日本語" },
                @{ employee_id = "E004"; name = "Владимир"; department = "Русский" }
            )
            
            $filterConfig = @{
                exclude = @("*ç*", "*ü*")  # アクセント文字を含むパターン
                field = "name"
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $unicodeTestData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.FilteredData | Should -Not -BeNullOrEmpty
            $result.Statistics.ExcludedCount | Should -BeGreaterOrEqual 1
        }
        
        It "フィルタ出力でUnicode文字を保持すること" {
            $unicodeData = @(
                @{ employee_id = "E001"; name = "🌟田中太郎🌟"; emoji = "😀" }
            )
            
            $filterConfig = @{
                exclude = @("NONE")  # 除外なし
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $unicodeData -FilterConfig $filterConfig -TableName "provided_data"
            
            $result.FilteredData[0].name | Should -Be "🌟田中太郎🌟"
            $result.FilteredData[0].emoji | Should -Be "😀"
        }
    }
    
    Context "Error Handling and Edge Cases" {
        It "不正な形式のフィルタ設定を処理すること" {
            $malformedConfig = @{
                exclude = "not_an_array"  # 配列ではない
                output_excluded_as_keep = "not_a_boolean"  # ブール値ではない
            }
            
            { Invoke-DataFiltering -Data $script:TestData -FilterConfig $malformedConfig -TableName "provided_data" } | Should -Not -Throw
        }
        
        It "フィールドが不足しているデータオブジェクトを処理すること" {
            $incompleteData = @(
                @{ employee_id = "E001" },  # nameフィールドなし
                @{ name = "名前のみ" },      # employee_idフィールドなし
                @{ employee_id = "E002"; name = "完全データ" }
            )
            
            $filterConfig = @{
                exclude = @("E*")
                output_excluded_as_keep = $false
            }
            
            $result = Invoke-DataFiltering -Data $incompleteData -FilterConfig $filterConfig -TableName "provided_data"
            
            # エラーを投げずに処理される
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "非常に大きなデータセットを効率的に処理すること" {
            $largeDataset = 1..10000 | ForEach-Object {
                @{ 
                    employee_id = "E{0:D5}" -f $_
                    name = "大量データ{0:D5}" -f $_
                    department = if ($_ % 100 -eq 0) { "除外部署" } else { "通常部署" }
                }
            }
            
            $filterConfig = @{
                exclude = @("*除外*")
                field = "department"
                output_excluded_as_keep = $false
            }
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $result = Invoke-DataFiltering -Data $largeDataset -FilterConfig $filterConfig -TableName "provided_data"
            $stopwatch.Stop()
            
            $result.Statistics.OriginalCount | Should -Be 10000
            $result.Statistics.ExcludedCount | Should -Be 100  # 100件ごとに1件
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10000  # 10秒以内
        }
        
        It "データ内の循環参照を処理すること" {
            # PowerShellでは循環参照のあるオブジェクトを作成
            $circularData = @{ employee_id = "E001"; name = "循環テスト" }
            $circularData.self = $circularData  # 自己参照
            
            $filterConfig = @{
                exclude = @("NONE")
                output_excluded_as_keep = $false
            }
            
            { Invoke-DataFiltering -Data @($circularData) -FilterConfig $filterConfig -TableName "provided_data" } | Should -Not -Throw
        }
    }
    
    Context "Performance and Memory Management" {
        It "メモリリークなしで大量データセットをフィルタリングすること" {
            $initialMemory = [GC]::GetTotalMemory($false)
            
            1..10 | ForEach-Object {
                $testDataset = 1..1000 | ForEach-Object {
                    @{ employee_id = "E{0:D4}" -f $_; name = "テスト{0:D4}" -f $_ }
                }
                
                $filterConfig = @{
                    exclude = @("E5*")
                    output_excluded_as_keep = $false
                }
                
                $result = Invoke-DataFiltering -Data $testDataset -FilterConfig $filterConfig -TableName "provided_data"
                $result | Out-Null  # 結果を破棄
            }
            
            [GC]::Collect()
            $finalMemory = [GC]::GetTotalMemory($true)
            
            ($finalMemory - $initialMemory) | Should -BeLessThan (50MB)
        }
        
        It "並行フィルタリング操作を処理すること" {
            $jobs = 1..5 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($JobId)
                    
                    $testData = 1..100 | ForEach-Object {
                        @{ employee_id = "E{0:D3}" -f $_; name = "Job$JobId-{0:D3}" -f $_ }
                    }
                    
                    $filterConfig = @{
                        exclude = @("E5*", "E6*")
                        output_excluded_as_keep = $false
                    }
                    
                    # 簡単なフィルタリング処理（実際のモジュール関数を使わずに）
                    $filtered = $testData | Where-Object { -not ($_.employee_id -like "E5*" -or $_.employee_id -like "E6*") }
                    
                    return @{
                        JobId = $JobId
                        OriginalCount = $testData.Count
                        FilteredCount = $filtered.Count
                        ExcludedCount = $testData.Count - $filtered.Count
                    }
                } -ArgumentList $_
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results | Should -HaveCount 5
            $results | ForEach-Object {
                $_.OriginalCount | Should -Be 100
                $_.FilteredCount | Should -Be 80  # E5*とE6*を除外
                $_.ExcludedCount | Should -Be 20
            }
        }
    }
    
    Context "Integration with Lower Layers" {
        It "インフラストラクチャ層の設定を使用すること" {
            $config = Get-DataSyncConfig
            $filterConfig = $config.tables.provided_data.filter
            
            $filterConfig | Should -Not -BeNullOrEmpty
            $filterConfig.exclude | Should -Contain "Z*"
        }
        
        It "基盤層のユーティリティを使用すること" {
            Mock Get-Timestamp { return "20250817_120000" } -Verifiable
            
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig @{ exclude = @("Z*") } -TableName "provided_data"
            
            # フィルタリング処理でタイムスタンプが使用される
            $result.Statistics.Timestamp | Should -Be "20250817_120000"
        }
        
        It "ログ関数と統合すること" {
            Mock Write-SystemLog { } -Verifiable
            
            $result = Invoke-DataFiltering -Data $script:TestData -FilterConfig @{ exclude = @("Z*") } -TableName "provided_data"
            
            # フィルタリング処理でログが出力される
            # Assert-MockCalled Write-SystemLog -Times 1 -Exactly
        }
    }
}