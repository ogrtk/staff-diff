# PowerShell & SQLite データ同期システム
# モック機能テストヘルパーモジュール

# グローバルモック状態管理
$script:MockedCommands = @{}
$script:MockCallHistory = @{}

# コマンドのモック化
function Mock-Command {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        
        [scriptblock]$MockScript = { Write-Host "Mocked: $CommandName" },
        
        [object]$ReturnValue = $null,
        
        [switch]$PassThru
    )
    
    # 元のコマンドの保存
    if (-not $script:MockedCommands.ContainsKey($CommandName)) {
        $originalCommand = Get-Command $CommandName -ErrorAction SilentlyContinue
        $script:MockedCommands[$CommandName] = $originalCommand
        $script:MockCallHistory[$CommandName] = @()
    }
    
    # モック関数の作成
    $mockFunction = @"
function global:$CommandName {
    param([Parameter(ValueFromRemainingArguments)]`$Args)
    
    # 呼び出し履歴の記録
    `$script:MockCallHistory['$CommandName'] += @{
        Timestamp = Get-Date
        Arguments = `$Args
        CallerInfo = (Get-PSCallStack)[1]
    }
    
    # モックスクリプトの実行
    try {
        if (`$ReturnValue -ne `$null) {
            return `$ReturnValue
        }
        else {
            & $MockScript @Args
        }
    }
    catch {
        Write-Error "Mock実行エラー ($CommandName): `$(`$_.Exception.Message)"
        throw
    }
}
"@
    
    Invoke-Expression $mockFunction
    
    Write-Verbose "コマンドをモック化しました: $CommandName"
    
    if ($PassThru) {
        return $CommandName
    }
}

# SQLiteコマンドのモック化
function Mock-SqliteCommand {
    param(
        [string]$ReturnValue = "",
        [int]$ExitCode = 0,
        [switch]$ThrowError
    )
    
    $mockScript = {
        param($DatabasePath, $Query)
        
        if ($ThrowError) {
            $global:LASTEXITCODE = 1
            throw "モック化されたSQLiteエラー"
        }
        
        $global:LASTEXITCODE = $ExitCode
        return $ReturnValue
    }
    
    Mock-Command -CommandName "sqlite3" -MockScript $mockScript
}

# ファイルシステム操作のモック化
function Mock-FileSystemOperations {
    param(
        [hashtable]$FileExists = @{},
        [hashtable]$FileContent = @{},
        [switch]$AllowWrite = $true
    )
    
    # Test-Pathのモック
    Mock-Command -CommandName "Test-Path" -MockScript {
        param($Path)
        
        if ($FileExists.ContainsKey($Path)) {
            return $FileExists[$Path]
        }
        
        # デフォルトは存在しない
        return $false
    }
    
    # Get-Contentのモック
    Mock-Command -CommandName "Get-Content" -MockScript {
        param($Path, $Raw, $Encoding)
        
        if ($FileContent.ContainsKey($Path)) {
            $content = $FileContent[$Path]
            if ($Raw) {
                return $content
            }
            else {
                return $content -split "`n"
            }
        }
        
        throw "モックファイルが見つかりません: $Path"
    }
    
    # Out-Fileのモック
    if ($AllowWrite) {
        Mock-Command -CommandName "Out-File" -MockScript {
            param($FilePath, $InputObject, $Encoding, $Append, $NoNewline)
            
            Write-Verbose "モックファイル出力: $FilePath"
            # 実際には何もしない（テスト環境）
        }
    }
}

# ログ機能のモック化
function Mock-LoggingSystem {
    param(
        [switch]$CaptureMessages,
        [switch]$SuppressOutput
    )
    
    if ($CaptureMessages) {
        $script:CapturedLogMessages = @()
    }
    
    Mock-Command -CommandName "Write-SystemLog" -MockScript {
        param($Message, $Level = "Info")
        
        if ($CaptureMessages) {
            $script:CapturedLogMessages += @{
                Message = $Message
                Level = $Level
                Timestamp = Get-Date
            }
        }
        
        if (-not $SuppressOutput) {
            Write-Host "[$Level] $Message" -ForegroundColor Green
        }
    }
}

# 設定システムのモック化
function Mock-ConfigurationSystem {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$MockConfig
    )
    
    Mock-Command -CommandName "Get-DataSyncConfig" -ReturnValue ([PSCustomObject]$MockConfig)
    
    # 設定の各セクションもモック化
    if ($MockConfig.ContainsKey("file_paths")) {
        Mock-Command -CommandName "Get-FilePathConfig" -ReturnValue ([PSCustomObject]$MockConfig.file_paths)
    }
    
    if ($MockConfig.ContainsKey("logging")) {
        Mock-Command -CommandName "Get-LoggingConfig" -ReturnValue ([PSCustomObject]$MockConfig.logging)
    }
}

