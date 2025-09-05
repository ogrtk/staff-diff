# PowerShell & SQLite データ同期システム
# UTF-8 テストファイル作成スクリプト

# using module文（スクリプト冒頭で静的パス指定）
using module "TestHelpers/TestEnvironmentHelpers.psm1"

param(
    [string]$OutputDirectory = "",
    [switch]$Overwrite,
    [bool]$IncludeJapanese = $true,
    [switch]$IncludeBOM,
    [int]$RecordCount = 20
)

# スクリプトの場所を基準にプロジェクトルートを設定
$ProjectRoot = (Get-Item -Path $PSScriptRoot).Parent.FullName
$TestHelpersPath = Join-Path $PSScriptRoot "TestHelpers"

# 出力ディレクトリの設定
if ([string]::IsNullOrEmpty($OutputDirectory)) {
    $OutputDirectory = Join-Path $ProjectRoot "test-data" "utf8-tests"
}

# 出力ディレクトリの作成
if (-not (Test-Path $OutputDirectory)) {
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
    Write-Host "出力ディレクトリを作成しました: $OutputDirectory" -ForegroundColor Green
}

# UTF-8エンコーディングの取得
function Get-UTF8Encoding {
    param([switch]$IncludeBOM)
    
    if ($IncludeBOM) {
        return [System.Text.UTF8Encoding]::new($true)
    }
    else {
        return [System.Text.UTF8Encoding]::new($false)
    }
}

