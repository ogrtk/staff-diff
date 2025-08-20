# PowerShell & SQLite データ同期システム
# Utils/DataProcessing/CsvProcessingUtils.psm1 ユニットテスト

# テストヘルパーを最初にインポート
using module "../../TestHelpers/TestEnvironmentHelpers.psm1"
using module "../../TestHelpers/MockHelpers.psm1"

# 依存関係のモジュールをインポート（モック化準備のため）
using module "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/ConfigurationUtils.psm1"
using module "../../../scripts/modules/Utils/Infrastructure/LoggingUtils.psm1"

# テスト対象モジュールを最後にインポート
using module "../../../scripts/modules/Utils/DataProcessing/CsvProcessingUtils.psm1"

Describe "CsvProcessingUtils モジュール" {
    
    BeforeAll {
        $script:ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.Parent.Parent.FullName

        # テスト環境の初期化
        $script:TestEnv = Initialize-TestEnvironment
        
        # テスト用ディレクトリ
        $script:TestDataDir = Get-TestDataPath -SubPath "csv-processing" -Temp
        if (-not (Test-Path $script:TestDataDir)) {
            New-Item -Path $script:TestDataDir -ItemType Directory -Force | Out-Null
        }
        
        # テスト用設定データ
        $script:TestConfig = New-TestConfig
    }
    
    AfterAll {
        # テスト環境のクリーンアップ
        Clear-TestEnvironment
        
        # テスト用ディレクトリのクリーンアップ
        if (Test-Path $script:TestDataDir) {
            Remove-Item $script:TestDataDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    
    BeforeEach {
        # 基本的なモック化 - 共通設定
        Mock -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog { }
        Mock -ModuleName "CsvProcessingUtils" -CommandName Get-DataSyncConfig { return $script:TestConfig }
        
        # テスト用ディレクトリをクリーンアップ
        if (Test-Path $script:TestDataDir) {
            Get-ChildItem $script:TestDataDir | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    Context "Get-CsvFormatConfig 関数 - CSV設定取得" {
        
        It "provided_dataテーブルのCSV設定が正常に取得される" {
            # Act
            $result = Get-CsvFormatConfig -TableName "provided_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.encoding | Should -Be "UTF-8"
            $result.delimiter | Should -Be ","
            $result.has_header | Should -Be $false
            $result.null_values | Should -Contain ""
            $result.null_values | Should -Contain "NULL"
        }
        
        It "current_dataテーブルのCSV設定が正常に取得される" {
            # Act
            $result = Get-CsvFormatConfig -TableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.encoding | Should -Be "UTF-8"
            $result.delimiter | Should -Be ","
            $result.has_header | Should -Be $true
        }
        
        It "sync_resultテーブル（output設定）が正常に取得される" {
            # Act
            $result = Get-CsvFormatConfig -TableName "sync_result"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.encoding | Should -Be "UTF-8"
            $result.delimiter | Should -Be ","
            $result.include_header | Should -Be $true
        }
        
        It "無効なテーブル名で例外がスローされる" {
            # Act & Assert
            { Get-CsvFormatConfig -TableName "invalid_table" } | Should -Throw "*CSVフォーマット設定が見つかりません*"
        }
        
        It "設定ファイルエラーが適切にハンドリングされる" {
            # Arrange
            Mock -ModuleName "CsvProcessingUtils" -CommandName Get-DataSyncConfig {
                throw "設定ファイル読み込みエラー"
            }
            
            # Act & Assert
            { Get-CsvFormatConfig -TableName "provided_data" } | Should -Throw "*設定ファイル読み込みエラー*"
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Level -eq "Error" } -Scope It
        }
    }

    Context "ConvertTo-PowerShellEncoding 関数 - エンコーディング変換" {
        
        It "UTF-8がUTF8に変換される" {
            # Act
            $result = ConvertTo-PowerShellEncoding -EncodingName "UTF-8"
            
            # Assert
            $result | Should -Be "UTF8"
        }
        
        It "UTF-16がUnicodeに変換される" {
            # Act
            $result = ConvertTo-PowerShellEncoding -EncodingName "UTF-16"
            
            # Assert
            $result | Should -Be "Unicode"
        }
        
        It "SHIFT_JISが正常に変換される" {
            # Act
            $result = ConvertTo-PowerShellEncoding -EncodingName "SHIFT_JIS"
            
            # Assert
            $result | Should -Be "Shift_JIS"
        }
        
        It "小文字のエンコーディング名でも正常に変換される" {
            # Act
            $result = ConvertTo-PowerShellEncoding -EncodingName "utf-8"
            
            # Assert
            $result | Should -Be "UTF8"
        }
        
        It "未サポートのエンコーディング名でUTF8がデフォルトとして返される" {
            # Act
            $result = ConvertTo-PowerShellEncoding -EncodingName "UNSUPPORTED"
            
            # Assert
            $result | Should -Be "UTF8"
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Level -eq "Warning" -and $Message -match "未サポートのエンコーディング" } -Scope It
        }
        
        It "ASCIIエンコーディングが正常に変換される" {
            # Act
            $result = ConvertTo-PowerShellEncoding -EncodingName "ASCII"
            
            # Assert
            $result | Should -Be "ASCII"
        }
        
        It "ISO-8859-1がLatin1に変換される" {
            # Act
            $result = ConvertTo-PowerShellEncoding -EncodingName "ISO-8859-1"
            
            # Assert
            $result | Should -Be "Latin1"
        }
    }

    Context "Import-CsvWithFormat 関数 - CSV読み込み" {
        
        It "ヘッダー付きCSVファイルが正常に読み込まれる" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "header-test.csv"
            $csvContent = @"
user_id,name,department
E001,田中太郎,営業部
E002,佐藤花子,開発部
"@
            $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
            
            # Act
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].user_id | Should -Be "E001"
            $result[0].name | Should -Be "田中太郎"
            $result[1].user_id | Should -Be "E002"
            $result[1].name | Should -Be "佐藤花子"
            
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "CSVファイルを読み込み中" } -Scope It
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "読み込み完了" } -Scope It
        }
        
        It "ヘッダーなしCSVファイルが正常に読み込まれる" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "no-header-test.csv"
            $csvContent = @"
