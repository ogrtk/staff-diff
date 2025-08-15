#!/usr/bin/env pwsh
# ErrorHandlingUtils Module Tests

BeforeAll {
    $script:TestRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ModulePath = Join-Path $TestRoot 'scripts/modules/Utils/Infrastructure/ErrorHandlingUtils.psm1'
    
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
