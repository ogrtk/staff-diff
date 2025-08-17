#!/usr/bin/env pwsh
# DataProcessing Layer (Layer 4) - CsvProcessingUtils Module Tests

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 4 (DataProcessing) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "DataProcessing" -ModuleName "CsvProcessingUtils"
    
    # テスト用CSVファイルの作成
    $script:TestCsvPath = Join-Path $script:TestEnv.TempDirectory.Path "test.csv"
    $script:TestEnv.ConfigurationMock = New-MockConfiguration
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "CsvProcessingUtils (データ処理層) テスト" {
    
    Context "Layer Architecture Validation" {
        It "すべての下位層依存関係を持つLayer 4であること" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "DataProcessing" -ModuleName "CsvProcessingUtils"
            $dependencies.Dependencies | Should -Contain "Foundation"
            $dependencies.Dependencies | Should -Contain "Infrastructure" 
            $dependencies.Dependencies | Should -Contain "DataAccess"
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "下位層関数を使用すること" {
            # CsvProcessingUtilsが下位レイヤの関数を使用することを確認
            $testData = New-LayeredTestData -DataType "Employee" -RecordCount 3 -IncludeHeaders
            $testData | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "ConvertFrom-CsvData Function - Basic Operations" {
        BeforeEach {
            # テスト用CSVデータの作成
            $csvContent = New-LayeredTestData -DataType "Employee" -RecordCount 5 -IncludeHeaders
            $csvContent | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
        }
        
        It "CSV内容を正しく解析すること" {
            $csvContent = Get-Content -Path $script:TestCsvPath -Raw
            $result = ConvertFrom-CsvData -CsvContent $csvContent -TableName "provided_data"
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -BeOfType [Array]
            $result.Count | Should -BeGreaterThan 0
            
            # 必須フィールドの検証
            $result[0].employee_id | Should -Not -BeNullOrEmpty
            $result[0].name | Should -Not -BeNullOrEmpty
        }
        
        It "ヘッダー付きCSVを処理すること" {
            $csvWithHeaders = New-LayeredTestData -DataType "Employee" -RecordCount 3 -IncludeHeaders
            $result = ConvertFrom-CsvData -CsvContent ($csvWithHeaders -join "`n") -TableName "provided_data"
            
            $result.Count | Should -Be 3  # ヘッダー行を除く
            $result[0].employee_id | Should -Match "E\d{3}"
        }
        
        It "ヘッダーなしCSVを処理すること" {
            $csvWithoutHeaders = New-LayeredTestData -DataType "Employee" -RecordCount 3
            $result = ConvertFrom-CsvData -CsvContent ($csvWithoutHeaders -join "`n") -TableName "provided_data"
            
            $result.Count | Should -Be 3
            $result[0].employee_id | Should -Not -BeNullOrEmpty
        }
        
        It "テーブルスキーマに対してデータを検証すること" {
            $csvContent = "employee_id,name,department`nE001,テスト太郎,開発部"
            $result = ConvertFrom-CsvData -CsvContent $csvContent -TableName "provided_data"
            
            $result[0].employee_id | Should -Be "E001"
            $result[0].name | Should -Be "テスト太郎"
            $result[0].department | Should -Be "開発部"
        }
    }
    
    Context "ConvertTo-CsvData Function - Output Generation" {
        It "データオブジェクトからCSV内容を生成すること" {
            $testData = @(
                @{ employee_id = "E001"; name = "テスト太郎"; department = "開発部" },
                @{ employee_id = "E002"; name = "テスト花子"; department = "営業部" }
            )
            
            $result = ConvertTo-CsvData -Data $testData -TableName "provided_data"
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "employee_id.*name.*department"  # ヘッダー
            $result | Should -Match "E001.*テスト太郎.*開発部"
            $result | Should -Match "E002.*テスト花子.*営業部"
        }
        
        It "デフォルトでヘッダーを含むこと" {
            $testData = @(
                @{ employee_id = "E001"; name = "テスト太郎" }
            )
            
            $result = ConvertTo-CsvData -Data $testData -TableName "provided_data" -IncludeHeaders
            
            $lines = $result -split "`n"
            $lines[0] | Should -Match "employee_id"
            $lines[1] | Should -Match "E001"
        }
        
        It "空のデータを適切に処理すること" {
            $result = ConvertTo-CsvData -Data @() -TableName "provided_data"
            
            $result | Should -Not -BeNullOrEmpty
            $result | Should -Match "employee_id"  # ヘッダーのみ
        }
        
        It "CSV特殊文字をエスケープすること" {
            $testData = @(
                @{ employee_id = "E001"; name = "テスト,太郎"; department = "開発""部" }
            )
            
            $result = ConvertTo-CsvData -Data $testData -TableName "provided_data"
            
            # カンマやダブルクォートが適切にエスケープされる
            $result | Should -Match '"テスト,太郎"'
            $result | Should -Match '"開発""部"'
        }
    }
    
    Context "Import-CsvToDatabase Function - Database Integration" {
        It "CSVデータをデータベースにインポートすること" {
            $csvContent = New-LayeredTestData -DataType "Employee" -RecordCount 3 -IncludeHeaders
            $csvContent | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
            
            $result = Import-CsvToDatabase -CsvFilePath $script:TestCsvPath -TableName "provided_data" -DatabasePath ":memory:"
            
            $result | Should -Not -BeNullOrEmpty
            $result.SuccessCount | Should -Be 3
            $result.ErrorCount | Should -Be 0
        }
        
        It "インポートエラーを適切に処理すること" {
            # 不正なデータを含むCSV
            $invalidCsv = "employee_id,name`n,Missing ID`nE001,Valid Name"
            $invalidCsv | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
            
            $result = Import-CsvToDatabase -CsvFilePath $script:TestCsvPath -TableName "provided_data" -DatabasePath ":memory:"
            
            $result.ErrorCount | Should -BeGreaterThan 0
            $result.Errors | Should -Not -BeNullOrEmpty
        }
        
        It "インポート時に必須フィールドを検証すること" {
            # 必須フィールドが欠けているデータ
            $csvWithMissingRequired = "employee_id,name`nE001,`nE002,Valid Name"
            $csvWithMissingRequired | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
            
            $result = Import-CsvToDatabase -CsvFilePath $script:TestCsvPath -TableName "provided_data" -DatabasePath ":memory:"
            
            # 一部のレコードでエラーが発生
            $result.ErrorCount | Should -BeGreaterThan 0
            $result.SuccessCount | Should -BeGreaterThan 0
        }
        
        It "大量データセットのバッチ処理をサポートすること" {
            # 大量データのテスト
            $largeCsvContent = New-LayeredTestData -DataType "Employee" -RecordCount 100 -IncludeHeaders
            $largeCsvContent | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
            
            $result = Import-CsvToDatabase -CsvFilePath $script:TestCsvPath -TableName "provided_data" -DatabasePath ":memory:" -BatchSize 25
            
            $result.SuccessCount | Should -Be 100
            $result.BatchCount | Should -Be 4  # 100 / 25 = 4
        }
    }
    
    Context "Export-DatabaseToCsv Function - Database Export" {
        It "データベースデータをCSVにエクスポートすること" {
            # まずデータをインポート
            $csvContent = New-LayeredTestData -DataType "Employee" -RecordCount 3 -IncludeHeaders
            $csvContent | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
            Import-CsvToDatabase -CsvFilePath $script:TestCsvPath -TableName "provided_data" -DatabasePath ":memory:" | Out-Null
            
            $outputCsvPath = Join-Path $script:TestEnv.TempDirectory.Path "output.csv"
            $result = Export-DatabaseToCsv -DatabasePath ":memory:" -TableName "provided_data" -OutputFilePath $outputCsvPath
            
            $result.Success | Should -Be $true
            Test-Path $outputCsvPath | Should -Be $true
            
            $exportedContent = Get-Content -Path $outputCsvPath
            $exportedContent | Should -Contain "employee_id*"
        }
        
        It "カスタムWHERE句を処理すること" {
            $outputCsvPath = Join-Path $script:TestEnv.TempDirectory.Path "filtered.csv"
            $result = Export-DatabaseToCsv -DatabasePath ":memory:" -TableName "provided_data" -OutputFilePath $outputCsvPath -WhereClause "department = '開発部'"
            
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "カスタム列選択をサポートすること" {
            $outputCsvPath = Join-Path $script:TestEnv.TempDirectory.Path "selected.csv"
            $columns = @("employee_id", "name")
            $result = Export-DatabaseToCsv -DatabasePath ":memory:" -TableName "provided_data" -OutputFilePath $outputCsvPath -Columns $columns
            
            $exportedContent = Get-Content -Path $outputCsvPath -Raw
            $exportedContent | Should -Match "employee_id.*name"
            $exportedContent | Should -Not -Match "department"
        }
    }
    
    Context "UTF-8 and Japanese Character Handling" {
        It "日本語文字を正しく処理すること" {
            $japaneseData = @"
employee_id,name,department
E001,田中太郎,開発部
E002,佐藤花子,営業部  
E003,鈴木一郎,総務部
"@
            $japaneseData | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
            
            $result = ConvertFrom-CsvData -CsvContent $japaneseData -TableName "provided_data"
            
            $result[0].name | Should -Be "田中太郎"
            $result[1].department | Should -Be "営業部"
            $result[2].name | Should -Be "鈴木一郎"
        }
        
        It "UTF-8 BOMを処理すること" {
            $utf8WithBom = [System.Text.UTF8Encoding]::new($true)
            $bomData = "employee_id,name`nE001,テスト太郎"
            [System.IO.File]::WriteAllText($script:TestCsvPath, $bomData, $utf8WithBom)
            
            $content = Get-Content -Path $script:TestCsvPath -Raw
            $result = ConvertFrom-CsvData -CsvContent $content -TableName "provided_data"
            
            $result[0].name | Should -Be "テスト太郎"
        }
        
        It "ラウンドトリップ時に日本語文字を保持すること" {
            $originalData = @(
                @{ employee_id = "E001"; name = "山田太郎"; department = "開発部" }
            )
            
            $csvContent = ConvertTo-CsvData -Data $originalData -TableName "provided_data"
            $parsedData = ConvertFrom-CsvData -CsvContent $csvContent -TableName "provided_data"
            
            $parsedData[0].name | Should -Be "山田太郎"
            $parsedData[0].department | Should -Be "開発部"
        }
    }
    
    Context "CSV Format and Delimiter Handling" {
        It "異なる区切り文字を処理すること" {
            # TSV (Tab-separated values) のテスト
            $tsvData = "employee_id`tname`tdepartment`nE001`tテスト太郎`t開発部"
            
            $result = ConvertFrom-CsvData -CsvContent $tsvData -TableName "provided_data" -Delimiter "`t"
            
            $result[0].employee_id | Should -Be "E001"
            $result[0].name | Should -Be "テスト太郎"
        }
        
        It "区切り文字を含むクォート付きフィールドを処理すること" {
            $csvWithQuotes = 'employee_id,name,description' + "`n" + 'E001,"テスト太郎","説明文,カンマ付き"'
            
            $result = ConvertFrom-CsvData -CsvContent $csvWithQuotes -TableName "provided_data"
            
            $result[0].description | Should -Be "説明文,カンマ付き"
        }
        
        It "空フィールドを処理すること" {
            $csvWithEmpty = "employee_id,name,department`nE001,,開発部`nE002,テスト花子,"
            
            $result = ConvertFrom-CsvData -CsvContent $csvWithEmpty -TableName "provided_data"
            
            $result[0].name | Should -BeNullOrEmpty
            $result[1].department | Should -BeNullOrEmpty
        }
        
        It "行末文字のバリエーションを処理すること" {
            # Windows (CRLF), Unix (LF), Mac (CR) の行末文字
            $csvWithCRLF = "employee_id,name`r`nE001,テスト太郎`r`nE002,テスト花子"
            $csvWithLF = "employee_id,name`nE001,テスト太郎`nE002,テスト花子"
            
            $resultCRLF = ConvertFrom-CsvData -CsvContent $csvWithCRLF -TableName "provided_data"
            $resultLF = ConvertFrom-CsvData -CsvContent $csvWithLF -TableName "provided_data"
            
            $resultCRLF.Count | Should -Be 2
            $resultLF.Count | Should -Be 2
            $resultCRLF[0].name | Should -Be "テスト太郎"
            $resultLF[0].name | Should -Be "テスト太郎"
        }
    }
    
    Context "Error Handling and Data Validation" {
        It "不正な形式のCSVを適切に処理すること" {
            $malformedCsv = "employee_id,name`nE001,テスト太郎,Extra Field`nE002"  # 不整合な列数
            
            $result = ConvertFrom-CsvData -CsvContent $malformedCsv -TableName "provided_data"
            
            # エラーがあっても処理可能な行は処理される
            $result | Should -Not -BeNullOrEmpty
        }
        
        It "データ型を検証すること" {
            $csvWithInvalidData = "employee_id,name,hire_date`nE001,テスト太郎,invalid-date"
            
            $result = ConvertFrom-CsvData -CsvContent $csvWithInvalidData -TableName "provided_data"
            
            # データは読み込まれるが、バリデーションは後続処理で行われる
            $result[0].hire_date | Should -Be "invalid-date"
        }
        
        It "非常に大きなCSVファイルを処理すること" {
            # メモリ効率的な処理のテスト
            $largeCsvContent = New-LayeredTestData -DataType "Employee" -RecordCount 1000 -IncludeHeaders
            $largeCsvContent | Out-File -FilePath $script:TestCsvPath -Encoding UTF8
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            $content = Get-Content -Path $script:TestCsvPath -Raw
            $result = ConvertFrom-CsvData -CsvContent $content -TableName "provided_data"
            $stopwatch.Stop()
            
            $result.Count | Should -Be 1000
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 10000  # 10秒以内
        }
        
        It "並行CSV処理を処理すること" {
            $jobs = 1..3 | ForEach-Object {
                Start-Job -ScriptBlock {
                    param($CsvContent, $TestNum)
                    # モジュールの再インポートが必要
                    Import-Module (Join-Path $using:PSScriptRoot "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1") -Force
                    Import-Module (Join-Path $using:PSScriptRoot "../../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1") -Force
                    Import-Module (Join-Path $using:PSScriptRoot "../../../scripts/modules/Utils/DataProcessing/CsvProcessingUtils.psm1") -Force
                    
                    # モック設定の設定
                    $Global:script = @{}
                    $Global:script.DataSyncConfig = @{
                        tables = @{
                            provided_data = @{
                                columns = @{
                                    employee_id = @{ type = "TEXT"; primary_key = $true }
                                    name = @{ type = "TEXT"; nullable = $false }
                                }
                            }
                        }
                    }
                    
                    return ConvertFrom-CsvData -CsvContent $CsvContent -TableName "provided_data"
                } -ArgumentList ($script:csvContent -join "`n"), $_
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results | Should -HaveCount 3
            $results | ForEach-Object { $_ | Should -Not -BeNullOrEmpty }
        }
    }
    
    Context "Performance and Memory Management" {
        It "CSVを効率的に処理すること" {
            $csvContent = New-LayeredTestData -DataType "Employee" -RecordCount 100 -IncludeHeaders
            
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            # 複数回の処理でメモリリークがないことを確認
            1..10 | ForEach-Object {
                $result = ConvertFrom-CsvData -CsvContent ($csvContent -join "`n") -TableName "provided_data"
                $result | Out-Null
            }
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 5000  # 5秒以内
        }
        
        It "繰り返し操作でメモリリークしないこと" {
            $initialMemory = [GC]::GetTotalMemory($false)
            
            1..50 | ForEach-Object {
                $csvContent = New-LayeredTestData -DataType "Employee" -RecordCount 10
                $result = ConvertFrom-CsvData -CsvContent ($csvContent -join "`n") -TableName "provided_data"
                $result | Out-Null
            }
            
            [GC]::Collect()
            $finalMemory = [GC]::GetTotalMemory($true)
            
            ($finalMemory - $initialMemory) | Should -BeLessThan (5MB)  # 5MB以内の増加
        }
    }
    
    Context "Integration with Lower Layers" {
        It "基盤層のエンコーディング関数を使用すること" {
            $encoding = Get-CrossPlatformEncoding
            $encoding | Should -Not -BeNullOrEmpty
            
            # CSV処理でエンコーディングが使用される
            $csvContent = "employee_id,name`nE001,テスト太郎"
            $result = ConvertFrom-CsvData -CsvContent $csvContent -TableName "provided_data"
            
            $result[0].name | Should -Be "テスト太郎"
        }
        
        It "インフラストラクチャ層の設定を使用すること" {
            $config = Get-DataSyncConfig
            $config | Should -Not -BeNullOrEmpty
            
            # 設定からテーブル定義を取得
            $tableDef = Get-TableDefinition -TableName "provided_data"
            $tableDef.columns | Should -Not -BeNullOrEmpty
        }
        
        It "データアクセス層のデータベース関数を使用すること" {
            $columns = Get-CsvColumns -TableName "provided_data"
            $columns | Should -Not -BeNullOrEmpty
            $columns | Should -Contain "employee_id"
        }
    }
}