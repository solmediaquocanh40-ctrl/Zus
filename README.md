# ZaloUnseen 1.0.1

## Có gì mới ở 1.0.1

- Thêm mốc "đã nạp" ghi vào kho cài đặt ngay khi tweak chạy trong Zalo: mở nút "Xem trạng thái dò" là biết tweak có vào được Zalo hay không, không cần mò file log nữa.
- Quét sớm hơn (1 giây sau khi mở Zalo) để bắt kịp các class nạp sớm.
- Đồng bộ lại thông số biên dịch ở cả hai subproject theo đúng mẫu các tweak đang chạy ổn định.


Đọc tin nhắn Zalo mà bên kia không thấy "đã xem", tắt luôn "đang nhập...". Cho máy jailbreak iOS 15/16 (build đủ rootful, rootless, roothide).

## Nó làm gì

- Mở đoạn chat ra đọc bình thường, nhưng Zalo **không lật trạng thái đã đọc**: trong danh sách chat, đoạn đó vẫn **chữ đậm + số tin chưa đọc** như chưa từng mở, và phía người gửi chỉ thấy "đã nhận", không thấy "đã xem".
- Khi bạn gõ tin nhắn, phía bên kia **không thấy "đang nhập..."**.
- Áp dụng cho **mọi người và mọi nhóm** — không cần chọn danh sách.
- Trang trong Cài đặt: công tắc tổng, công tắc riêng cho từng phần, nút "Xem trạng thái dò" cho biết tweak đã tìm thấy và chặn được những gì trên máy bạn.

## Cách nó hoạt động (nói thẳng)

Zalo là app đóng, không ai ngoài VNG biết chính xác hàm nào trong app phụ trách đánh dấu đã đọc. Bản này dùng cơ chế **dò + chặn**: khi Zalo chạy, tweak quét các class nằm trong chính gói Zalo, tìm những hàm khớp mẫu "đánh dấu/gửi/cập nhật + read/seen/typing", kiểm tra kiểu dữ liệu an toàn rồi mới móc vào. Hàm bị móc sẽ không được chạy khi tính năng đang bật — vì vậy trạng thái đã đọc không bị lật và máy chủ không nhận được sự kiện.

Mọi ứng viên tìm thấy, móc nào thành công, lần chặn nào xảy ra đều được ghi vào log `ZaloUnseen.log` trong thư mục Documents của Zalo (xem bằng Filza → Apps → Zalo → Documents). Nếu bản này chưa chặn trúng chỗ trên phiên bản Zalo của bạn, gửi file log đó lại — vòng sau chỉnh đúng tên hàm thật mà log đã phơi ra.

## Giới hạn thật

- Phải kiểm chứng bằng **2 tài khoản**: máy phụ gửi tin, máy này mở ra đọc — bên phụ vẫn chỉ thấy "đã nhận" và đoạn chat bên này vẫn chữ đậm là đạt.
- Nếu bạn **trả lời** tin nhắn thì Zalo tự đánh dấu đã xem lúc gửi — đúng bản chất, không giấu được.
- Chỉ có tác dụng trên điện thoại đã cài tweak. Mở Zalo trên máy tính hay thiết bị khác thì phía đó vẫn tính đã xem như bình thường.
- Zalo cập nhật phiên bản lớn có thể đổi tên hàm bên trong — khi đó gửi lại log, mình chỉnh theo.
- Tắt công tắc tổng trong Cài đặt là mọi hàm móc chạy lại y như gốc, không cần gỡ tweak.

## Cài đặt

Build bằng GitHub Actions (workflow trong `.github/workflows/build.yml`) hoặc up nguyên file zip nguồn lên repo đã cài sẵn workflow "mở zip" — Actions tự mở zip và build 3 bản. Cài bản rootless bằng Sileo, respring, mở Zalo dùng như bình thường.
