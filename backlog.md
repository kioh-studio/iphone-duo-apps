# Backlog

- Build & chạy thử trên Mac: `xcodegen generate`, build app, `swift test` cho CaptionCore — code viết trên Windows, chưa compile lần nào. (2026-09-13, chưa có Mac/Xcode để verify)
- Màn ngoài iPhone Duo: thay/bổ sung external-display scene bằng `.sceneAccessory` (Apple mới document `CameraCaptureAccessory` cho app camera — app không phải camera có dùng được màn ngoài qua API này không thì chưa rõ) khi Apple phát hành tài liệu + Xcode 27.1; xác minh app không phải camera có được hiển thị ở màn ngoài không, màn ngoài có nhận touch không (rủi ro lớn nhất của ý tưởng). (2026-09-13, API chưa được document đầy đủ, chờ Xcode 27.1)
- Xác minh trên máy thật: `TranslationSession(installedSource:target:)` (throw khi nào, gọi đồng thời có an toàn không), chuyển format audio `AVAudioConverter` → `SpeechAnalyzer.bestAvailableAudioFormat`, scene role `windowExternalDisplayNonInteractive` trong app SwiftUI lifecycle. (2026-09-13, cần thiết bị thật + iOS 26)
- Dùng API reserved regions (`GeometryProxy.reservedRegions(kind: .division)` / UIKit `view.reservedRegions(kind:)`, iOS 27.1 — Apple đã mô tả trong Tech Talk 111463) cho dải nếp gập thay vì dải cố định 28pt ở layout chia đôi. (2026-09-13, chờ Xcode 27.1 beta — Apple hẹn cuối tháng 9)
- Tự chuyển layout theo tư thế máy bằng `ArrangementView` + reserved regions (Apple khuyên không dùng góc bản lề `.onHingeChange` để quyết định layout — chỉ dùng cho tương tác/hiệu ứng; Tech Talk 111463, 111464) thay vì luôn chia đôi khi không có màn hình đối diện. (2026-09-13, chờ Xcode 27.1 beta)
- Tự nhận diện ngôn ngữ / tự chuyển lượt nói để bỏ nút lượt nói thủ công. (2026-09-13, để MVP dùng nút thủ công trước cho chắc)
- Bản địa hoá tiếng Việt (String Catalog) — UI hiện chỉ có tiếng Anh. (2026-09-13, chưa ưu tiên cho bản đầu)
- App icon (AppIcon hiện để trống). (2026-09-13, chưa có asset thiết kế)
- Test trên iPhone Duo thật sau 23/10/2026. (2026-09-13, máy chưa ra mắt)
- Khác biệt hoá với tính năng dịch hội thoại sẵn có của Apple: app Translate (chế độ face-to-face) và Live Translation trên AirPods (iOS 26+; AirPods 5 ra mắt 09/09/2026, cần iPhone 15 Pro trở lên, không có ở Trung Quốc đại lục). Điểm khác của Across phải là: không cần tai nghe cho cả hai người, có màn hình đối diện đọc được từ xa, chạy trên iPhone đời cũ hơn. (2026-09-13, cần theo dõi Apple cập nhật)
- Đề xuất: App Intents cho Siri AI (iOS 27 bỏ SiriKit, Siri chỉ gọi app qua App Intents) — ví dụ "Siri, bắt đầu hội thoại tiếng Anh". (2026-09-13, đề xuất từ Apple event, chưa duyệt)
