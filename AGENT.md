# AGENT.md

## 1. Tổng quan dự án

Đây là dự án Trading Desktop App dùng để quản lý, phân tích và hỗ trợ kỷ luật giao dịch.

Mục tiêu chính:
- Kết nối/lấy dữ liệu từ MT5.
- Lưu lịch sử giao dịch.
- Phân tích hiệu suất trading.
- Ghi journal cho từng trade.
- Tính điểm kỷ luật.
- Block trade khi vi phạm rule.
- Hỗ trợ trader cải thiện theo ngày/tuần/tháng.

Không chỉ là app xem lịch sử giao dịch, dự án này tập trung vào:
- Trading discipline.
- Risk management.
- Trade analytics.
- MT5 integration.
- Desktop-first experience.

---

## 2. Công nghệ áp dụng

Frontend:
- Flutter Desktop
- Dart

Backend:
- FastAPI
- Python

Database:
- SQLite trong giai đoạn local/dev
- Có thể nâng cấp PostgreSQL/Supabase sau

MT5 Integration:
- MetaTrader 5
- Python MT5 package hoặc file export từ MT5

Development tools:
- VS Code / Antigravity IDE
- Git / GitHub

---

## 3. Kiến trúc tổng quát

Frontend Flutter:
- Hiển thị dashboard
- Hiển thị trade history
- Hiển thị analytics
- Hiển thị journal
- Hiển thị rule/settings
- Gửi request tới backend API

Backend FastAPI:
- Nhận dữ liệu từ MT5
- Chuẩn hóa dữ liệu giao dịch
- Lưu database
- Tính toán analytics
- Kiểm tra rule vi phạm
- Cung cấp API cho frontend

Database:
- Lưu raw data từ MT5
- Lưu dữ liệu trade đã chuẩn hóa
- Lưu journal
- Lưu analytics
- Lưu rule settings
- Lưu rule breaks

---

## 4. Các bảng dữ liệu chính

Các bảng quan trọng:

- trading_accounts
- account_snapshots
- raw_mt5_imports
- raw_deals
- raw_orders
- raw_positions
- normalized_trades
- trade_journals
- daily_analytics
- guardrail_settings
- rule_breaks
- economic_events

Nguyên tắc dữ liệu:

- Raw data: lưu dữ liệu gốc từ MT5, không chỉnh sửa.
- Normalized data: dữ liệu đã xử lý sạch.
- Analytics: chỉ tính từ normalized data.
- Journal: gắn với normalized trade.
- Rule breaks: lưu các lần vi phạm rule.

---

## 5. Quy tắc thiết kế

Luôn ưu tiên:
- Code rõ ràng, dễ đọc.
- Tách frontend/backend/database rõ ràng.
- Không viết logic tính toán trực tiếp trong UI.
- Backend chịu trách nhiệm xử lý dữ liệu.
- Frontend chỉ gọi API và hiển thị.
- Database schema phải rõ ràng.
- Mỗi chức năng nên tách thành module riêng.

Không nên:
- Viết toàn bộ logic vào một file.
- Hard-code dữ liệu test quá nhiều.
- Trộn raw data và normalized data.
- Tính analytics trực tiếp từ raw MT5 data.
- Xóa dữ liệu thật nếu chưa có xác nhận.
- Sửa rule trong ngày nếu đã có trade.

---

## 6. Quy tắc bắt buộc cho AI Agent

Khi thực hiện bất kỳ task nào trong dự án này, AI Agent bắt buộc phải tuân thủ các quy tắc sau.

### 6.1. Bắt buộc phải làm

- Luôn đọc `AGENT.md` trước khi bắt đầu sửa code.
- Luôn kiểm tra cấu trúc thư mục hiện tại trước khi tạo file mới.
- Luôn xác định task thuộc phần nào:
  - Frontend
  - Backend
  - Database
  - MT5 integration
  - Analytics
  - Rule/guardrail
- Luôn đọc file liên quan trước khi chỉnh sửa.
- Luôn giữ nguyên kiến trúc hiện tại nếu không có yêu cầu thay đổi.
- Luôn ưu tiên cách sửa đơn giản, rõ ràng, dễ debug.
- Luôn tách logic xử lý ra khỏi UI.
- Luôn đặt code đúng thư mục/module.
- Luôn kiểm tra import/path sau khi sửa.
- Luôn giải thích ngắn gọn đã sửa gì và sửa ở file nào.
- Nếu task chưa rõ, phải hỏi lại trước khi sửa.
- Nếu có nhiều phương án, chọn phương án an toàn nhất.
- Nếu sửa backend, phải kiểm tra API route/schema/service liên quan.
- Nếu sửa frontend, phải kiểm tra screen/widget/service/model liên quan.
- Nếu sửa database, phải kiểm tra schema/model/migration trước.
- Nếu sửa logic trading/risk/analytics, phải giữ tính đúng dữ liệu lên hàng đầu.

