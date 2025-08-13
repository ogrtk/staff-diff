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