# エラーハンドリングのモック化
function Mock-ErrorHandling {
    param(
        [switch]$BypassErrorHandling,
        [hashtable]$ErrorConfig = @{}
    )
    
    if ($BypassErrorHandling) {
        Mock-Command -CommandName "Invoke-WithErrorHandling" -MockScript {
            param($ScriptBlock, $Category, $Operation, $Context, $CleanupScript)
            
            # エラーハンドリングをバイパスして直接実行
            & $ScriptBlock
        }
    }
    else {
        $defaultErrorConfig = @{
            enabled = $true
            retry_settings = @{
                enabled = $false
                max_attempts = 1
            }
            continue_on_error = @{
                System = $false
                Data = $true
                External = $false
            }
        }
        
        $mergedConfig = $defaultErrorConfig.Clone()
        foreach ($key in $ErrorConfig.Keys) {
            $mergedConfig[$key] = $ErrorConfig[$key]
        }
        
        Mock-Command -CommandName "Get-ErrorHandlingConfig" -ReturnValue ([PSCustomObject]$mergedConfig)
    }
}

# モック呼び出し履歴の取得
function Get-MockCallHistory {
    param(
        [string]$CommandName = ""
    )
    
    if ([string]::IsNullOrEmpty($CommandName)) {
        return $script:MockCallHistory
    }
    
    if ($script:MockCallHistory.ContainsKey($CommandName)) {
        return $script:MockCallHistory[$CommandName]
    }
    
    return @()
}

# キャプチャされたログメッセージの取得
function Get-CapturedLogMessages {
    param(
        [string]$Level = ""
    )
    
    if (-not (Get-Variable -Name "CapturedLogMessages" -Scope Script -ErrorAction SilentlyContinue)) {
        return @()
    }
    
    $messages = $script:CapturedLogMessages
    
    if (-not [string]::IsNullOrEmpty($Level)) {
        $messages = $messages | Where-Object { $_.Level -eq $Level }
    }
    
    return $messages
}

# モックの検証ヘルパー
function Assert-MockCalled {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CommandName,
        
        [int]$Times = -1,
        
        [scriptblock]$ParameterFilter = $null
    )
    
    $callHistory = Get-MockCallHistory -CommandName $CommandName
    
    if ($Times -eq 0) {
        if ($callHistory.Count -gt 0) {
            throw "コマンド '$CommandName' が予期せず呼び出されました ($($callHistory.Count) 回)"
        }
        return $true
    }
    
    if ($Times -gt 0 -and $callHistory.Count -ne $Times) {
        throw "コマンド '$CommandName' の呼び出し回数が期待値と異なります。期待: $Times, 実際: $($callHistory.Count)"
    }
    
    if ($callHistory.Count -eq 0) {
        throw "コマンド '$CommandName' が呼び出されませんでした"
    }
    
    # パラメータフィルタの適用
    if ($ParameterFilter) {
        $filteredCalls = $callHistory | Where-Object { & $ParameterFilter $_.Arguments }
        if ($filteredCalls.Count -eq 0) {
            throw "コマンド '$CommandName' が指定されたパラメータで呼び出されませんでした"
        }
    }
    
    return $true
}

# すべてのモックのリセット
function Reset-AllMocks {
    # モック化されたコマンドの復元
    foreach ($commandName in $script:MockedCommands.Keys) {
        $originalCommand = $script:MockedCommands[$commandName]
        
        if ($originalCommand) {
            # 元のコマンドを復元（グローバル関数として定義されたモックを削除）
            if (Get-Command $commandName -ErrorAction SilentlyContinue) {
                Remove-Item "Function:\$commandName" -ErrorAction SilentlyContinue
            }
        }
    }
    
    # 状態のクリア
    $script:MockedCommands.Clear()
    $script:MockCallHistory.Clear()
    
    # キャプチャされたログメッセージのクリア
    if (Get-Variable -Name "CapturedLogMessages" -Scope Script -ErrorAction SilentlyContinue) {
        $script:CapturedLogMessages = @()
    }
    
    Write-Verbose "すべてのモックをリセットしました"
}

Export-ModuleMember -Function @(
    'Mock-Command',
    'Mock-SqliteCommand', 
    'Mock-FileSystemOperations',
    'Mock-LoggingSystem',
    'Mock-ConfigurationSystem',
    'Mock-ErrorHandling',
    'Get-MockCallHistory',
    'Get-CapturedLogMessages',
    'Assert-MockCalled',
    'Reset-AllMocks'
)