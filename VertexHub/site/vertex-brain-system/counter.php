<?php
declare(strict_types=1);

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate, max-age=0');

$base = __DIR__ . DIRECTORY_SEPARATOR . 'data';
if (!is_dir($base)) {
    @mkdir($base, 0750, true);
}

$count = null;
$backend = 'none';

try {
    if (class_exists('SQLite3')) {
        $dbPath = $base . DIRECTORY_SEPARATOR . 'counter.sqlite3';
        $db = new SQLite3($dbPath);
        $db->busyTimeout(3000);
        $db->exec('PRAGMA journal_mode=WAL;');
        $db->exec('CREATE TABLE IF NOT EXISTS counters (
            page_key TEXT PRIMARY KEY,
            count INTEGER NOT NULL DEFAULT 0,
            updated_at TEXT NOT NULL
        )');

        $db->exec('BEGIN IMMEDIATE;');
        $stmt = $db->prepare(
            'INSERT INTO counters(page_key, count, updated_at)
             VALUES (:page_key, 1, :updated_at)
             ON CONFLICT(page_key) DO UPDATE SET
               count = count + 1,
               updated_at = excluded.updated_at'
        );
        $stmt->bindValue(':page_key', 'vertex-brain-system', SQLITE3_TEXT);
        $stmt->bindValue(':updated_at', gmdate('c'), SQLITE3_TEXT);
        $stmt->execute();

        $stmt = $db->prepare('SELECT count FROM counters WHERE page_key = :page_key');
        $stmt->bindValue(':page_key', 'vertex-brain-system', SQLITE3_TEXT);
        $row = $stmt->execute()->fetchArray(SQLITE3_ASSOC);
        $count = isset($row['count']) ? (int)$row['count'] : null;

        $db->exec('COMMIT;');
        $db->close();
        $backend = 'sqlite';
    }
} catch (Throwable $e) {
    $count = null;
}

if ($count === null) {
    $file = $base . DIRECTORY_SEPARATOR . 'counter.txt';
    $fp = @fopen($file, 'c+');
    if ($fp === false) {
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'counter storage unavailable']);
        exit;
    }

    if (!flock($fp, LOCK_EX)) {
        fclose($fp);
        http_response_code(500);
        echo json_encode(['ok' => false, 'error' => 'counter lock failed']);
        exit;
    }

    rewind($fp);
    $raw = trim((string)stream_get_contents($fp));
    $count = ctype_digit($raw) ? (int)$raw : 0;
    $count++;

    ftruncate($fp, 0);
    rewind($fp);
    fwrite($fp, (string)$count);
    fflush($fp);
    flock($fp, LOCK_UN);
    fclose($fp);
    $backend = 'file';
}

echo json_encode([
    'ok' => true,
    'count' => $count,
    'backend' => $backend
], JSON_UNESCAPED_SLASHES);
