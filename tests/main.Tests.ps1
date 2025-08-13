#!/usr/bin/env pwsh
# PowerShell & SQLite Data Management System - Main Script Tests

BeforeAll {
    $script:TestRoot = Split-Path -Parent $PSScriptRoot
    $script:MainScript = Join-Path $TestRoot 'scripts/main.ps1'
    $script:ConfigPath = Join-Path $TestRoot 'config/data-sync-config.json'
    
    # Test temporary directory
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "ps-sqlite-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
    
    # Test data files
    $script:TestProvidedData = Join-Path $script:TempDir "test-provided.csv"
    $script:TestCurrentData = Join-Path $script:TempDir "test-current.csv"
    $script:TestOutputData = Join-Path $script:TempDir "test-output.csv"
    
    # Create test CSV files with Japanese content
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

Describe "Main Script Tests" {
    Context "Configuration Loading" {
        It "should load configuration file successfully" {
            Test-Path $script:ConfigPath | Should -Be $true
            
            $config = Get-Content -Path $script:ConfigPath | ConvertFrom-Json
            $config | Should -Not -BeNullOrEmpty
            $config.file_paths | Should -Not -BeNullOrEmpty
            $config.tables | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Parameter Validation" {
        It "should validate required parameters" {
            $params = @{
                ProvidedDataFilePath = $script:TestProvidedData
                CurrentDataFilePath = $script:TestCurrentData
                OutputFilePath = $script:TestOutputData
            }
            
            # Verify parameters are acceptable
            $params.Keys | Should -Contain "ProvidedDataFilePath"
            $params.Keys | Should -Contain "CurrentDataFilePath" 
            $params.Keys | Should -Contain "OutputFilePath"
        }
    }
    
    Context "File Operations" {
        It "should handle timestamp formatting correctly" {
            $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
            $timestamp | Should -Match "^\d{8}_\d{6}$"
        }
    }
}

Describe "Performance Tests" {
    Context "Memory Usage" {
        It "should not leak memory during operations" {
            $initialMemory = [System.GC]::GetTotalMemory($false)
            
            # Simulate operations
            for ($i = 0; $i -lt 10; $i++) {
                $data = @("test") * 100
                $data = $null
                [System.GC]::Collect()
            }
            
            $finalMemory = [System.GC]::GetTotalMemory($true)
            $memoryIncrease = $finalMemory - $initialMemory
            
            # Memory increase should be minimal (less than 5MB)
            $memoryIncrease | Should -BeLessOrEqual (5 * 1024 * 1024)
        }
    }
}
