import 'app_language.dart';

class AppStrings {
  final AppLanguage language;

  const AppStrings(this.language);
  const AppStrings.fallback() : language = AppLanguage.english;

  bool get isVietnamese => language == AppLanguage.vietnamese;

  String text(String value) {
    if (!isVietnamese) return value;
    return _vi[value] ?? value;
  }

  static const Map<String, String> _vi = {
    'Dashboard': 'Dashboard',
    'Journal': 'Nhật ký',
    'Notebook': 'Sổ tay',
    'News': 'Tin tức',
    'Guardrails': 'Guardrails',
    'Settings': 'Cài đặt',
    'Plan Page': 'Kế hoạch',
    'BALANCE': 'SỐ DƯ',
    'CLOSED P&L': 'P&L ĐÃ ĐÓNG',
    'WIN RATE': 'TỶ LỆ THẮNG',
    'AVG R / TRADE': 'R TB / LỆNH',
    'PROFIT FACTOR': 'HỆ SỐ LỢI NHUẬN',
    'Loading trading account, positions, and performance analytics...':
        'Đang tải tài khoản, vị thế và phân tích hiệu suất...',
    'Trading analytics connected - account, risk, and performance are calculated from broker data.':
        'Đã kết nối phân tích giao dịch - tài khoản, rủi ro và hiệu suất được tính từ dữ liệu broker.',
    'Account Balance': 'Số dư tài khoản',
    'Recent Trades': 'Lệnh gần nhất',
    'All trades': 'Tất cả lệnh',
    'Instrument': 'Sản phẩm',
    'Direction': 'Hướng',
    'Ticket': 'Ticket',
    'Volume': 'Khối lượng',
    'Entry': 'Vào lệnh',
    'Exit': 'Thoát lệnh',
    'Status': 'Trạng thái',
    'Opened': 'Mở lúc',
    'Closed': 'Đóng lúc',
    'P/L': 'Lãi/Lỗ',
    'Outcome': 'Kết quả',
    'Closed At': 'Đóng lúc',
    'Win': 'Thắng',
    'Loss': 'Thua',
    'No closed trades yet': 'Chưa có lệnh đã đóng',
    'No normalized trades yet': 'Chưa có lệnh đã chuẩn hóa',
    'Discipline breakdown': 'Phân tích kỷ luật',
    'Performance': 'Hiệu suất',
    'Discipline': 'Kỷ luật',
    'Consistency': 'Ổn định',
    'Profit factor': 'Hệ số lợi nhuận',
    'Win rate': 'Tỷ lệ thắng',
    'Average RR': 'RR trung bình',
    'Expectancy': 'Kỳ vọng',
    'Daily drawdown': 'Drawdown ngày',
    'Max trades': 'Số lệnh tối đa',
    'Risk per trade': 'Rủi ro mỗi lệnh',
    'Revenge trade': 'Giao dịch trả thù',
    'Max drawdown': 'Drawdown tối đa',
    'Trading time': 'Thời gian giao dịch',
    'Trading locked around high-impact news.':
        'Giao dịch bị khóa quanh tin quan trọng.',
    "Today's rule breaks": 'Vi phạm hôm nay',
    "A quick summary of today's trading rules and loss status.":
        'Tóm tắt nhanh các vi phạm và trạng thái lãi lỗ hôm nay.',
    'Modify guardrails': 'Chỉnh giới hạn bảo vệ',
    'Max daily loss is reached.': 'Đã chạm mức lỗ tối đa trong ngày.',
    'No active rule breaks.': 'Không có vi phạm nào đang hoạt động.',
    'Monthly Summary': 'Tổng kết tháng',
    'Weekly Breakdown': 'Phân tích tuần',
    'No weekly PnL synced yet': 'Chưa có PnL tuần được đồng bộ',
    'No weekly trade data for this month yet.':
        'Chưa có dữ liệu giao dịch theo tuần trong tháng này.',
    'Avg win': 'Thắng TB',
    'Avg loss': 'Thua TB',
    'Net PnL': 'PnL ròng',
    'Mistakes': 'Lỗi',
    'Calendar': 'Lịch',
    'Loading journal, calendar, and MT5 trade reviews...':
        'Đang tải nhật ký, lịch và đánh giá lệnh MT5...',
    'Trade journal connected - notes, reviews, and calendar are synced from broker data.':
        'Nhật ký đã kết nối - ghi chú, đánh giá và lịch được đồng bộ từ dữ liệu broker.',
    'Connected to backend': 'Đã kết nối dịch vụ',
    'Syncing trades from MT5': 'Đang đồng bộ lệnh từ MT5',
    'Profit': 'Lời',
    'Reviewed': 'Đã review',
    'No trades synced for this day.': 'Chưa có lệnh đồng bộ cho ngày này.',
    'All': 'Tất cả',
    'Wins': 'Lệnh thắng',
    'Losses': 'Lệnh thua',
    'Return': 'Lợi suất',
    'Trades': 'Lệnh',
    'Rule break': 'Vi phạm',
    'Templates': 'Mẫu',
    'New Note': 'Ghi chú mới',
    'Create from Template': 'Tạo từ mẫu',
    'Create Blank Note': 'Tạo ghi chú trống',
    'Think before you trade. Review before you repeat.':
        'Nghĩ trước khi trade. Review trước khi lặp lại.',
    'Search in notes': 'Tìm trong ghi chú',
    'No matching notes': 'Không tìm thấy ghi chú phù hợp',
    'No notes yet': 'Chưa có ghi chú',
    'Note title': 'Tiêu đề ghi chú',
    'Folder name': 'Tên thư mục',
    'New folder': 'Thư mục mới',
    'Create folder': 'Tạo thư mục',
    'Rename folder': 'Đổi tên thư mục',
    'Delete folder': 'Xóa thư mục',
    'Pinned Templates': 'Mẫu đã ghim',
    'My Templates': 'Mẫu của tôi',
    'No templates yet': 'Chưa có mẫu',
    'Rename note': 'Đổi tên ghi chú',
    'Pin note': 'Ghim ghi chú',
    'Unpin note': 'Bỏ ghim ghi chú',
    'Delete note': 'Xóa ghi chú',
    'Pinned notes': 'Ghi chú đã ghim',
    'Recent notes': 'Ghi chú gần đây',
    'All notes': 'Tất cả ghi chú',
    'Cancel': 'Hủy',
    'Create': 'Tạo',
    'Delete': 'Xóa',
    'Save': 'Lưu',
    'Saved': 'Đã lưu',
    'Draft': 'Nháp',
    'Back to Notebook': 'Quay lại sổ tay',
    'Planning': 'Kế hoạch',
    'Checklist': 'Checklist',
    'Notes': 'Ghi chú',
    'Add planning task': 'Thêm việc cần chuẩn bị',
    'Capture ideas, lessons, scenarios, review notes...':
        'Ghi lại ý tưởng, bài học, kịch bản, review...',
    'Bias, risk, trigger, invalidation, action plan...':
        'Xu hướng, rủi ro, tín hiệu, điểm vô hiệu, kế hoạch hành động...',
    'Heading': 'Tiêu đề',
    'Bullet': 'Gạch đầu dòng',
    'Numbered': 'Đánh số',
    'Checkbox': 'Checkbox',
    'Quote': 'Trích dẫn',
    'Bold': 'Đậm',
    'Italic': 'Nghiêng',
    'Timestamp': 'Mốc thời gian',
    'Pre-market': 'Trước phiên',
    'Trade review': 'Review lệnh',
    'Clear done': 'Xóa mục đã xong',
    'News backend offline - showing empty calendar':
        'Backend tin tức offline - đang hiển thị lịch trống',
    "Today's Events": 'Tin hôm nay',
    'No economic events for today.': 'Không có sự kiện kinh tế hôm nay.',
    'No economic events for this day.':
        'Không có sự kiện kinh tế cho ngày này.',
    'Time': 'Giờ',
    'Currency': 'Tiền tệ',
    'Impact': 'Mức ảnh hưởng',
    'Event': 'Sự kiện',
    'Actual': 'Thực tế',
    'Forecast': 'Dự báo',
    'Previous': 'Trước đó',
    'Today': 'Hôm nay',
    'List': 'Danh sách',
    'Refresh': 'Làm mới',
    'High': 'Đỏ',
    'Medium': 'Vàng',
    'Low': 'Thấp',
    'Account protection': 'Bảo vệ tài khoản',
    'Automated limits that keep your trading inside the plan, enforced directly on MT5.':
        'Các giới hạn tự động giúp bạn giao dịch đúng kế hoạch, thực thi trực tiếp trên MT5.',
    'Trade blocking': 'Chặn giao dịch',
    'Ready': 'Sẵn sàng',
    'Blocked': 'Đang chặn',
    'Off': 'Tắt',
    'Mode': 'Chế độ',
    'MT5 enforcement': 'Thực thi MT5',
    'Mt5 enforcement': 'Thực thi MT5',
    'Triggered rules': 'Điều kiện đang kích hoạt',
    'Critical': 'Nghiêm trọng',
    'active': 'đang kích hoạt',
    'critical': 'nghiêm trọng',
    'critical rule needs attention': 'mục nghiêm trọng cần chú ý',
    'Trade blocking rules': 'Quy tắc chặn giao dịch',
    'Set your Guardrails': 'Thiết lập giới hạn bảo vệ',
    'These are recommended defaults. You can change them later.':
        'Đây là các mặc định được đề xuất. Bạn có thể thay đổi sau.',
    'Guardrails will flag actions that break your rules. Trade blocking stays off until you enable it later.':
        'Hệ thống sẽ đánh dấu các hành động vượt giới hạn. Chế độ chặn giao dịch vẫn tắt cho đến khi bạn chủ động bật.',
    'Guardrails can block app/EA trade execution automatically once enabled.':
        'Khi được bật, hệ thống có thể tự động chặn lệnh từ app hoặc EA.',
    'Enable trade blocking': 'Bật chặn giao dịch',
    'Blocks new orders when an active limit is reached':
        'Chặn lệnh mới khi một giới hạn đang bị kích hoạt',
    'Max trades per day': 'Số lệnh tối đa mỗi ngày',
    'Stop overtrading by limiting completed trades':
        'Giới hạn số lệnh đã hoàn tất để tránh overtrade',
    'Max daily loss': 'Lỗ tối đa mỗi ngày',
    'Uses realized P&L from normalized trades':
        'Dùng P&L đã chốt từ lệnh đã chuẩn hóa',
    'Uses realized PnL.': 'Dùng PnL đã chốt.',
    'Max daily profit': 'Lãi tối đa mỗi ngày',
    'Locks in discipline once the target is reached':
        'Khóa kỷ luật khi đã đạt mục tiêu',
    'Fixed risk per trade': 'Rủi ro cố định mỗi lệnh',
    'Stored for position sizing and risk warnings':
        'Lưu để tính khối lượng và cảnh báo rủi ro',
    'Let max auto-adjusts to match risk.':
        'Tự điều chỉnh mức tối đa để khớp rủi ro.',
    'Trading window': 'Khung giờ giao dịch',
    'Used for local warnings outside planned sessions':
        'Dùng để cảnh báo khi giao dịch ngoài phiên đã đặt',
    'High-impact news block': 'Chặn tin đỏ',
    'News block': 'Chặn tin tức',
    'Lot size auto-adjusts to match risk.':
        'Khối lượng tự điều chỉnh để khớp rủi ro.',
    'Only blocks high-impact events relevant to your pinned pairs.':
        'Chỉ chặn sự kiện quan trọng liên quan đến các cặp đã ghim.',
    'Blocks red news only - 15 min before & after - yellow allowed':
        'Chỉ chặn tin đỏ - 15 phút trước và sau - tin vàng vẫn được phép',
    'Blocks red news only · 15 min before & after · yellow allowed':
        'Chỉ chặn tin đỏ · 15 phút trước và sau · tin vàng vẫn được phép',
    'Live rule checks': 'Kiểm tra trực tiếp',
    'Reads local analytics and cached economic news in real time.':
        'Đọc phân tích nội bộ và tin kinh tế đã cache theo thời gian thực.',
    'Reset defaults': 'Đặt lại mặc định',
    'Save guardrails': 'Lưu giới hạn',
    'Skip for now': 'Bỏ qua lúc này',
    'Locked': 'Đã khóa',
    'Saving...': 'Đang lưu...',
    'Guardrails saved. MT5 trade blocker will enforce active limits.':
        'Đã lưu giới hạn. MT5 sẽ áp dụng các giới hạn đang bật.',
    'Guardrails saved. Trade blocking is currently off.':
        'Đã lưu giới hạn. Chế độ chặn giao dịch hiện đang tắt.',
    'AI Coach': 'AI Coach',
    'AI Coach unavailable': 'AI Coach chưa khả dụng',
    'Journal, guardrails, trades, and news are analyzed from local broker data.':
        'Nhật ký, giới hạn bảo vệ, lệnh giao dịch và tin tức được phân tích từ dữ liệu broker cục bộ.',
    'Week': 'Tuần',
    'Month': 'Tháng',
    'Key findings': 'Điểm chính',
    'Coach advice': 'Lời khuyên',
    'No findings yet. Sync more closed trades.':
        'Chưa có nhận định. Hãy đồng bộ thêm lệnh đã đóng.',
    'No advice yet. Journal a trade first.':
        'Chưa có lời khuyên. Hãy journal một lệnh trước.',
    'No coach review yet': 'Chưa có review từ coach',
    'No closed trades in this period': 'Chưa có lệnh đã đóng trong kỳ này',
    'No normalized closed trades are available yet.':
        'Chưa có lệnh đã đóng được chuẩn hóa.',
    'Sync MT5 after trades close.': 'Đồng bộ MT5 sau khi lệnh đã đóng.',
    'Write a pre-market plan before taking the next setup.':
        'Viết kế hoạch trước phiên trước khi vào setup tiếp theo.',
    'Next session plan': 'Kế hoạch phiên tiếp theo',
    'Risk/trade': 'Rủi ro/lệnh',
    'Focus': 'Tập trung',
    'Avoid': 'Tránh',
    'No forced avoidance': 'Không bắt buộc tránh',
    'Data signals': 'Tín hiệu dữ liệu',
    'Weakest symbols': 'Mã yếu nhất',
    'Rule breaks': 'Các vi phạm',
    'No data yet': 'Chưa có dữ liệu',
    'Avg R': 'R trung bình',
    'High risk': 'Rủi ro cao',
    'Medium risk': 'Rủi ro vừa',
    'Low risk': 'Rủi ro thấp',
    'Neutral': 'Trung lập',
    'Wait for A+ setups only': 'Chỉ chờ setup A+',
    'A+ setup only': 'Chỉ setup A+',
    'Keep trade blocking enabled and do not loosen core limits mid-session.':
        'Giữ bật chặn giao dịch và không nới lỏng các giới hạn cốt lõi giữa phiên.',
    'Limit the next session to 1-2 trades and cut size until win rate stabilizes.':
        'Giới hạn phiên tới còn 1-2 lệnh và giảm khối lượng cho đến khi tỷ lệ thắng ổn định.',
    'Keep the same risk profile; do not scale up until this edge repeats across another period.':
        'Giữ nguyên mức rủi ro; không tăng size cho đến khi lợi thế này lặp lại ở kỳ tiếp theo.',
    'Trade only setups already written in the plan; skip impulse entries.':
        'Chỉ giao dịch các setup đã viết trong kế hoạch; bỏ qua lệnh vào theo cảm xúc.',
    'Discipline is the main issue this period':
        'Kỷ luật là vấn đề chính trong kỳ này',
    'Losses are driven by low win rate and negative expectancy':
        'Thua lỗ đến từ tỷ lệ thắng thấp và expectancy âm',
    'Period is negative; review sizing and weakest symbol':
        'Kỳ này đang âm; cần review khối lượng và mã yếu nhất',
    'Period is profitable; protect the edge and avoid overtrading':
        'Kỳ này có lợi nhuận; hãy bảo vệ lợi thế và tránh overtrade',
    'Flat period; wait for cleaner setups':
        'Kỳ này đi ngang; hãy chờ setup rõ ràng hơn',
    'Trade not found': 'Không tìm thấy lệnh',
    'No normalized trade exists for this id.':
        'Không có lệnh đã chuẩn hóa cho id này.',
    'Sync MT5 again, then reopen this trade review.':
        'Đồng bộ MT5 lại, sau đó mở lại review lệnh này.',
  };

