# K4-Track02-Day17 — Report cá nhân

Phần phân tích tối đa một trang, không tính output ở phần 5.
Định dạng tham chiếu và phạm vi tính trang: [SUBMISSION.md](../docs/SUBMISSION.md).

- **Họ tên / MSSV:** Lê Đức Tùng / 03005
- **Repo:** K4-Track02-Day17-LeDucTung-03005-DataPipelineEngineering
- **Commit bài nộp:** (điền hash commit cuối sau khi push)
- **AI đã dùng và phạm vi hỗ trợ:** Claude (Haiku 4.5, Opus 5.5) qua Claude Code — trao đổi kiến thức về CDC/LSN/batch ordering, giải thích DuckDB SQL syntax (QUALIFY, MERGE, JSON path), thảo luận về pipeline design issues (idempotency, keyed writes, duplicate detection) để xác định bugs; đề xuất và sửa code (MERGE ở `silver.py`, khoá delete ở `staging.py`), chạy kiểm tra và soạn nháp REPORT. Tôi đã review từng thay đổi và chạy lại toàn bộ kiểm tra.
- **Nguồn tham khảo khác:** Day 17 deck — Silver keyed writes, CDC delete handling, late data lookback

## 1. Ba lỗi

| | Lỗi Silver | Lỗi late data | Lỗi xoá (CDC) |
|---|---|---|---|
| **Triệu chứng** | `verify`: `silver_tickets` có **24 rows cho 12 tickets**; T-91 có 3 hàng `('low','open',None)`, `('high','open',None)`, `('high','closed','bug')`. | `test_feature_daily_reconciles_with_full_recompute` fail: checksum Gold `c50b8851affe` ≠ full recompute `8630e04a61d1`; 4 dòng lệch (u05/08-12, u07/08-11, u07/08-13, u02/08-14); u05 ngày 08-12 = `(2, 1, 0)` thay vì `(5, 3, 1)`. | `verify` crash ngay ở check T-97 (in ra subject tiếng Việt của T-97 — ticket vẫn còn nguyên); `test_cdc_delete_becomes_tombstone` fail; T-97 còn 1 hàng trong snapshot `v2026-08-16`; `gold_doc_chunks` có 9 chunk thay vì 8. |
| **Nguyên nhân gốc** | `upsert_silver_tickets()` dùng `INSERT`: mỗi batch có thay đổi lại thêm một hàng mới cho cùng ticket, không có khoá; chạy lại batch cũ còn chèn thêm bản cũ. | `config.LOOKBACK_DAYS = 0` trong khi p99 lateness đo từ Bronze là 3 ngày: mỗi lần chạy chỉ tính lại partition của chính ngày đó, nên event đến trễ vào Silver nhưng partition `event_date` cũ không được tính lại. | `staging.ticket_changes_sql()` lấy `ticket_id` từ `after`; với `op = 'd'` thì `after = null` → `ticket_id = NULL` → bị `WHERE ticket_id IS NOT NULL` loại → Silver/Gold không bao giờ thấy lệnh xoá. |
| **Cách sửa** | `pipeline/silver.py`: `INSERT` → `MERGE ... ON ticket_id`; `WHEN MATCHED AND s._lsn > t._lsn THEN UPDATE`, `WHEN MATCHED AND s._lsn <= t._lsn THEN DO NOTHING`, `WHEN NOT MATCHED THEN INSERT`. | `pipeline/config.py`: `LOOKBACK_DAYS = 0` → `3` (= ceil(p99)). `build_feature_daily()` giữ nguyên: DELETE + INSERT partition `[day−3, day]` theo `event_time`. | `pipeline/staging.py`: `ticket_id` lấy từ khoá Kafka `j->'key'->>'ticket_id'` (luôn có, kể cả khi `after = null`). Logic tombstone ở Silver và lọc ở Gold đã có sẵn nên tự chạy đúng. |
| **Khái niệm trên slide** | **Idempotent**; **Một hàng = một thực thể** (Silver — keyed); **Idempotent technique: ghi theo khoá (upsert)** với LSN guard. | **Late data**: event time ≠ ingest time, lookback = ceil(P99) đo từ Bronze; **overwrite-partition**. | **Log-based CDC** (`before/after/op/lsn`, CDC delete ≠ Kafka tombstone); **Xoá phải lan** (Silver → training snapshot mới nhất → RAG). |

## 2. Các con số