E001,C001,田中太郎,営業部,課長,tanaka@company.com,03-1234-5678,2020-01-15
E002,C002,佐藤花子,開発部,主任,sato@company.com,03-1234-5679,2021-03-20
"@
            $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
            
            # CSVヘッダーを手動で追加するためのモック
            Mock -ModuleName "CsvProcessingUtils" -CommandName Import-Csv {
                param($Path, $Encoding, $Delimiter)
                
                # ヘッダーを手動で追加してインポート
                $headers = @("employee_id", "card_number", "name", "department", "position", "email", "phone", "hire_date")
                $content = Get-Content $Path
                $headerLine = $headers -join ","
                $csvWithHeader = @($headerLine) + $content
                $tempFile = [System.IO.Path]::GetTempFileName()
                $csvWithHeader | Out-File -FilePath $tempFile -Encoding UTF8
                
                try {
                    return Import-Csv -Path $tempFile -Encoding $Encoding
                }
                finally {
                    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
                }
            }
            
            # Act
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "provided_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].employee_id | Should -Be "E001"
            $result[0].name | Should -Be "田中太郎"
        }
        
        It "null値が正常に変換される" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "null-values-test.csv"
            $csvContent = @"
user_id,name,department
E001,田中太郎,
E002,,開発部
E003,NULL,null
"@
            $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
            
            # Act
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
            $result[0].department | Should -Be $null
            $result[1].name | Should -Be $null
            $result[2].name | Should -Be $null
            $result[2].department | Should -Be $null
        }
        
        It "日本語を含むCSVファイルが正常に読み込まれる" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "japanese-test.csv"
            $csvContent = @"