  String nav(String key, String fallback) {
    if (!isVietnamese) return fallback;
    return switch (key) {
      'dashboard' => 'Dashboard',
      'journal' => 'Nhật ký',
      'notebook' => 'Sổ tay',
      'news' => 'Tin tức',
      'guardrails' => 'Guardrails',
      'aiCoach' => 'AI Coach',
      'collapse' => 'Thu gọn',
      'settings' => 'Cài đặt',
      _ => fallback,
    };
  }

  String get settingsTitle => text('Settings');
  String get settingsSubtitle => isVietnamese
      ? 'Tài khoản, giao diện, ngôn ngữ và thông báo.'
      : 'Account, appearance, language, and notification preferences.';

  String get accountTitle => isVietnamese ? 'Tài khoản' : 'Account';
  String get accountSubtitle => isVietnamese
      ? 'Định danh đăng nhập và hồ sơ desktop.'
      : 'Login identity and desktop profile.';
  String get tradingDesk => 'Trading Desk';
  String get connectMt5 =>
      isVietnamese ? 'Kết nối MT5 hiện có' : 'Connect existing MT5 terminal';
  String get readyToSync => isVietnamese
      ? 'Sẵn sàng đồng bộ và bảo vệ tài khoản này'
      : 'Ready to sync and protect this account';
  String get licenseTitle => isVietnamese ? 'License' : 'License';
  String get licenseSubtitle => isVietnamese
      ? 'Nhập mã license offline để kích hoạt.'
      : 'Enter an offline license key to activate.';
  String get licenseHint =>
      isVietnamese ? 'Nhập license key' : 'Enter license key';
  String get activateLicense =>
      isVietnamese ? 'Kích hoạt license' : 'Activate license';
  String get licenseStatusActive =>
      isVietnamese ? 'License đã kích hoạt' : 'License active';
  String get licenseStatusInactive =>
      isVietnamese ? 'Chưa kích hoạt license' : 'License not active';
  String get licenseKeyRequired =>
      isVietnamese ? 'Vui lòng nhập license key' : 'Please enter a license key';
  String get signIn => isVietnamese ? 'Đăng nhập' : 'Sign in';
  String get syncMt5 => isVietnamese ? 'Đồng bộ MT5' : 'Sync MT5';
  String get connecting => isVietnamese ? 'Đang kết nối...' : 'Connecting...';
  String get connectingMt5Message => isVietnamese
      ? 'Đang khởi động backend và kết nối MT5...'
      : 'Starting backend and connecting to MT5...';
  String connectedMt5Message(String login) => isVietnamese
      ? 'Đã kết nối. Đã import và đồng bộ tài khoản MT5 $login.'
      : 'Connected. Imported and synced MT5 account $login.';
  String couldNotConnect(Object error) {
    final message = error.toString();
    final lower = message.toLowerCase();
    if (lower.contains('read-only') || lower.contains('readonly database')) {
      return isVietnamese
          ? 'Chua the luu du lieu MT5 vi database dang chi doc. Hay dong app, mo lai TradingDesk, hoac kiem tra quyen ghi cua thu muc TradingDesk trong AppData. $error'
          : 'Could not save MT5 data because the database is read-only. Close and reopen TradingDesk, or check write permission for the TradingDesk folder in AppData. $error';
    }
    return isVietnamese
        ? 'Khong the ket noi. Hay mo MT5, dang nhap tai khoan, roi thu lai. $error'
        : 'Could not connect. Open MT5, log in, then try again. $error';
  }