# UTF-8 CSVファイルの作成
function New-UTF8CsvFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [array]$Data,
        
        [switch]$IncludeHeader,
        [switch]$IncludeBOM
    )
    
    $encoding = Get-UTF8Encoding -IncludeBOM:$IncludeBOM
    
    # CSV内容の生成
    $csvContent = ""
    if ($IncludeHeader -and $Data.Count -gt 0) {
        $headers = ($Data[0].PSObject.Properties | ForEach-Object { $_.Name }) -join ","
        $csvContent += $headers + "`n"
    }
    
    foreach ($record in $Data) {
        $values = $record.PSObject.Properties | ForEach-Object { 
            $value = $_.Value
            if ($value -match '[",\n\r]' -or [string]::IsNullOrEmpty($value)) {
                "`"$($value -replace '"', '""')`""
            }
            else {
                $value
            }
        }
        $csvContent += ($values -join ",") + "`n"
    }
    
    # ファイルに書き込み
    [System.IO.File]::WriteAllText($FilePath, $csvContent, $encoding)
}

# テストデータの生成
function New-TestDataSets {
    Write-Host "UTF-8テストデータを生成中..." -ForegroundColor Yellow
    
    # 基本的な提供データ
    Write-Host "  - 提供データ（基本）" -ForegroundColor Gray
    $providedData = New-ProvidedDataRecords -Count $RecordCount -IncludeJapanese:$IncludeJapanese
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "provided-data-basic.csv") -Data $providedData -IncludeBOM:$IncludeBOM
    
    # ヘッダー付き提供データ
    Write-Host "  - 提供データ（ヘッダー付き）" -ForegroundColor Gray
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "provided-data-with-header.csv") -Data $providedData -IncludeHeader -IncludeBOM:$IncludeBOM
    
    # 基本的な現在データ
    Write-Host "  - 現在データ（基本）" -ForegroundColor Gray
    $currentData = New-CurrentDataRecords -Count $RecordCount -IncludeJapanese:$IncludeJapanese
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "current-data-basic.csv") -Data $currentData -IncludeHeader -IncludeBOM:$IncludeBOM
    
    # フィルタリング用データ（Z*、Y*を含む）
    Write-Host "  - フィルタリングテスト用データ" -ForegroundColor Gray
    $filterTestData = @()
    
    # 通常データ
    for ($i = 1; $i -le 5; $i++) {
        $filterTestData += [PSCustomObject]@{
            employee_id = "E{0:D3}" -f $i
            card_number = "C{0:D6}" -f (100000 + $i)
            name        = if ($IncludeJapanese) { "通常職員$i" } else { "Employee$i" }
            department  = if ($IncludeJapanese) { "営業部" } else { "Sales" }
            position    = if ($IncludeJapanese) { "課長" } else { "Manager" }
            email       = "employee$i@company.com"
            phone       = "03-1234-567$i"
            hire_date   = (Get-Date).AddDays( - ($i * 100)).ToString("yyyy-MM-dd")
        }
    }
    
    # フィルタ対象データ（Z*）
    for ($i = 1; $i -le 3; $i++) {
        $filterTestData += [PSCustomObject]@{
            employee_id = "Z{0:D3}" -f $i
            card_number = "C9{0:D5}" -f (10000 + $i)
            name        = if ($IncludeJapanese) { "除外職員$i" } else { "ExcludeEmployee$i" }
            department  = if ($IncludeJapanese) { "テスト部" } else { "Test" }
            position    = if ($IncludeJapanese) { "テスト" } else { "Tester" }
            email       = "exclude$i@company.com"
            phone       = "03-9999-000$i"
            hire_date   = (Get-Date).AddDays(-30).ToString("yyyy-MM-dd")
        }
    }
    
    # フィルタ対象データ（Y*）
    for ($i = 1; $i -le 2; $i++) {
        $filterTestData += [PSCustomObject]@{
            employee_id = "Y{0:D3}" -f $i
            card_number = "C8{0:D5}" -f (10000 + $i)
            name        = if ($IncludeJapanese) { "Y除外職員$i" } else { "YExcludeEmployee$i" }
            department  = if ($IncludeJapanese) { "Y部門" } else { "YDept" }
            position    = if ($IncludeJapanese) { "Yテスト" } else { "YTester" }
            email       = "yexclude$i@company.com"
            phone       = "03-8888-000$i"
            hire_date   = (Get-Date).AddDays(-60).ToString("yyyy-MM-dd")
        }
    }
    
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "provided-data-with-filters.csv") -Data $filterTestData -IncludeBOM:$IncludeBOM
    
    # 対応する現在データ（フィルタリング用）
    $currentFilterData = @()
    for ($i = 3; $i -le 7; $i++) {
        $currentFilterData += [PSCustomObject]@{
            user_id     = "E{0:D3}" -f $i
            card_number = "C{0:D6}" -f (200000 + $i)
            name        = if ($IncludeJapanese) { "現在職員$i" } else { "CurrentEmployee$i" }
            department  = if ($IncludeJapanese) { "開発部" } else { "Development" }
            position    = if ($IncludeJapanese) { "主任" } else { "Supervisor" }
            email       = "current$i@company.com"
            phone       = "03-2345-678$i"
            hire_date   = (Get-Date).AddDays( - ($i * 80)).ToString("yyyy-MM-dd")
        }
    }
    
    # 除外対象のcurrent_data（KEEPとして出力される）
    $currentFilterData += [PSCustomObject]@{
        user_id     = "Z888"
        card_number = "C888888"
        name        = if ($IncludeJapanese) { "除外KEEP対象" } else { "ExcludedKeep" }
        department  = if ($IncludeJapanese) { "保持部" } else { "KeepDept" }
        position    = if ($IncludeJapanese) { "保持役" } else { "Keeper" }
        email       = "keep@company.com"
        phone       = "03-8888-8888"
        hire_date   = "2023-01-01"
    }
    
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "current-data-with-filters.csv") -Data $currentFilterData -IncludeHeader -IncludeBOM:$IncludeBOM
    
    # 大量データテスト用
    Write-Host "  - 大量データテスト用ファイル" -ForegroundColor Gray
    $largeProvidedData = New-ProvidedDataRecords -Count 1000 -IncludeJapanese:$IncludeJapanese
    $largeCurrentData = New-CurrentDataRecords -Count 1000 -IncludeJapanese:$IncludeJapanese
    
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "large-provided-data.csv") -Data $largeProvidedData -IncludeBOM:$IncludeBOM
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "large-current-data.csv") -Data $largeCurrentData -IncludeHeader -IncludeBOM:$IncludeBOM
    
    # エラーテスト用（不正フォーマット）
    Write-Host "  - エラーテスト用ファイル" -ForegroundColor Gray
    $errorTestContent = @"
E001,C001,不正データ,営業部
E002,C002,カラム不足
E003,C003,田中太郎,開発部,課長,extra_column,too_many_columns
"@
    
    $encoding = Get-UTF8Encoding -IncludeBOM:$IncludeBOM
    [System.IO.File]::WriteAllText((Join-Path $OutputDirectory "error-test-data.csv"), $errorTestContent, $encoding)
    
    # 空データテスト用
    Write-Host "  - 空データテスト用ファイル" -ForegroundColor Gray
    [System.IO.File]::WriteAllText((Join-Path $OutputDirectory "empty-provided-data.csv"), "", $encoding)
    [System.IO.File]::WriteAllText((Join-Path $OutputDirectory "empty-current-data.csv"), "user_id,card_number,name,department,position,email,phone,hire_date`n", $encoding)
    
    # 特殊文字テスト用
    Write-Host "  - 特殊文字テスト用ファイル" -ForegroundColor Gray
    $specialCharData = @(
        [PSCustomObject]@{
            employee_id = "S001"
            card_number = "C001"
            name        = if ($IncludeJapanese) { "特殊文字テスト「」〜♪" } else { "Special,Chars""Test" }
            department  = if ($IncludeJapanese) { "特殊部署\n改行" } else { "Special\nDept" }
            position    = if ($IncludeJapanese) { "特殊役職" } else { "Special""Position" }
            email       = "special@company.com"
            phone       = "03-1234-5678"
            hire_date   = "2023-01-01"
        }
        [PSCustomObject]@{
            employee_id = "S002"
            card_number = "C002"
            name        = if ($IncludeJapanese) { "山田　太郎（全角スペース）" } else { "John Doe (spaces)" }
            department  = if ($IncludeJapanese) { "😀絵文字部😀" } else { "😀Emoji😀Dept" }
            position    = if ($IncludeJapanese) { "Unicode🚀テスト" } else { "Unicode🚀Test" }
            email       = "unicode@company.com"
            phone       = "03-9999-9999"
            hire_date   = "2023-02-01"
        }
    )
    
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "special-chars-data.csv") -Data $specialCharData -IncludeHeader -IncludeBOM:$IncludeBOM
}