user_id,name,department
E001,田中太郎,営業部
E002,佐藤花子,開発部
E003,鈴木一郎,総務部
"@
            $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
            
            # Act
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
            $result[0].name | Should -Be "田中太郎"
            $result[1].name | Should -Be "佐藤花子"
            $result[2].name | Should -Be "鈴木一郎"
        }
        
        It "存在しないファイルで例外がスローされる" {
            # Arrange
            $nonExistentFile = Join-Path $script:TestDataDir "non-existent.csv"
            
            # Act & Assert
            { Import-CsvWithFormat -CsvPath $nonExistentFile -TableName "current_data" } | Should -Throw
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Level -eq "Error" } -Scope It
        }
        
        It "空のCSVファイルで空の配列が返される" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "empty-test.csv"
            "user_id,name,department" | Out-File -FilePath $csvFile -Encoding UTF8  # ヘッダーのみ
            
            # Act
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Be @()
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "0行" } -Scope It
        }
    }

    Context "Test-CsvFormat 関数 - CSV検証" {
        
        It "有効なCSVファイルで検証が成功する" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "valid-test.csv"
            $csvContent = @"
user_id,name,department
E001,田中太郎,営業部
E002,佐藤花子,開発部
"@
            $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
            
            # Act
            $result = Test-CsvFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Be $true
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "CSVファイルを検証中" } -Scope It
        }
        
        It "空のCSVファイルで検証が成功する（allow_empty_file=true）" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "empty-allowed-test.csv"
            "user_id,name,department" | Out-File -FilePath $csvFile -Encoding UTF8  # ヘッダーのみ
            
            # Act
            $result = Test-CsvFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Be $true
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "空のCSVファイルです" } -Scope It
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "許可されています" } -Scope It
        }
        
        It "空のCSVファイルで検証が失敗する（allow_empty_file=false）" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "empty-forbidden-test.csv"
            "user_id,name,department" | Out-File -FilePath $csvFile -Encoding UTF8  # ヘッダーのみ
            
            # allow_empty_file=falseの設定でモック
            $restrictiveConfig = $script:TestConfig.Clone()
            $restrictiveConfig.csv_format.current_data.allow_empty_file = $false
            Mock -ModuleName "CsvProcessingUtils" -CommandName Get-DataSyncConfig { return $restrictiveConfig }
            
            # Act
            $result = Test-CsvFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Be $false
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Message -match "許可されていません" -and $Level -eq "Error" } -Scope It
        }
        
        It "不正なCSVファイルで例外がスローされる" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "invalid-test.csv"
            # 不正なCSV（カンマが不正）
            @"
user_id,name,department
E001田中太郎,営業部
E002佐藤花子
"@ | Out-File -FilePath $csvFile -Encoding UTF8
            
            # Import-CsvWithFormatが例外をスローするようにモック
            Mock -ModuleName "CsvProcessingUtils" -CommandName Import-CsvWithFormat {
                throw "不正なCSV形式"
            }
            
            # Act & Assert
            { Test-CsvFormat -CsvPath $csvFile -TableName "current_data" } | Should -Throw "*不正なCSV形式*"
        }
    }

    Context "エラーハンドリングとエッジケース" {
        
        It "非常に大きなCSVファイルでも正常に処理される" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "large-test.csv"
            $header = "user_id,name,department"
            $rows = @($header)
            
            # 1000行のデータを生成
            for ($i = 1; $i -le 1000; $i++) {
                $rows += "E{0:D4},ユーザー{0},部署{1}" -f $i, ($i % 10 + 1)
            }
            
            $rows | Out-File -FilePath $csvFile -Encoding UTF8
            
            # Act
            $startTime = Get-Date
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            $result.Count | Should -Be 1000
            $duration | Should -BeLessThan 10  # 10秒以内に完了すべき
        }
        
        It "特殊文字を含むCSVファイルが正常に処理される" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "special-chars-test.csv"
            $csvContent = @"
user_id,name,department
E001,"田中,太郎","営業部,課長"
E002,"佐藤""花子""","開発部"
E003,"鈴木`n一郎","総務部"
"@
            $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
            
            # Act
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 3
            $result[0].name | Should -Be "田中,太郎"
            $result[0].department | Should -Be "営業部,課長"
            $result[1].name | Should -Be "佐藤""花子"""
        }
        
        It "異なる区切り文字のCSVファイルが正常に処理される" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "semicolon-test.csv"
            $csvContent = @"
