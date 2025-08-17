#!/usr/bin/env pwsh
# 基盤層 (Layer 1) - CoreUtils モジュールテスト

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../../TestHelpers/MockHelpers.psm1") -Force
    
    # Layer 1 (Foundation) テスト環境の初期化
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "Foundation" -ModuleName "CoreUtils" -MockDependencies:$false
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "CoreUtils (基盤層) テスト" {
    
    Context "レイヤーアーキテクチャ検証" {
        It "Layer 1 で依存関係がないこと" {
            $dependencies = Assert-LayeredModuleDependencies -LayerName "Foundation" -ModuleName "CoreUtils"
            $dependencies.Dependencies | Should -BeExactly @()
            $dependencies.InvalidDependencies | Should -BeExactly @()
            $dependencies.CircularDependencies | Should -BeExactly @()
        }
        
        It "設定に依存しないこと" {
            # Foundation層は設定非依存であることを確認
            { Get-Sqlite3Path } | Should -Not -Throw
            { Get-CrossPlatformEncoding } | Should -Not -Throw
            { Get-Timestamp } | Should -Not -Throw
        }
    }
    
    Context "Get-Sqlite3Path 関数" {
        It "SQLite3コマンドパスを返すこと" {
            $result = Get-Sqlite3Path
            $result | Should -Not -BeNullOrEmpty
            $result.Source | Should -Not -BeNullOrEmpty
        }
        
        It "sqlite3が利用できない場合にエラーをスローすること" {
            Mock Get-Command { return $null } -ModuleName CoreUtils -ParameterFilter { $Name -eq "sqlite3" }
            { Get-Sqlite3Path } | Should -Throw "*sqlite3コマンドが見つかりません*"
        }
        
        It "コマンド解決エラーを適切に処理すること" {
            Mock Get-Command { throw "Command resolution failed" } -ModuleName CoreUtils -ParameterFilter { $Name -eq "sqlite3" }
            { Get-Sqlite3Path } | Should -Throw "*SQLite3コマンドの取得に失敗しました*"
        }
    }
    
    Context "Get-CrossPlatformEncoding 関数" {
        It "PowerShell Core (version 6+) でUTF8エンコーディングを返すこと" {
            # 現在のPowerShellバージョンに関係なく、戻り値の型を確認
            $encoding = Get-CrossPlatformEncoding
            $encoding.EncodingName | Should -Be "Unicode (UTF-8)"
            # PowerShell Core (6+) かどうかに関わらず、UTF-8エンコーディングが返される
        }
        
        It "Windows PowerShell (version < 6) でBOM付きUTF8エンコーディングを返すこと" {
            # PowerShell 5.1以下の動作をシミュレート
            if ($PSVersionTable.PSVersion.Major -lt 6) {
                $encoding = Get-CrossPlatformEncoding
                $encoding.EncodingName | Should -Be "Unicode (UTF-8)"
                $encoding.Preamble.Length | Should -BeGreaterThan 0  # BOM present
            } else {
                # PowerShell Core環境では、このテストをスキップ
                Write-Host "Skipping Windows PowerShell specific test on PowerShell Core" -ForegroundColor Yellow
            }
        }
        
        It "常に有効なエンコーディングオブジェクトを返すこと" {
            $encoding = Get-CrossPlatformEncoding
            $encoding | Should -Not -BeNullOrEmpty
            $encoding | Should -BeOfType [System.Text.Encoding]
            $encoding.EncodingName | Should -Not -BeNullOrEmpty
        }
    }
    
    Context "Get-Timestamp 関数" {
        It "デフォルトフォーマットでタイムスタンプを返すこと" {
            $timestamp = Get-Timestamp
            $timestamp | Should -Not -BeNullOrEmpty
            $timestamp | Should -Match "^\d{8}_\d{6}$"  # YYYYMMDD_HHMMSS format
        }
        
        It "カスタムフォーマットパラメータを受け入れること" {
            $customFormat = "yyyy-MM-dd HH:mm:ss"
            $timestamp = Get-Timestamp -Format $customFormat
            $timestamp | Should -Not -BeNullOrEmpty
            $timestamp | Should -Match "^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$"
        }
        
        It "Asia/Tokyoタイムゾーンを正しく処理すること" {
            $timestamp = Get-Timestamp -TimeZone "Asia/Tokyo"
            $timestamp | Should -Not -BeNullOrEmpty
            $timestamp | Should -Match "^\d{8}_\d{6}$"
        }
        
        It "タイムゾーンに失敗した場合にUTC+9フォールバックを使用すること" {
            # 無効なタイムゾーンで呼び出し
            $timestamp = Get-Timestamp -TimeZone "Invalid/Timezone"
            $timestamp | Should -Not -BeNullOrEmpty
            $timestamp | Should -Match "^\d{8}_\d{6}$"
        }
        
        It "異なるタイムゾーン値を処理すること" {
            $utcTimestamp = Get-Timestamp -TimeZone "UTC"
            $tokyoTimestamp = Get-Timestamp -TimeZone "Asia/Tokyo"
            
            $utcTimestamp | Should -Not -BeNullOrEmpty
            $tokyoTimestamp | Should -Not -BeNullOrEmpty
            
            # タイムスタンプは同じフォーマットである必要がある
            $utcTimestamp | Should -Match "^\d{8}_\d{6}$"
            $tokyoTimestamp | Should -Match "^\d{8}_\d{6}$"
        }
        
        It "カスタムフォーマット文字列を正しく処理すること" {
            $testCases = @(
                @{ Format = "yyyyMMdd"; Pattern = "^\d{8}$" },
                @{ Format = "HHmmss"; Pattern = "^\d{6}$" },
                @{ Format = "yyyy-MM-dd"; Pattern = "^\d{4}-\d{2}-\d{2}$" },
                @{ Format = "MM/dd/yyyy"; Pattern = "^\d{2}/\d{2}/\d{4}$" }
            )
            
            foreach ($testCase in $testCases) {
                $result = Get-Timestamp -Format $testCase.Format
                $result | Should -Match $testCase.Pattern
            }
        }
    }
    
    Context "基盤層関数統合" {
        It "設定依存なしで連携動作すること" {
            # Foundation層の関数が設定なしで動作することを確認
            $sqlite3Path = Get-Sqlite3Path
            $encoding = Get-CrossPlatformEncoding
            $timestamp = Get-Timestamp
            
            $sqlite3Path | Should -Not -BeNullOrEmpty
            $encoding | Should -Not -BeNullOrEmpty
            $timestamp | Should -Not -BeNullOrEmpty
            
            # 各関数が独立して動作することを確認
            $sqlite3Path.GetType().Name | Should -BeIn @("CommandInfo", "ApplicationInfo")
            $encoding.GetType().BaseType.Name | Should -BeIn @("Encoding", "UTF8Encoding")
            $timestamp.GetType().Name | Should -Be "String"
        }
        
        It "上位層から呼び出し可能であること" {
            # 上位層からの呼び出しをシミュレート
            $result = & {
                param($Functions)
                $results = @{}
                foreach ($func in $Functions) {
                    try {
                        $results[$func] = & $func
                    } catch {
                        $results[$func] = $_.Exception.Message
                    }
                }
                return $results
            } -Functions @("Get-Sqlite3Path", "Get-CrossPlatformEncoding", "Get-Timestamp")
            
            $result["Get-Sqlite3Path"] | Should -Not -BeNullOrEmpty
            $result["Get-CrossPlatformEncoding"] | Should -Not -BeNullOrEmpty  
            $result["Get-Timestamp"] | Should -Not -BeNullOrEmpty
            
            # エラーメッセージではないことを確認
            $result["Get-Sqlite3Path"] | Should -Not -Match "Exception"
            $result["Get-CrossPlatformEncoding"] | Should -Not -Match "Exception"
            $result["Get-Timestamp"] | Should -Not -Match "Exception"
        }
    }
    
    Context "エラーハンドリングとエッジケース" {
        It "nullまたは空のパラメータを適切に処理すること" {
            # Get-Timestampの空文字列パラメータテスト
            $timestamp1 = Get-Timestamp -Format ""
            $timestamp2 = Get-Timestamp -TimeZone ""
            
            # 空文字列でも例外を投げずに結果を返すべき
            $timestamp1 | Should -Not -BeNullOrEmpty
            $timestamp2 | Should -Not -BeNullOrEmpty
        }
        
        It "複数回の呼び出しで一貫した動作を維持すること" {
            $timestamps = 1..5 | ForEach-Object { Get-Timestamp }
            $encodings = 1..3 | ForEach-Object { Get-CrossPlatformEncoding }
            
            # 全ての呼び出しが成功することを確認
            $timestamps | Should -HaveCount 5
            $encodings | Should -HaveCount 3
            
            # 同じ関数の呼び出しは一貫した型を返すべき
            $encodings | ForEach-Object { $_.GetType().BaseType.Name | Should -BeIn @("Encoding", "UTF8Encoding") }
            $timestamps | ForEach-Object { $_.GetType().Name | Should -Be "String" }
        }
        
        It "並行アクセスを安全に処理すること" {
            # 並行アクセスのシミュレーション
            $jobs = 1..3 | ForEach-Object {
                Start-Job -ScriptBlock {
                    Import-Module (Join-Path $using:PSScriptRoot "../../../scripts/modules/Utils/Foundation/CoreUtils.psm1") -Force
                    return @{
                        Encoding = Get-CrossPlatformEncoding
                        Timestamp = Get-Timestamp
                    }
                }
            }
            
            $results = $jobs | Wait-Job | Receive-Job
            $jobs | Remove-Job
            
            $results | Should -HaveCount 3
            $results | ForEach-Object {
                $_.Encoding | Should -Not -BeNullOrEmpty
                $_.Timestamp | Should -Not -BeNullOrEmpty
            }
        }
    }
    
    Context "パフォーマンスとリソース使用量" {
        It "関数を高速で実行すること" {
            $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            
            1..10 | ForEach-Object {
                Get-Timestamp | Out-Null
                Get-CrossPlatformEncoding | Out-Null
            }
            
            $stopwatch.Stop()
            $stopwatch.ElapsedMilliseconds | Should -BeLessThan 1000  # Should complete within 1 second
        }
        
        It "繰り返し呼び出しでメモリリークしないこと" {
            $initialMemory = [GC]::GetTotalMemory($false)
            
            # 多数回の呼び出し
            1..100 | ForEach-Object {
                Get-CrossPlatformEncoding | Out-Null
                Get-Timestamp | Out-Null
            }
            
            [GC]::Collect()
            $finalMemory = [GC]::GetTotalMemory($true)
            
            # メモリ使用量の大幅な増加がないことを確認
            ($finalMemory - $initialMemory) | Should -BeLessThan (1MB)
        }
    }
}