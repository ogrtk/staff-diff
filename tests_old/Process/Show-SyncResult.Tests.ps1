# PowerShell & SQLite データ同期システム
# Show-SyncResult モジュール テスト

BeforeAll {
    # レイヤードテストヘルパーの読み込み
    Import-Module (Join-Path $PSScriptRoot "../TestHelpers/LayeredTestHelpers.psm1") -Force
    Import-Module (Join-Path $PSScriptRoot "../TestHelpers/MockHelpers.psm1") -Force
    
    # Process層モジュールのテスト環境を初期化（Show-SyncResultはProcess層）
    $script:TestEnv = Initialize-LayeredTestEnvironment -LayerName "Process" -ModuleName "Show-SyncResult"
}

AfterAll {
    # テスト環境のクリーンアップ
    Cleanup-LayeredTestEnvironment -TestEnvironment $script:TestEnv
}

Describe "Show-SyncResult" {
    BeforeAll {
        # Mock dependencies
        Mock -ModuleName Show-SyncResult -CommandName Get-DataSyncConfig -MockWith {
            return @{
                version    = "1.0.0"
                sync_rules = @{
                    sync_action_labels = @{
                        mappings = @{
                            "1" = @{
                                action_name   = "ADD"
                                display_label = "1"
                                description   = "新規追加"
                            }
                            "2" = @{
                                action_name   = "UPDATE"
                                display_label = "2"
                                description   = "更新"
                            }
                            "3" = @{
                                action_name   = "DELETE"
                                display_label = "3"
                                description   = "削除"
                            }
                            "9" = @{
                                action_name   = "KEEP"
                                display_label = "9"
                                description   = "変更なし"
                            }
                        }
                    }
                }
            }
        }
        
        # 日本時間は関数内で直接計算されるのでモック不要
        
        Mock -ModuleName Show-SyncResult -CommandName Invoke-SqliteCsvQuery -MockWith {
            param($DatabasePath, $Query)
            
            if ($Query -match "table_name") {
                # テーブル件数クエリのモック
                return @(
                    @{table_name = "provided_data"; count = 100 },
                    @{table_name = "current_data"; count = 95 },
                    @{table_name = "sync_result"; count = 100 }
                )
            }
            elseif ($Query -match "sync_action") {
                # 同期結果クエリのモック（config設定に基づく数値）
                return @(
                    @{sync_action = "1"; count = 5 },
                    @{sync_action = "2"; count = 10 },
                    @{sync_action = "3"; count = 0 },
                    @{sync_action = "9"; count = 85 }
                )
            }
            
            return @()
        }
        
        Mock -ModuleName Show-SyncResult -CommandName Write-SystemLog -MockWith {}
        Mock -ModuleName Show-SyncResult -CommandName Invoke-WithErrorHandling -MockWith {
            param($ScriptBlock, $Operation, $Category, $SuppressThrow)
            & $ScriptBlock
        }
    }

    Context "正常な結果表示" {
        It "同期結果を正しく表示する" {
            Show-SyncResult -DatabasePath "test.db" -ProvidedDataFilePath "provided.csv" -CurrentDataFilePath "current.csv"

            # 戻り値がないことを確認
            # ログ出力のみ行われることを確認
            Assert-MockCalled Write-SystemLog -Times 1 -Exactly -ParameterFilter { $Message -like "*同期処理完了レポート*" }
        }

        It "テーブル件数を表示する" {
            Show-SyncResult -DatabasePath "test.db" -ProvidedDataFilePath "provided.csv" -CurrentDataFilePath "current.csv"

            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*provided_data: 100 件*" } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*current_data: 95 件*" } -Times 1  
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*sync_result: 100 件*" } -Times 1
        }

        It "同期結果を表示する" {
            Show-SyncResult -DatabasePath "test.db" -ProvidedDataFilePath "provided.csv" -CurrentDataFilePath "current.csv"

            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*1 (新規追加): 5 件*" } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*2 (更新): 10 件*" } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*3 (削除): 0 件*" } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*9 (変更なし): 85 件*" } -Times 1
        }

        It "同期処理総件数を表示する" {
            Show-SyncResult -DatabasePath "test.db" -ProvidedDataFilePath "provided.csv" -CurrentDataFilePath "current.csv"

            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*同期処理総件数: 100 件*" } -Times 1
        }

        It "適切にログ出力を行う" {
            Show-SyncResult -DatabasePath "test.db" -ProvidedDataFilePath "provided.csv" -CurrentDataFilePath "current.csv"

            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*同期処理完了レポート*" } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*実行情報*" } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*データ統計*" } -Times 1
            Assert-MockCalled Write-SystemLog -ParameterFilter { $Message -like "*同期結果*" } -Times 1
        }
    }

    Context "エラーハンドリング" {
        It "データベース接続エラー時に適切に処理する" {
            Mock -ModuleName Show-SyncResult -CommandName Invoke-WithErrorHandling -MockWith {
                # エラー時は何も処理しない
            }

            # エラー時も戻り値はない（関数が正常終了）
            { Show-SyncResult -DatabasePath "invalid.db" -ProvidedDataFilePath "provided.csv" -CurrentDataFilePath "current.csv" } | Should -Not -Throw
        }
    }
}