# エンコーディング検証用ファイルの作成
function New-EncodingTestFiles {
    Write-Host "エンコーディング検証用ファイルを作成中..." -ForegroundColor Yellow
    
    $testData = @(
        [PSCustomObject]@{
            employee_id = "T001"
            card_number = "C001"
            name        = if ($IncludeJapanese) { "日本語テスト" } else { "Japanese Test" }
            department  = if ($IncludeJapanese) { "日本語部署" } else { "Japanese Dept" }
            position    = if ($IncludeJapanese) { "日本語役職" } else { "Japanese Position" }
            email       = "japanese@company.com"
            phone       = "03-1234-5678"
            hire_date   = "2023-01-01"
        }
    )
    
    # UTF-8 (BOM無し)
    Write-Host "  - UTF-8 (BOM無し)" -ForegroundColor Gray
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "encoding-utf8-nobom.csv") -Data $testData -IncludeHeader -IncludeBOM:$false
    
    # UTF-8 (BOM有り)
    Write-Host "  - UTF-8 (BOM有り)" -ForegroundColor Gray
    New-UTF8CsvFile -FilePath (Join-Path $OutputDirectory "encoding-utf8-bom.csv") -Data $testData -IncludeHeader -IncludeBOM:$true
    
    # エンコーディング情報ファイル
    $encodingInfo = @"
UTF-8 テストファイル エンコーディング情報

作成日時: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
作成者: create-utf8-tests.ps1

ファイル一覧:
- encoding-utf8-nobom.csv : UTF-8 (BOM無し)
- encoding-utf8-bom.csv   : UTF-8 (BOM有り)

検証方法:
PowerShellでのエンコーディング確認:
Get-Content <ファイル名> -Encoding UTF8

バイナリでのBOM確認:
Get-Content <ファイル名> -AsByteStream | Select-Object -First 3
UTF-8 BOM: 239, 187, 191 (0xEF, 0xBB, 0xBF)
"@
    
    $encodingInfo | Out-File -FilePath (Join-Path $OutputDirectory "encoding-info.txt") -Encoding UTF8
}

# 設定ファイルの作成
function New-TestConfigFiles {
    Write-Host "テスト用設定ファイルを作成中..." -ForegroundColor Yellow
    
    if (Get-Command "New-TestConfig" -ErrorAction SilentlyContinue) {
        # フィルタリング有効設定
        Write-Host "  - フィルタリング有効設定" -ForegroundColor Gray
        $filterConfig = New-TestConfig -CustomSettings @{
            file_paths   = @{
                provided_data_file_path = Join-Path $OutputDirectory "provided-data-with-filters.csv"
                current_data_file_path  = Join-Path $OutputDirectory "current-data-with-filters.csv"
                output_file_path        = Join-Path $OutputDirectory "test-output-filtered.csv"
            }
            data_filters = @{
                provided_data = @{
                    enabled = $true
                    rules   = @(
                        @{ field = "employee_id"; type = "exclude"; glob = "Z*"; description = "Z始まりを除外" }
                        @{ field = "employee_id"; type = "exclude"; glob = "Y*"; description = "Y始まりを除外" }
                    )
                }
                current_data  = @{
                    enabled                 = $true
                    rules                   = @(
                        @{ field = "user_id"; type = "exclude"; glob = "Z*"; description = "Z始まりを除外" }
                        @{ field = "user_id"; type = "exclude"; glob = "Y*"; description = "Y始まりを除外" }
                    )
                    output_excluded_as_keep = @{
                        enabled = $true
                    }
                }
            }
        }
        
        $filterConfig | ConvertTo-Json -Depth 15 | Out-File -FilePath (Join-Path $OutputDirectory "test-config-with-filters.json") -Encoding UTF8
        
        # フィルタリング無効設定
        Write-Host "  - フィルタリング無効設定" -ForegroundColor Gray
        $noFilterConfig = New-TestConfig -CustomSettings @{
            file_paths   = @{
                provided_data_file_path = Join-Path $OutputDirectory "provided-data-basic.csv"
                current_data_file_path  = Join-Path $OutputDirectory "current-data-basic.csv"
                output_file_path        = Join-Path $OutputDirectory "test-output-no-filter.csv"
            }
            data_filters = @{
                provided_data = @{ enabled = $false }
                current_data  = @{ enabled = $false }
            }
        }
        
        $noFilterConfig | ConvertTo-Json -Depth 15 | Out-File -FilePath (Join-Path $OutputDirectory "test-config-no-filters.json") -Encoding UTF8
    }
}

