BeforeAll {
    # Mock functions to avoid dependency issues
    function Global:Invoke-WithErrorHandling {
        param(
            [scriptblock]$ScriptBlock,
            [string]$Category = "System",
            [string]$Operation = "Operation",
            [hashtable]$Context = @{},
            [scriptblock]$CleanupScript = {}
        )
        
        try {
            return & $ScriptBlock
        } catch {
            Write-Warning "Mock error handling: $($_.Exception.Message)"
            throw
        }
    }
    
    # Mock Get-LoggingConfig function
    function Global:Get-LoggingConfig {
        return @{
            enabled = $true
            levels = @("Info", "Warning", "Error", "Success")
            log_directory = "logs"
            log_file_name = "test.log"
            max_file_size_mb = 10
            max_files = 5
        }
    }
    
    # Mock Get-Timestamp function
    function Global:Get-Timestamp {
        param([string]$Format = "yyyy-MM-dd HH:mm:ss")
        return Get-Date -Format $Format
    }
    
    # モジュールをインポート
    Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/modules/Utils/Foundation/CoreUtils.psm1') -Force
    Import-Module (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'scripts/modules/Utils/Infrastructure/LoggingUtils.psm1') -Force
}

Describe "Write-SystemLog with Console Color Parameter" {
    BeforeEach {
        # PowerShell ホスト情報を取得してMock化可能にする
        $originalHost = $Host
    }
    
    It "should use the specified console color when provided" {
        # Write-Host呼び出しをMock
        Mock -ModuleName LoggingUtils Write-Host { 
            param($Object, $ForegroundColor)
            # 指定された色が正しく渡されているかを確認
            $ForegroundColor | Should -Be "Magenta"
            return $Object
        }
        
        # Mock Write-LogToFile to avoid file operations
        Mock -ModuleName LoggingUtils Write-LogToFile { return }
        
        # Test: 明示的に色を指定
        Write-SystemLog -Message "Test message" -Level "Info" -ConsoleColor "Magenta"
        
        # Write-Hostが期待される色で呼び出されたかを確認
        Assert-MockCalled -ModuleName LoggingUtils Write-Host -Exactly 1 -ParameterFilter {
            $ForegroundColor -eq "Magenta"
        }
    }
    
    It "should use default level-based colors when ConsoleColor is not specified" {
        # Write-Host呼び出しをMock
        Mock -ModuleName LoggingUtils Write-Host { 
            param($Object, $ForegroundColor)
            # Error レベルの場合は Red になることを確認
            $ForegroundColor | Should -Be "Red"
            return $Object
        }
        
        # Mock Write-LogToFile to avoid file operations
        Mock -ModuleName LoggingUtils Write-LogToFile { return }
        
        # Test: ConsoleColorを指定せずにErrorレベルでログ出力
        Write-SystemLog -Message "Error message" -Level "Error"
        
        # Write-Hostが期待される色で呼び出されたかを確認
        Assert-MockCalled -ModuleName LoggingUtils Write-Host -Exactly 1 -ParameterFilter {
            $ForegroundColor -eq "Red"
        }
    }
    
    It "should use default level-based colors for Info level" {
        # Write-Host呼び出しをMock
        Mock -ModuleName LoggingUtils Write-Host { 
            param($Object, $ForegroundColor)
            # Info レベルの場合は Cyan になることを確認
            $ForegroundColor | Should -Be "Cyan"
            return $Object
        }
        
        # Mock Write-LogToFile to avoid file operations
        Mock -ModuleName LoggingUtils Write-LogToFile { return }
        
        # Test: ConsoleColorを指定せずにInfoレベルでログ出力
        Write-SystemLog -Message "Info message" -Level "Info"
        
        # Write-Hostが期待される色で呼び出されたかを確認
        Assert-MockCalled -ModuleName LoggingUtils Write-Host -Exactly 1 -ParameterFilter {
            $ForegroundColor -eq "Cyan"
        }
    }
    
    It "should use default level-based colors for Warning level" {
        # Write-Host呼び出しをMock
        Mock -ModuleName LoggingUtils Write-Host { 
            param($Object, $ForegroundColor)
            # Warning レベルの場合は Yellow になることを確認
            $ForegroundColor | Should -Be "Yellow"
            return $Object
        }
        
        # Mock Write-LogToFile to avoid file operations
        Mock -ModuleName LoggingUtils Write-LogToFile { return }
        
        # Test: ConsoleColorを指定せずにWarningレベルでログ出力
        Write-SystemLog -Message "Warning message" -Level "Warning"
        
        # Write-Hostが期待される色で呼び出されたかを確認
        Assert-MockCalled -ModuleName LoggingUtils Write-Host -Exactly 1 -ParameterFilter {
            $ForegroundColor -eq "Yellow"
        }
    }
    
    It "should use default level-based colors for Success level" {
        # Write-Host呼び出しをMock
        Mock -ModuleName LoggingUtils Write-Host { 
            param($Object, $ForegroundColor)
            # Success レベルの場合は Green になることを確認
            $ForegroundColor | Should -Be "Green"
            return $Object
        }
        
        # Mock Write-LogToFile to avoid file operations
        Mock -ModuleName LoggingUtils Write-LogToFile { return }
        
        # Test: ConsoleColorを指定せずにSuccessレベルでログ出力
        Write-SystemLog -Message "Success message" -Level "Success"
        
        # Write-Hostが期待される色で呼び出されたかを確認
        Assert-MockCalled -ModuleName LoggingUtils Write-Host -Exactly 1 -ParameterFilter {
            $ForegroundColor -eq "Green"
        }
    }
    
    It "should override level-based color when ConsoleColor is explicitly provided" {
        # Write-Host呼び出しをMock
        Mock -ModuleName LoggingUtils Write-Host { 
            param($Object, $ForegroundColor)
            # 明示的に指定された色を使用することを確認（レベルベースの色を上書き）
            $ForegroundColor | Should -Be "DarkBlue"
            return $Object
        }
        
        # Mock Write-LogToFile to avoid file operations
        Mock -ModuleName LoggingUtils Write-LogToFile { return }
        
        # Test: ErrorレベルだがConsoleColorでDarkBlueを明示指定
        Write-SystemLog -Message "Custom color message" -Level "Error" -ConsoleColor "DarkBlue"
        
        # Write-Hostが期待される色で呼び出されたかを確認
        Assert-MockCalled -ModuleName LoggingUtils Write-Host -Exactly 1 -ParameterFilter {
            $ForegroundColor -eq "DarkBlue"
        }
    }
    
    It "should still call Write-LogToFile for file logging regardless of console color" {
        # Mock Write-Host and Write-LogToFile
        Mock -ModuleName LoggingUtils Write-Host { return }
        Mock -ModuleName LoggingUtils Write-LogToFile { return }
        
        # Test: ファイルログ機能が色指定に関わらず動作することを確認
        Write-SystemLog -Message "File log test" -Level "Info" -ConsoleColor "White"
        
        # Write-LogToFileが呼び出されたかを確認
        Assert-MockCalled -ModuleName LoggingUtils Write-LogToFile -Exactly 1 -ParameterFilter {
            $Message -eq "File log test" -and $Level -eq "Info"
        }
    }
}