- P99 lateness đo từ Bronze: `3.00` ngày (p50 = 0, p95 = 2.90, max = 3, n = 43) → `LOOKBACK_DAYS = 3`
- `submission/checksums.txt`: **PASS** — Gold checksum: `39e115c510ecdf526800eac227158a4f`
- `make parity`: **PARITY** (`silver_tickets` `3c15dfd43701`, `gold_feature_daily` `8630e04a61d1`)

## 3. Lựa chọn công cụ / kỹ thuật (mỗi dòng một câu "vì sao")

- MERGE theo khoá cho `silver_tickets`, overwrite-partition cho `gold_feature_daily`: mỗi hàng Silver là một thực thể có khoá và LSN quyết định bản nào mới hơn; mỗi hàng Gold là tổng hợp của cả partition nên không cập nhật từng hàng được — xoá rồi tính lại từ Silver vừa idempotent vừa nhận event đến muộn. Lookback = 3 vì p99 = max = 3 ngày: phủ 100% seed, mỗi lần chạy chỉ tính lại 4 partition.
- Tombstone thay vì xoá hẳn hàng trong Silver: hàng tombstone giữ LSN của lệnh xoá, nên khi replay batch cũ MERGE gặp `s._lsn <= t._lsn` và bỏ qua; nếu xoá hẳn, replay sẽ rơi vào `NOT MATCHED` và "hồi sinh" ticket kèm PII. Đánh đổi: hàng tombstone (chỉ còn khoá + metadata) tồn tại mãi.
- Snapshot training dựng lại từ Bronze "as of" ngày đó, không sửa snapshot cũ: mô hình đã train trên `v<ngày>` phải tái lập được; dựng từ Bronze với `_batch_id <= ngày` cho kết quả giống hệt mỗi lần chạy, và `SnapshotImmutableError` chặn việc ghi đè âm thầm.
- DuckDB (lite) / dbt (track dbt) cho bài toán cỡ này, chứ không phải Spark: dữ liệu vài trăm dòng, chạy một máy, zero-key; DuckDB có MERGE/QUALIFY/Parquet, dbt thêm contract, data test, unit test và microbatch — Spark chỉ thêm chi phí cluster mà không có lợi ích ở quy mô này.

## 4. Hai câu hỏi suy ngẫm

1. **Snapshot bất biến vs quyền được xoá.** Quyền xoá thắng: bất biến là để tái lập, không phải để giữ dữ liệu người đã yêu cầu xoá. Tôi sẽ tách PII khỏi snapshot — snapshot chỉ lưu `ticket_id` và đặc trưng đã khử danh tính, văn bản để ở kho riêng có thể xoá (hoặc mã hoá theo user rồi huỷ khoá — crypto-shredding). Nếu snapshot đã chứa văn bản, phát hành phiên bản sửa (vd. `v2026-08-12-r1`) bỏ T-97, đánh dấu bản cũ thu hồi, xoá bản cũ khỏi lưu trữ, ghi audit log, và đưa các model train trên bản cũ vào danh sách cần train lại.
2. **Chốt PII cho tên người.** Đặt chốt ở ranh giới Bronze → Silver (cùng chỗ `mask_pii`), vì đó là lần đầu dữ liệu rời vùng raw có kiểm soát truy cập. Regex không bắt được tên, nên thêm NER tiếng Việt (vd. underthesea/Presidio có recognizer tiếng Việt) để thay bằng `<NAME>`, kèm danh sách tên đã biết từ bảng user. Đo bằng một tập mẫu gán nhãn tay: recall (tỷ lệ PII bị che) là chỉ số chính, precision để không che nhầm; thêm một check trong `verify` quét Silver/Gold và fail nếu còn tên trong tập kiểm tra.

## 5. Output (dán nguyên văn)

Chạy trên Windows PowerShell bằng `make.ps1`, với `$env:PYTHONIOENCODING = 'utf-8'` (nếu thiếu, `verify` crash vì không in được ký tự tiếng Việt trên console cp1252).