# メイン処理
function Invoke-UTF8TestFileCreation {
    Write-Host "=== UTF-8 テストファイル作成スクリプト ===" -ForegroundColor Cyan
    Write-Host "出力ディレクトリ: $OutputDirectory" -ForegroundColor Gray
    Write-Host "日本語を含む: $IncludeJapanese" -ForegroundColor Gray
    Write-Host "BOMを含む: $IncludeBOM" -ForegroundColor Gray
    Write-Host "レコード数: $RecordCount" -ForegroundColor Gray
    Write-Host ""
    
    # 既存ファイルの確認
    if ((Test-Path $OutputDirectory) -and ((Get-ChildItem $OutputDirectory).Count -gt 0) -and -not $Overwrite) {
        Write-Warning "出力ディレクトリに既存ファイルがあります。"
        $response = Read-Host "上書きしますか？ (y/N)"
        if ($response -notmatch "^[yY]") {
            Write-Host "処理を中止しました。" -ForegroundColor Yellow
            exit 0
        }
    }
    
    # 既存ファイルの削除
    if ($Overwrite -and (Test-Path $OutputDirectory)) {
        Get-ChildItem $OutputDirectory -File | Remove-Item -Force
        Write-Host "既存ファイルを削除しました。" -ForegroundColor Yellow
    }
    
    # テストデータの生成
    New-TestDataSets
    
    # エンコーディングテストファイルの作成
    New-EncodingTestFiles
    
    # 設定ファイルの作成
    New-TestConfigFiles
    
    # 完了メッセージ
    Write-Host ""
    Write-Host "✓ UTF-8テストファイルの作成が完了しました！" -ForegroundColor Green
    Write-Host "出力ディレクトリ: $OutputDirectory" -ForegroundColor Green
    
    # 作成されたファイルの一覧表示
    $createdFiles = Get-ChildItem $OutputDirectory -File | Sort-Object Name
    Write-Host ""
    Write-Host "作成されたファイル ($($createdFiles.Count) 件):" -ForegroundColor Cyan
    foreach ($file in $createdFiles) {
        $size = [math]::Round($file.Length / 1KB, 2)
        Write-Host "  $($file.Name) ($size KB)" -ForegroundColor Gray
    }
    
    Write-Host ""
    Write-Host "使用方法:" -ForegroundColor Yellow
    Write-Host "  # 基本テストの実行" -ForegroundColor Gray
    Write-Host "  pwsh ./tests/run-test.ps1" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  # フィルタリングテスト用設定での実行" -ForegroundColor Gray
    Write-Host "  pwsh ./scripts/main.ps1 -ConfigFilePath `"$OutputDirectory/test-config-with-filters.json`"" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  # エンコーディングテスト" -ForegroundColor Gray
    Write-Host "  Get-Content `"$OutputDirectory/encoding-utf8-nobom.csv`" -Encoding UTF8" -ForegroundColor Gray
}

# ヘルプの表示
function Show-Help {
    Write-Host @"
UTF-8 テストファイル作成スクリプト

使用方法:
  pwsh ./tests/create-utf8-tests.ps1 [オプション]

オプション:
  -OutputDirectory <パス>    出力ディレクトリ（デフォルト: test-data/utf8-tests）
  -Overwrite                既存ファイルを上書き
  -IncludeJapanese          日本語を含むテストデータを作成（デフォルト: true）
  -IncludeBOM               UTF-8 BOMを含むファイルを作成
  -RecordCount <数>         生成するレコード数（デフォルト: 20）

使用例:
  # 基本的な使用
  pwsh ./tests/create-utf8-tests.ps1

  # BOM付きで日本語なしのテストファイル作成
  pwsh ./tests/create-utf8-tests.ps1 -IncludeBOM -IncludeJapanese:$false

  # 大量データテスト用
  pwsh ./tests/create-utf8-tests.ps1 -RecordCount 100 -Overwrite

  # カスタムディレクトリに出力
  pwsh ./tests/create-utf8-tests.ps1 -OutputDirectory "./custom-test-data"
"@
}

# ヘルプが要求された場合
if ($args -contains "-h" -or $args -contains "-help" -or $args -contains "--help") {
    Show-Help
    exit 0
}

# メイン処理の実行
Invoke-UTF8TestFileCreation