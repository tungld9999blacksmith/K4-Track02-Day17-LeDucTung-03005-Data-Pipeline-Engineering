# K4-Track02-Day17 — Report cá nhân

Phần phân tích tối đa một trang, không tính output ở phần 5.
Định dạng tham chiếu và phạm vi tính trang: [SUBMISSION.md](../docs/SUBMISSION.md).

- **Họ tên / MSSV:** Lê Đức Tùng / 03005
- **Repo:** K4-Track02-Day17-LeDucTung-03005-DataPipelineEngineering
- **Commit bài nộp:** (sẽ cập nhật sau)
- **AI đã dùng và phạm vi hỗ trợ:** Claude Haiku 4.5 - Trao đổi kiến thức về CDC/LSN/batch ordering, giải thích DuckDB SQL syntax (QUALIFY, MERGE, JSON path), thảo luận về pipeline design issues (idempotency, keyed writes, duplicate detection) để xác định bugs
- **Nguồn tham khảo khác:** Day 17 deck - Silver keyed writes, CDC delete handling, late data lookback

## 1. Ba lỗi

Mỗi lỗi 4 dòng. Triệu chứng = thứ bạn *thấy* đầu tiên (check nào fail, số nào lạ,
checksum nào lệch) — không phải cách sửa.

| | Lỗi Silver | Lỗi late data | Lỗi xoá (CDC) |
|---|---|---|---|
| **Triệu chứng** | `make verify` fail: silver_tickets_uniqueness — 24 rows cho 12 tickets (expected 12). T-91 có 3 hàng: ('low', 'open', None), ('high', 'open', None), ('high', 'closed', 'bug'). | `test_feature_daily_reconciles_with_full_recompute` fail: checksum Gold `c50b8851affe` ≠ full recompute `8630e04a61d1`; 4 dòng lệch (u05/08-12, u07/08-11, u07/08-13, u02/08-14). u05 ngày 08-12 = `(2, 1, 0)` thay vì `(5, 3, 1)` (n_events, n_clicks, n_feedback_down). | |
| **Nguyên nhân gốc** | `upsert_silver_tickets()` dùng `INSERT` (line 82-86) không kiểm tra LSN. Nếu run batch cũ sau batch mới, sẽ INSERT duplicate rows. Ví dụ: T-91 (LSN=101) đã ở Silver, run batch 08-10 INSERT T-91 (LSN=100) lại → 2 hàng; rerun batch 08-10 lần 2 → 3 hàng. | `config.LOOKBACK_DAYS = 0` (giả định event đến trong vài giây), nhưng đo từ Bronze p99 = 3 ngày. Mỗi lần chạy chỉ tính lại partition của chính ngày đó → event đến trễ (u05: xảy ra 08-12, đến 08-15) vào Silver nhưng partition `event_date` cũ không bao giờ được tính lại. | |
| **Cách sửa** (file, vài dòng) | File: `pipeline/silver.py`, hàm `upsert_silver_tickets()` (lines 79-106). Đổi `INSERT` thành `MERGE` với LSN guard: `WHEN MATCHED AND s._lsn > t._lsn THEN UPDATE SET...` (chỉ update nếu LSN mới hơn), `WHEN MATCHED AND s._lsn <= t._lsn THEN DO NOTHING` (không tạo duplicate), `WHEN NOT MATCHED THEN INSERT VALUES (...)` (insert ticket mới). | `pipeline/config.py`: `LOOKBACK_DAYS = 0` → `3` (= ceil(p99) đo bằng `make lateness`). `build_feature_daily()` giữ nguyên: mỗi lần chạy DELETE + INSERT các partition `[day−3, day]` theo `event_time` từ toàn bộ Silver. | |
| **Khái niệm trên slide** | **Idempotent** (slide "Idempotent"): re-run batch cũ sau batch mới → state không thay đổi. **Một hàng = một thực thể** (slide "Silver — keyed"): 1 ticket_id = 1 row trong silver_tickets. **Idempotent technique: Ghi theo khóa (keyed write/upsert)** (slide "Four ways to write idempotent"): MERGE với merge_update_condition (LSN guard) → ensure chỉ update nếu change mới hơn. | **Late data**: event time ≠ ingest time; lookback = ceil(P99) đo từ Bronze, không đoán. **Idempotent technique: overwrite-partition**: xoá và tính lại partition từ Silver → chạy lại bao nhiêu lần cũng cùng kết quả, và nhận được event đến muộn. | |