```text
PS> .\make.ps1 verify
=== verify.py — Day 17 pipeline contracts ===
  [OK ] Bronze  every daily batch landed as Parquet (7 days x 3 sources)
  [OK ] Bronze  re-landing a batch is a no-op (append-only, no duplicate file)
  [OK ] Bronze  Bronze keeps the raw truth: Kafka tombstone + redelivered events are still there
  [OK ] Silver  silver_tickets has exactly one row per ticket_id
  [OK ] Silver  T-91 shows its latest state: high / closed / bug
  [OK ] Silver  deleted ticket T-97 is a tombstone: is_deleted and no personal data left
  [OK ] Silver  no email / phone number survives past Bronze
  [OK ] Silver  silver_events has one row per event_id (Kafka redeliveries removed)
  [OK ] Silver  2 malformed events quarantined with a reason; the run did not halt
  [OK ] Gold    gold_feature_daily reconciles with a full recompute from Silver
  [OK ] Gold    u05's offline events of 08-12 (arrived 08-15) are counted on 08-12
  [OK ] Gold    LOOKBACK_DAYS covers measured P99 lateness (p99=3.00 days)
  [OK ] Gold    training set uses point-in-time priority (T-91 created as 'low')
  [OK ] Gold    late feedback creates a NEW snapshot version; the old one is untouched
  [OK ] Gold    latest training snapshot excludes the deleted ticket T-97
  [OK ] Gold    deletes propagate to the RAG index: no chunk of T-97
  [OK ] Gold    gold_doc_chunks: one row per chunk, and a re-run embeds 0 new chunks
  [OK ] Rerun   re-run 2026-08-12 three times -> Gold checksum identical to a fresh build

RESULT: 18/18 checks — ALL PASS
re-run checksums written to submission/checksums.txt

PS> .\make.ps1 test
..................................                                       [100%]
34 passed in 4.29s

PS> .\make.ps1 rerun3
# Lab 17 — re-run check for 2026-08-12

run                     gold_feature_daily    gold_training_set     gold_doc_chunks       gold (combined)
fresh build             8630e04a61d1          9370ca77af23          cb9ebd12fdcc          39e115c510ecdf526800eac227158a4f
re-run #1 of 2026-08-12 8630e04a61d1          9370ca77af23          cb9ebd12fdcc          39e115c510ecdf526800eac227158a4f
re-run #2 of 2026-08-12 8630e04a61d1          9370ca77af23          cb9ebd12fdcc          39e115c510ecdf526800eac227158a4f
re-run #3 of 2026-08-12 8630e04a61d1          9370ca77af23          cb9ebd12fdcc          39e115c510ecdf526800eac227158a4f

RESULT: PASS — 3 re-runs, identical checksums

PS> .\make.ps1 lateness
event lateness over 43 Bronze records (calendar days): p50=0.00 p95=2.90 p99=3.00 max=3
-> lookback must be >= ceil(p99) = 3 day(s); config.LOOKBACK_DAYS = 3

PS> .\make.ps1 dbt
18:51:56  Running with dbt=1.12.5
18:51:56  Registered adapter: duckdb=1.11.0
18:51:57  Unable to do partial parsing because saved manifest not found. Starting full parse.
18:52:00  Found 5 models, 13 data tests, 2 sources, 502 macros, 1 unit test
18:52:00
18:52:00  Concurrency: 1 threads (target='dev')
18:52:00
18:52:02  1 of 19 START sql view model main.stg_events ................................... [RUN]
18:52:02  1 of 19 OK created sql view model main.stg_events .............................. [OK in 0.16s]
18:52:02  2 of 19 START sql view model main.stg_ticket_changes ........................... [RUN]
18:52:02  2 of 19 OK created sql view model main.stg_ticket_changes ...................... [OK in 0.06s]
18:52:02  3 of 19 START sql incremental model main.silver_events ......................... [RUN]
18:52:02  3 of 19 OK created sql incremental model main.silver_events .................... [OK in 0.18s]
18:52:02  4 of 19 START unit_test silver_tickets::silver_tickets_latest_change_wins_and_delete_is_tombstone  [RUN]
18:52:02  4 of 19 PASS silver_tickets::silver_tickets_latest_change_wins_and_delete_is_tombstone  [PASS in 0.32s]
18:52:02  8 of 19 START sql incremental model main.silver_tickets ........................ [RUN]
18:52:03  8 of 19 OK created sql incremental model main.silver_tickets ................... [OK in 0.19s]
18:52:03  5 of 19 START test not_null_silver_events_event_id ............................. [RUN]
18:52:03  5 of 19 PASS not_null_silver_events_event_id ................................... [PASS in 0.09s]
18:52:03  6 of 19 START test not_null_silver_events_user_id .............................. [RUN]
18:52:03  6 of 19 PASS not_null_silver_events_user_id .................................... [PASS in 0.04s]
18:52:03  7 of 19 START test unique_silver_events_event_id ............................... [RUN]
18:52:03  7 of 19 PASS unique_silver_events_event_id ..................................... [PASS in 0.04s]
18:52:03  9 of 19 START test accepted_values_silver_tickets_category__bug__billing__other  [RUN]
18:52:03  9 of 19 PASS accepted_values_silver_tickets_category__bug__billing__other ...... [PASS in 0.04s]
18:52:03  10 of 19 START test accepted_values_silver_tickets_priority__low__medium__high . [RUN]
18:52:03  10 of 19 PASS accepted_values_silver_tickets_priority__low__medium__high ....... [PASS in 0.03s]
18:52:03  11 of 19 START test accepted_values_silver_tickets_status__open__pending__closed  [RUN]
18:52:03  11 of 19 PASS accepted_values_silver_tickets_status__open__pending__closed ..... [PASS in 0.03s]
18:52:03  12 of 19 START test not_null_silver_tickets__lsn ............................... [RUN]
18:52:03  12 of 19 PASS not_null_silver_tickets__lsn ..................................... [PASS in 0.03s]
18:52:03  13 of 19 START test not_null_silver_tickets_is_deleted ......................... [RUN]
18:52:03  13 of 19 PASS not_null_silver_tickets_is_deleted ............................... [PASS in 0.03s]
18:52:03  14 of 19 START test not_null_silver_tickets_ticket_id .......................... [RUN]
18:52:03  14 of 19 PASS not_null_silver_tickets_ticket_id ................................ [PASS in 0.03s]
18:52:03  15 of 19 START test unique_silver_tickets_ticket_id ............................ [RUN]
18:52:03  15 of 19 PASS unique_silver_tickets_ticket_id .................................. [PASS in 0.03s]
18:52:03  16 of 19 START sql microbatch model main.gold_feature_daily .................... [RUN]
18:52:03  Batch 1 of 7 START batch 2026-08-10 of main.gold_feature_daily ....................... [RUN]
18:52:03  Batch 1 of 7 OK created batch 2026-08-10 of main.gold_feature_daily .................. [OK in 0.04s]
18:52:03  Batch 2 of 7 START batch 2026-08-11 of main.gold_feature_daily ....................... [RUN]
18:52:03  Batch 2 of 7 OK created batch 2026-08-11 of main.gold_feature_daily .................. [OK in 0.09s]
18:52:03  Batch 3 of 7 START batch 2026-08-12 of main.gold_feature_daily ....................... [RUN]
18:52:03  Batch 3 of 7 OK created batch 2026-08-12 of main.gold_feature_daily .................. [OK in 0.05s]
18:52:03  Batch 4 of 7 START batch 2026-08-13 of main.gold_feature_daily ....................... [RUN]
18:52:03  Batch 4 of 7 OK created batch 2026-08-13 of main.gold_feature_daily .................. [OK in 0.04s]
18:52:03  Batch 5 of 7 START batch 2026-08-14 of main.gold_feature_daily ....................... [RUN]
18:52:03  Batch 5 of 7 OK created batch 2026-08-14 of main.gold_feature_daily .................. [OK in 0.05s]
18:52:03  Batch 6 of 7 START batch 2026-08-15 of main.gold_feature_daily ....................... [RUN]
18:52:03  Batch 6 of 7 OK created batch 2026-08-15 of main.gold_feature_daily .................. [OK in 0.06s]
18:52:03  Batch 7 of 7 START batch 2026-08-16 of main.gold_feature_daily ....................... [RUN]
18:52:04  Batch 7 of 7 OK created batch 2026-08-16 of main.gold_feature_daily .................. [OK in 0.05s]
18:52:04  16 of 19 OK created sql microbatch model main.gold_feature_daily ............... [SUCCESS in 0.43s]
18:52:04  17 of 19 START test dbt_utils_free_unique_combination_gold_feature_daily_user_id__event_date  [RUN]
18:52:04  17 of 19 PASS dbt_utils_free_unique_combination_gold_feature_daily_user_id__event_date  [PASS in 0.03s]
18:52:04  18 of 19 START test not_null_gold_feature_daily_event_date ..................... [RUN]
18:52:04  18 of 19 PASS not_null_gold_feature_daily_event_date ........................... [PASS in 0.03s]
18:52:04  19 of 19 START test not_null_gold_feature_daily_user_id ........................ [RUN]
18:52:04  19 of 19 PASS not_null_gold_feature_daily_user_id .............................. [PASS in 0.03s]
18:52:04
18:52:04  Finished running 3 incremental models, 13 data tests, 1 unit test, 2 view models in 0 hours 0 minutes and 3.44 seconds (3.44s).
18:52:04
18:52:04  Completed successfully
18:52:04
18:52:04  Done. PASS=19 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=19

PS> .\make.ps1 parity
=== parity: lite pipeline vs dbt ===
  [OK ] silver_tickets       lite 3c15dfd43701  dbt 3c15dfd43701
  [OK ] gold_feature_daily   lite 8630e04a61d1  dbt 8630e04a61d1
RESULT: PARITY — both implementations agree
```