  String get notificationsTitle => isVietnamese ? 'Thông báo' : 'Notifications';
  String get notificationsSubtitle => isVietnamese
      ? 'Cảnh báo được quản lý trong ứng dụng.'
      : 'Alerts stay inside the app.';
  String get add => isVietnamese ? '+ Thêm' : '+ Add';
  String get tradeBlockAlerts =>
      isVietnamese ? 'Cảnh báo chặn lệnh' : 'Trade block alerts';
  String get tradeBlockAlertsSubtitle => isVietnamese
      ? 'Thông báo khi guardrail chặn một lệnh'
      : 'Notify when a guardrail blocks a trade';
  String get redNewsAlerts =>
      isVietnamese ? 'Cảnh báo tin đỏ' : 'Red news alerts';
  String get redNewsAlertsSubtitle => isVietnamese
      ? 'Thông báo trước tin tức quan trọng'
      : 'Notify before high-impact news events';
  String get mt5SyncAlerts =>
      isVietnamese ? 'Cảnh báo đồng bộ MT5' : 'MT5 sync alerts';
  String get mt5SyncAlertsSubtitle => isVietnamese
      ? 'Thông báo khi đồng bộ tài khoản hoàn tất'
      : 'Notify when account sync finishes';

  String get languageTitle => isVietnamese ? 'Ngôn ngữ' : 'Language';
  String get languageSubtitle => isVietnamese
      ? 'Chọn ngôn ngữ hiển thị cho ứng dụng.'
      : 'Choose the display language for the app.';

  String get appearanceTitle => isVietnamese ? 'Giao diện' : 'Appearance';
  String get appearanceSubtitle => isVietnamese
      ? 'Theme được quản lý tại đây thay vì trên thanh icon.'
      : 'Theme is managed here instead of the icon bar.';
  String get lightTheme => isVietnamese ? 'Trắng' : 'Light';
  String get darkTheme => isVietnamese ? 'Đen' : 'Dark';
}
