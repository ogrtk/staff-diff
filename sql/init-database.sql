-- SQLite データベース初期化スクリプト
-- 職員データ管理システム用テーブル定義

-- 職員情報テーブル
CREATE TABLE IF NOT EXISTS staff_info (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id TEXT NOT NULL UNIQUE,
    card_number TEXT,
    name TEXT NOT NULL,
    department TEXT,
    position TEXT,
    email TEXT,
    phone TEXT,
    hire_date DATE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 職員マスタテーブル
CREATE TABLE IF NOT EXISTS staff_master (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id TEXT NOT NULL UNIQUE,
    card_number TEXT,
    name TEXT NOT NULL,
    department TEXT,
    position TEXT,
    email TEXT,
    phone TEXT,
    hire_date DATE,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- 同期結果テーブル
CREATE TABLE IF NOT EXISTS sync_result (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    employee_id TEXT NOT NULL,
    card_number TEXT,
    name TEXT NOT NULL,
    department TEXT,
    position TEXT,
    email TEXT,
    phone TEXT,
    hire_date DATE,
    sync_action TEXT NOT NULL, -- 'ADD', 'UPDATE', 'DELETE', 'KEEP'
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- インデックス作成
CREATE INDEX IF NOT EXISTS idx_staff_info_employee_id ON staff_info(employee_id);
CREATE INDEX IF NOT EXISTS idx_staff_master_employee_id ON staff_master(employee_id);
CREATE INDEX IF NOT EXISTS idx_sync_result_employee_id ON sync_result(employee_id);

-- 更新日時の自動更新トリガー
CREATE TRIGGER IF NOT EXISTS update_staff_info_timestamp 
    AFTER UPDATE ON staff_info
BEGIN
    UPDATE staff_info SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;

CREATE TRIGGER IF NOT EXISTS update_staff_master_timestamp 
    AFTER UPDATE ON staff_master
BEGIN
    UPDATE staff_master SET updated_at = CURRENT_TIMESTAMP WHERE id = NEW.id;
END;