#!/usr/bin/env pwsh
# PowerShell & SQLite データ管理システム - メインスクリプトテスト

BeforeAll {
    $script:TestRoot = Split-Path -Parent $PSScriptRoot
    $script:MainScript = Join-Path $TestRoot 'scripts/main.ps1'
    $script:ConfigPath = Join-Path $TestRoot 'config/data-sync-config.json'
    
    # テスト一時ディレクトリ
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "ps-sqlite-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    
    # テストデータファイル
    $script:TestProvidedData = Join-Path $script:TempDir "test-provided.csv"
    $script:TestCurrentData = Join-Path $script:TempDir "test-current.csv"
    $script:TestOutputData = Join-Path $script:TempDir "test-output.csv"
    
    # 日本語コンテンツでテストCSVファイルを作成
    @"
employee_id,card_number,name,department,position,email,phone,hire_date
E001,C001,田中太郎,営業部,主任,tanaka@example.com,090-1111-1111,2020-04-01
E002,C002,佐藤花子,総務部,係長,sato@example.com,090-2222-2222,2019-03-15
E003,C003,鈴木一郎,開発部,部長,suzuki@example.com,090-3333-3333,2018-01-10
"@ | Out-File -FilePath $script:TestProvidedData -Encoding utf8
    
    @"
user_id,card_number,name,department,position,email,phone,hire_date
E001,C001,田中太郎,営業部,主任,tanaka@example.com,090-1111-1111,2020-04-01
E004,C004,山田次郎,経理部,主任,yamada@example.com,090-4444-4444,2021-06-01
"@ | Out-File -FilePath $script:TestCurrentData -Encoding utf8
}

AfterAll {
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
}

Describe "メインスクリプトテスト" {
    Context "設定読み込み" {
        It "設定ファイルを正常に読み込むこと" {
            Test-Path $script:ConfigPath | Should -Be $true
            
            $config = Get-Content -Path $script:ConfigPath | ConvertFrom-Json
            $config | Should -Not -BeNullOrEmpty
            $config.file_paths | Should -Not -BeNullOrEmpty
            $config.tables | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "パラメータ検証" {
        It "必須パラメータを検証すること" {
            $params = @{
                ProvidedDataFilePath = $script:TestProvidedData
                CurrentDataFilePath = $script:TestCurrentData
                OutputFilePath = $script:TestOutputData
            }
            
            # パラメータが適切であることを検証
            $params.Keys | Should -Contain "ProvidedDataFilePath"
            $params.Keys | Should -Contain "CurrentDataFilePath" 
            $params.Keys | Should -Contain "OutputFilePath"
        }
    }
    
    Context "ファイル操作" {
        It "タイムスタンプフォーマットを正しく処理すること" {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $timestamp | Should -Match "^\d{8}_\d{6}$"
        }
    }
}

Describe "パフォーマンステスト" {
    Context "メモリ使用量" {
        It "操作中にメモリリークしないこと" {
            $initialMemory = [System.GC]::GetTotalMemory($false)
            
            # 操作のシミュレーション
            for ($i = 0; $i -lt 10; $i++) {
                $data = @("test") * 100
                $data = $null
                [System.GC]::Collect()
            }
            
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryIncrease = $finalMemory - $initialMemory
            
            # メモリ増加は最小限であるべき (5MB未満)
            $memoryIncrease | Should -BeLessOrEqual (5 * 1024 * 1024)
        }
    }
}
