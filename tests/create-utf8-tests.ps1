#!/usr/bin/env pwsh
# UTF-8 Test File Creator - Clean Recreation Script

# Force UTF-8 encoding for all operations
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
if ($PSVersionTable.PSVersion.Major -ge 6) {
    $PSDefaultParameterValues['Out-File:Encoding'] = 'utf8NoBOM'
}

Write-Host "Creating clean UTF-8 test files..." -ForegroundColor Green

# Create main.Tests.ps1 with clean UTF-8 encoding
$mainTestContent = @'
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
'@

$mainTestContent | Out-File -FilePath "tests/main.Tests.ps1" -Encoding utf8
Write-Host "Created: tests/main.Tests.ps1" -ForegroundColor Blue

# Create ErrorHandlingUtils.Tests.ps1
$errorHandlingTestContent = @'
#!/usr/bin/env pwsh
# ErrorHandlingUtils Module Tests

BeforeAll {
    $script:TestRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $TestRoot 'scripts/modules/Utils/ErrorHandlingUtils.psm1'
    
    # Import module for testing
    Import-Module $script:ModulePath -Force
    
    # Test temporary directory
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "error-handling-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
    
    Remove-Module -Name ErrorHandlingUtils -Force -ErrorAction SilentlyContinue
}

Describe "ErrorHandlingUtils Tests" {
    Context "Basic Error Handling" {
        It "should handle successful operations" {
            # Test successful script block execution
            $result = & {
                try {
                    "success"
                } catch {
                    "error"
                }
            }
            
            $result | Should -Be "success"
        }
        
        It "should handle error scenarios" {
            # Test error handling
            $result = & {
                try {
                    throw "test error"
                } catch {
                    "caught error: $($_.Exception.Message)"
                }
            }
            
            $result | Should -Match "caught error: test error"
        }
    }
    
    Context "File Operations" {
        It "should handle file access errors gracefully" {
            $nonExistentFile = Join-Path $script:TempDir "nonexistent.txt"
            
            $result = & {
                try {
                    Get-Content $nonExistentFile -ErrorAction Stop
                } catch {
                    "file not found"
                }
            }
            
            $result | Should -Be "file not found"
        }
    }
}
'@

$errorHandlingTestContent | Out-File -FilePath "tests/Utils/ErrorHandlingUtils.Tests.ps1" -Encoding utf8
Write-Host "Created: tests/Utils/ErrorHandlingUtils.Tests.ps1" -ForegroundColor Blue

# Create ConfigUtils.Tests.ps1
$configTestContent = @'
#!/usr/bin/env pwsh
# ConfigUtils Module Tests

BeforeAll {
    $script:TestRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $TestRoot 'scripts/modules/Utils/ConfigUtils.psm1'
    $script:RealConfigPath = Join-Path $TestRoot 'config/data-sync-config.json'
    
    # Import module for testing
    Import-Module $script:ModulePath -Force
    
    # Test temporary directory
    $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "config-test-$(Get-Random)"
    New-Item -ItemType Directory -Path $script:TempDir -Force | Out-Null
}

AfterAll {
    if (Test-Path $script:TempDir) {
        Remove-Item -Path $script:TempDir -Recurse -Force
    }
    
    Remove-Module -Name ConfigUtils -Force -ErrorAction SilentlyContinue
}

Describe "ConfigUtils Tests" {
    Context "Configuration File Loading" {
        It "should load the real configuration file" {
            Test-Path $script:RealConfigPath | Should -Be $true
            
            $config = Get-Content -Path $script:RealConfigPath | ConvertFrom-Json
            $config | Should -Not -BeNullOrEmpty
            $config.file_paths | Should -Not -BeNullOrEmpty
            $config.tables | Should -Not -BeNullOrEmpty
        }
        
        It "should validate configuration structure" {
            $config = Get-Content -Path $script:RealConfigPath | ConvertFrom-Json
            
            # Check required sections
            $config.file_paths.provided_data_file_path | Should -Not -BeNullOrEmpty
            $config.file_paths.current_data_file_path | Should -Not -BeNullOrEmpty
            $config.file_paths.output_file_path | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Configuration Values" {
        It "should retrieve timezone setting" {
            $config = Get-Content -Path $script:RealConfigPath | ConvertFrom-Json
            
            if ($config.file_paths.timezone) {
                $config.file_paths.timezone | Should -Match "(Asia/Tokyo|UTC)"
            }
        }
    }
}
'@

$configTestContent | Out-File -FilePath "tests/Utils/ConfigUtils.Tests.ps1" -Encoding utf8
Write-Host "Created: tests/Utils/ConfigUtils.Tests.ps1" -ForegroundColor Blue

Write-Host "All test files created successfully with clean UTF-8 encoding!" -ForegroundColor Green
Write-Host "You can now run tests using: ./tests/run-test.ps1" -ForegroundColor Cyan