user_id;name;department
E001;田中太郎;営業部
E002;佐藤花子;開発部
"@
            $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
            
            # セミコロン区切りの設定でモック
            $semicolonConfig = $script:TestConfig.Clone()
            $semicolonConfig.csv_format.current_data.delimiter = ";"
            Mock -ModuleName "CsvProcessingUtils" -CommandName Get-DataSyncConfig { return $semicolonConfig }
            
            # Act
            $result = Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
            
            # Assert
            $result | Should -Not -BeNullOrEmpty
            $result.Count | Should -Be 2
            $result[0].name | Should -Be "田中太郎"
        }
        
        It "破損したファイルで適切にエラーがハンドリングされる" {
            # Arrange
            $csvFile = Join-Path $script:TestDataDir "corrupted-test.csv"
            # バイナリデータを混入
            [byte[]]$corruptedData = @(0x00, 0xFF, 0xFE) + [System.Text.Encoding]::UTF8.GetBytes("user_id,name")
            [System.IO.File]::WriteAllBytes($csvFile, $corruptedData)
            
            # Act & Assert
            { Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data" } | Should -Throw
            Should -Invoke -ModuleName "CsvProcessingUtils" -CommandName Write-SystemLog -ParameterFilter { $Level -eq "Error" } -Scope It
        }
    }

    Context "設定ファイル連携テスト" {
        
        It "カスタムCSV設定が正常に適用される" {
            # Arrange
            $customConfig = @{
                csv_format = @{
                    custom_data = @{
                        encoding         = "UTF-16"
                        delimiter        = "|"
                        has_header       = $true
                        null_values      = @("N/A", "NULL", "")
                        allow_empty_file = $false
                    }
                }
            }
            Mock -ModuleName "CsvProcessingUtils" -CommandName Get-DataSyncConfig { return $customConfig }
            
            # Act
            $result = Get-CsvFormatConfig -TableName "custom_data"
            
            # Assert
            $result.encoding | Should -Be "UTF-16"
            $result.delimiter | Should -Be "|"
            $result.has_header | Should -Be $true
            $result.null_values | Should -Contain "N/A"
            $result.allow_empty_file | Should -Be $false
        }
        
        It "複数のCSV設定が同時に利用できる" {
            # Act
            $providedConfig = Get-CsvFormatConfig -TableName "provided_data"
            $currentConfig = Get-CsvFormatConfig -TableName "current_data"
            $outputConfig = Get-CsvFormatConfig -TableName "sync_result"
            
            # Assert
            $providedConfig.has_header | Should -Be $false
            $currentConfig.has_header | Should -Be $true
            $outputConfig.include_header | Should -Be $true
        }
    }

    Context "パフォーマンステスト" {
        
        It "複数のCSVファイル処理が一定時間内に完了する" {
            # Arrange
            $fileCount = 5
            $csvFiles = @()
            
            for ($i = 1; $i -le $fileCount; $i++) {
                $csvFile = Join-Path $script:TestDataDir "perf-test-$i.csv"
                $csvContent = @"
user_id,name,department
E00$i,ユーザー$i,部署$i
E0${i}1,ユーザー${i}1,部署${i}1
"@
                $csvContent | Out-File -FilePath $csvFile -Encoding UTF8
                $csvFiles += $csvFile
            }
            
            # Act
            $startTime = Get-Date
            foreach ($csvFile in $csvFiles) {
                Import-CsvWithFormat -CsvPath $csvFile -TableName "current_data"
                Test-CsvFormat -CsvPath $csvFile -TableName "current_data"
            }
            $endTime = Get-Date
            $duration = ($endTime - $startTime).TotalSeconds
            
            # Assert
            $duration | Should -BeLessThan 10  # 10秒以内に完了すべき
        }
    }

    Context "関数のエクスポート確認" {
        
        It "必要な関数がエクスポートされている" {
            # Arrange
            $expectedFunctions = @(
                'Get-CsvFormatConfig',
                'ConvertTo-PowerShellEncoding',
                'Import-CsvWithFormat',
                'Test-CsvFormat'
            )
            
            # Act
            $module = Get-Module -Name CsvProcessingUtils
            $exportedFunctions = $module.ExportedFunctions.Keys
            
            # Assert
            foreach ($func in $expectedFunctions) {
                $exportedFunctions | Should -Contain $func
            }
        }
    }
}