### 6.2. Không được làm

- Không tự ý xóa file, folder hoặc code quan trọng.
- Không tự ý đổi kiến trúc dự án nếu chưa được yêu cầu.
- Không viết toàn bộ logic vào một file lớn.
- Không hard-code dữ liệu nếu có thể lấy từ backend/database.
- Không trộn logic frontend với backend.
- Không tính analytics trực tiếp trong UI.
- Không sửa database schema tùy tiện.
- Không đổi tên bảng, cột, model, API route khi chưa cần.
- Không phá vỡ API cũ nếu frontend đang dùng.
- Không tự ý thêm thư viện mới nếu chưa cần thiết.
- Không viết code quá phức tạp khi task đơn giản.
- Không bỏ qua lỗi import, lỗi type, lỗi format.
- Không tạo file trùng chức năng với file đã có.
- Không sửa nhiều phần không liên quan đến task.
- Không đưa ra code giả nếu đang sửa code thật.
- Không đoán logic nghiệp vụ trading khi chưa rõ.
- Không tối ưu quá sớm.
- Không làm thay đổi dữ liệu thật nếu chưa có xác nhận.

### 6.3. Quy trình bắt buộc trước khi sửa code

Trước khi sửa code, AI Agent phải thực hiện:

1. Đọc `AGENT.md`.
2. Kiểm tra cây thư mục dự án.
3. Tìm các file liên quan đến task.
4. Đọc nội dung file liên quan.
5. Xác định nơi cần sửa.
6. Chỉ sửa đúng phần cần sửa.
7. Kiểm tra lại import, path, lỗi cú pháp.
8. Báo cáo ngắn gọn kết quả sau khi sửa.

### 6.4. Quy trình sau khi sửa code

Sau khi sửa code, AI Agent phải báo cáo:

- Đã sửa file nào.
- Đã thêm file nào nếu có.
- Logic chính đã thay đổi là gì.
- Cách chạy/test lại.
- Có rủi ro gì cần chú ý không.

### 6.5. Nguyên tắc ưu tiên

Thứ tự ưu tiên khi làm task:

1. Không làm hỏng code đang chạy đúng .
2. Đúng yêu cầu task.
3. Dữ liệu phải đúng.
4. Code dễ hiểu.
5. Dễ debug.
6. Dễ mở rộng sau này.
7. Giao diện đẹp sau cùng.

---

## 7. Workflow làm việc cho AI Agent

Khi chỉnh sửa dự án, AI phải làm theo thứ tự:

1. Đọc file AGENT.md trước.
2. Kiểm tra cấu trúc thư mục hiện tại.
3. Xác định đang sửa frontend hay backend.
4. Không tự ý thay đổi kiến trúc lớn nếu chưa cần.
5. Không xóa file quan trọng.
6. Nếu sửa database, phải kiểm tra schema trước.
7. Nếu thêm API, phải cập nhật route rõ ràng.
8. Nếu thêm frontend screen, phải đặt đúng thư mục.
9. Nếu sửa logic trading/risk/rule, phải giải thích rõ.
10. Sau khi sửa, cần nêu các file đã thay đổi.

---

## 8. Quy ước code

Backend:
- Dùng FastAPI router.
- Tách models, schemas, services, routes.
- Logic xử lý nên nằm trong services.
- API response nên rõ ràng.
- Không để logic lớn trong main.py.

Frontend:
- Tách screens, widgets, services, models.
- Không gọi API trực tiếp lung tung trong UI.
- Nên có service riêng để gọi backend.
- UI desktop cần gọn, rõ, chuyên nghiệp.

Database:
- Không xóa bảng nếu chưa có yêu cầu.
- Không đổi tên cột tùy tiện.
- Nếu thêm bảng/cột, phải giải thích lý do.

---

## 9. Mục tiêu hiện tại của dự án

Giai đoạn hiện tại:

- Backend FastAPI chạy được.
- SQLite hoạt động.
- API `/health` hoạt động.
- API accounts hoạt động.
- Chuẩn bị schema database.
- Chuẩn bị kết nối dữ liệu MT5.
- Frontend Flutter gọi được backend.

---

## 10. Khi AI trả lời

AI cần trả lời theo kiểu:

- Nói rõ vấn đề.
- Đưa cách sửa cụ thể.
- Chỉ rõ file cần sửa.
- Nếu có code, viết code đầy đủ.
- Không trả lời quá chung chung.
- Không tự ý đổi hướng dự án.
- Ưu tiên cách làm đơn giản, chắc chắn, dễ mở rộng.

---

## 11. Nguyên tắc quan trọng nhất

Dự án này ưu tiên:

1. Chạy được trước.
2. Đúng dữ liệu.
3. Dễ debug.
4. Dễ mở rộng.
5. Giao diện chuyên nghiệp sau.

Không tối ưu quá sớm.
Không làm phức tạp khi chưa cần.