## 2. Các con số

- P99 lateness đo từ Bronze: `3.00` ngày (p50 = 0, p95 = 2.90, max = 3, n = 43) → `LOOKBACK_DAYS = 3`
- `submission/checksums.txt`: (sẽ cập nhật sau CP4)
- `make parity`: (sẽ cập nhật sau CP5)

## 3. Lựa chọn công cụ / kỹ thuật (mỗi dòng một câu "vì sao")

- MERGE theo khoá cho `silver_tickets`, overwrite-partition cho `gold_feature_daily`: mỗi hàng Silver là một thực thể có khoá, LSN quyết định bản nào mới hơn; mỗi hàng Gold là tổng hợp của cả partition nên không cập nhật từng hàng được, xoá rồi tính lại từ Silver vừa idempotent vừa nhận event đến muộn. Lookback = 3 vì p99 = max = 3 ngày: phủ 100% seed, mỗi lần chạy chỉ tính lại 4 partition.
- Tombstone thay vì xoá hẳn hàng trong Silver:
- Snapshot training dựng lại từ Bronze "as of" ngày đó, không sửa snapshot cũ:
- DuckDB (lite) / dbt (track dbt) cho bài toán cỡ này, chứ không phải Spark:

## 4. Hai câu hỏi suy ngẫm

1. Snapshot `v2026-08-12`..`v2026-08-14` vẫn chứa văn bản của T-97 (đã bị xoá ngày
   08-15). "Snapshot bất biến" và "quyền được xoá dữ liệu" mâu thuẫn — bạn xử lý thế nào?
2. Regex che được email và số điện thoại, nhưng tên "Nguyễn Văn An" vẫn còn. Bạn sẽ
   đặt chốt PII nào, ở tầng nào, và đo nó ra sao?

## 5. Output (dán nguyên văn)

### make verify (CP2 - Silver checks PASS)
```text
=== verify.py – Day 17 pipeline contracts ===
  [OK ] Bronze  every daily batch landed as Parquet (7 days x 3 sources)
  [OK ] Bronze  re-landing a batch is a no-op (append-only, no duplicate file)
  [OK ] Bronze  Bronze keeps the raw truth: Kafka tombstone + redelivered events are still there
  [OK ] Silver  silver_tickets has exactly one row per ticket_id
  [OK ] Silver  T-91 shows its latest state: high / closed / bug
```

### make test (27 passed, 7 failed - bugs #2 #3 expected)
```text
27 passed, 7 failed in 4.31s
PASSED: test_silver_tickets_unique, test_silver_tickets_latest_state, ... (Silver tests all pass)
FAILED: test_feature_daily_reconciles_with_full_recompute (bug #2 - lateness)
FAILED: test_deleted_ticket_leaves_training_and_rag (bug #3 - CDC delete)
```

### make lateness (CP2 - Đo P99)
```text
event lateness over 43 Bronze records (calendar days): p50=0.00 p95=2.90 p99=3.00 max=3
-> lookback must be >= ceil(p99) = 3 day(s); config.LOOKBACK_DAYS = 0
```

### make rerun3, make dbt, make parity
(Sẽ cập nhật sau CP4-CP5)

Nếu dùng PowerShell, ghi lệnh tương đương và output thực tế theo [SUBMISSION.md](../docs/SUBMISSION.md).
Nếu làm bonus, thêm output B1 hoặc đường dẫn bằng chứng B2 ở cuối phần này.
