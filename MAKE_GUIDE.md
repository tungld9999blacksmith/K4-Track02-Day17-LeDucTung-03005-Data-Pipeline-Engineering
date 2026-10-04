# Make Scripts Guide — Windows 11

Đã tạo 2 script thay thế cho Makefile gốc, chạy được trên Windows 11 native.

## 🚀 Sử dụng

### Cách 1: Command Prompt (Recommended for Windows)
```batch
make.bat help
make.bat setup
make.bat run
make.bat test
make.bat day -Day 2026-08-14
make.bat clean
```

### Cách 2: PowerShell
```powershell
.\make.ps1 help
.\make.ps1 setup
.\make.ps1 run
.\make.ps1 test
.\make.ps1 day -Day 2026-08-14
.\make.ps1 clean
```

Nếu gặp lỗi ExecutionPolicy:
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Cách 3: Git Bash (nếu cài Git for Windows)
```bash
make help
make setup
make run
make test
make day DAY=2026-08-14
make clean
```

## 📋 Available Targets

| Target | Description |
|--------|-------------|
| `help` | Hiển thị danh sách lệnh |
| `setup` | Tạo .venv + cài dependencies |
| `setup-dbt` | Cài dbt-core + dbt-duckdb |
| `run` | Fresh build: reset Silver/Gold, backfill Bronze |
| `day` | One daily run (thêm `-Day 2026-08-14`) |
| `lateness` | Measure event lateness |
| `rerun3` | GRADING TEST: fresh build + compare checksums |
| `verify` | All pipeline contracts (18 checks) |
| `test` | pytest (unit tests + contracts) |
| `dbt` | dbt track: land Bronze → dbt build |
| `parity` | dbt track: check parity (lite vs dbt) |
| `bonus-llm` | Bonus: LLM labelling |
| `flywheel` | Extension: agent traces → eval set |
| `kg` | Extension: knowledge graph vs retrieval |
| `docker-up` | Bonus: Airflow 3 |
| `clean` | Remove venv, lake, warehouse, caches |

## ⚙️ Ngoài ra

**`make.ps1`**: PowerShell script chính
- Tương tương 100% với Makefile gốc
- Hỗ trợ tất cả targets
- Tự động kiểm tra venv trước khi chạy

**`make.bat`**: Batch wrapper
- Gọi `make.ps1` từ Command Prompt
- Không cần mở PowerShell riêng

## 🔧 Lưu ý

1. **Lần đầu chạy**: `make.bat setup` (hoặc `.\make.ps1 setup`)
2. **Nếu dùng dbt track**: `make.bat setup-dbt` sau setup
3. **Cleanup**: `make.bat clean` để reset (remove venv + lake + warehouse)

## ✅ So sánh với Makefile gốc

| Tính năng | Makefile | make.ps1 | make.bat |
|----------|----------|----------|----------|
| Windows native | ❌ | ✅ | ✅ |
| Git Bash | ✅ | ❌ | ❌ |
| Command Prompt | ❌ | ❌ | ✅ |
| PowerShell | ❌ | ✅ | ✅ |
| Tất cả targets | ✅ | ✅ | ✅ |

---

**Khuyến nghị**: Sử dụng `make.bat` nếu bạn dùng Command Prompt/Windows Terminal native. Hoặc sử dụng `make.ps1` nếu bạn quen với PowerShell.
