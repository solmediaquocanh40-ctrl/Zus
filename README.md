# ZaloUnseen 1.0.6

## Có gì mới ở 1.0.6

- **Chặn thêm lớp dữ liệu — đường rò mà log 1.0.5 đã chỉ mặt.** Bản 1.0.5 hết văng thật, và log chứng minh cả 25 cửa lắp được đều chạy + bị chặn khi mở nhóm (kể cả hàm ghi mốc đã xem trong máy và hàm xả hàng đợi lên máy chủ), vậy mà chữ vẫn mất đậm: luồng đánh dấu đã đọc còn đi qua lớp dữ liệu ghi trạng thái đã xem vào giao diện + cơ sở dữ liệu. 1.0.6 thêm 9 cửa ở lớp này (tổng 36): họ processUpdateStatus...withUI:withDB: của ChatDataManager / ChatDataFlow / InboxDataManager, processResetUnread... của ChatProcessor, updateMaxSeenGlobalId: và checkSendClearUnreadType: của ChatDataManager — tên hàm lấy từ danh sách ứng viên trong chính bản Zalo trên máy (log 1.0.3). Một cửa anh em 7 tham số của InboxDataManager tạm chưa móc (tham số thứ 7 nằm trên ngăn xếp, cần kỹ thuật chuyển tiếp khác); hai cửa 5 và 6 tham số của nó nhiều khả năng phủ cùng luồng.
- **Đang nhập: sửa đúng nguyên nhân bị từ chối.** Log 1.0.5 ghi rõ mã kiểu: hai hàm đang nhập trả về số (B và Q) chứ không phải void — cổng kiểm tra cũ chỉ nhận hàm trả về void nên từ chối oan (giả thuyết ký tự định tính trước đây là sai). Nay cổng nhận mọi kiểu trả về vô hướng/con trỏ, và mọi hàm thay thế trả lại giá trị: chuyển tiếp thì trả nguyên giá trị gốc, chặn thì trả 0.
- **Hàm thay thế 6 tham số mới** cho cửa lớp dữ liệu 6 tham số; điều kiện kích hoạt của hàm thay thế 5 tham số được tổng quát hoá cho cả hai nhóm (trước đây chỉ xét nhóm đang nhập — cửa đã-xem 5 tham số sẽ không bao giờ bị chặn nếu giữ nguyên).
- Giữ nguyên: log "lần đầu được gọi" cho từng cửa, bộ đếm chẩn đoán trong trang Cài đặt, filter vn.com.vng.zingalo.

## Có gì mới ở 1.0.5

- **Sửa đúng gốc vụ văng khi mở đoạn chat của 1.0.4.** File báo cáo sập (.ips) cộng với giải mã đúng file .deb đã cài chỉ đích danh: hàm thay thế chung của tweak khai tham số kiểu `id`, trình biên dịch (ARC) tự chèn lệnh retain cho cả hai tham số ngay khi vào hàm; hàm nào của Zalo có tham số thứ hai là số nguyên (như `type:` của ConversationModel) thì lệnh retain đó đọc con số như một địa chỉ bộ nhớ và sập tại chỗ — chết trước khi kịp chặn hay ghi log. Đó là lý do log 1.0.4 trống ở đúng đoạn mở chat và phần "đã xem" tưởng như không đi qua cửa nào. 1.0.5 khai mọi tham số của hàm thay thế là `__unsafe_unretained`/`void*`: không còn lệnh retain nào trên đường đi của tham số nữa.
- **Danh sách móc 27 hàm:** giữ 19 hàm đã kiểm chứng của 1.0.4 (bỏ 2 hàm sendGetChatSeen/sendGetGroupSeen — chúng lấy danh sách người đã xem tin của CHÍNH mình, không thuộc luồng cần chặn), thêm lớp màn hình chat (BaseChatTVC, 4 hàm) và lớp xử lý (BaseChatProcessor) — các cửa phát sinh "đã xem" ngay khi mở đoạn chat — cùng addChatSeenWithLastChatEntity: và cửa delivered 3 tham số. Riêng addChatSeenWithLastChatEntity: lấy từ bộ móc của ZaloTools, chưa có trong log máy thật: nếu Zalo không có hàm này, bộ lắp móc tự ghi log và bỏ qua, không ảnh hưởng gì.
- **Đang nhập móc ở cả hai điểm:** ChatDataManager sendTypingWithType:... (4 tham số) và ChatSocketCmdHelper sendStatusTyping:... (5 tham số). Cổng kiểm tra mã kiểu nay bỏ qua các ký tự định tính (const/in/out...) — nhiều khả năng đó là lý do sendStatusTyping bị từ chối ở 1.0.4; từ bản này, hàm nào bị bỏ qua đều ghi rõ mã kiểu của nó vào log để vòng sau chỉnh đúng từng chữ.
- **Log thêm dòng "lần đầu được gọi" cho từng cửa:** mở đoạn chat mà cửa nào chạy là log có bằng chứng ngay, kể cả khi cửa đó đang được chuyển tiếp — vòng thử này sẽ chỉ đích danh cửa còn rò, nếu còn.
- Mỗi mục đều kiểm tra: class có thật không, hàm có thật không, số tham số có đúng kỳ vọng không, mã kiểu có an toàn không — sai bất kỳ điều nào thì ghi log và bỏ qua. Không đụng vào bất kỳ hàm nào khác của Zalo.
- Giữ nguyên từ 1.0.3: filter đúng mã Zalo iOS vn.com.vng.zingalo (kèm com.vng.zalo dự phòng), entry Cài đặt không khoá icon, chẩn đoán trong trang Cài đặt.
- **Kết quả thử trên máy (11-24, log phiên 01:20):** hết văng thật khi mở đoạn chat — gốc ARC đã cắt trúng. 25/27 cửa lắp được và đều chặn thật khi mở nhóm (cửa màn hình chat bắt qua chuỗi class cha từ BaseChatTVC, setLastSeenObject:/clearMention... của model nhóm, forceSendSeenServer, addChatSeen 23 lần lúc đồng bộ). Chữ vẫn mất đậm → phát hiện đường lớp dữ liệu (xem mục 1.0.6). Hai hàm đang nhập vẫn bị từ chối, log ghi rõ mã kiểu trả về B/Q — đầu mối để sửa ở 1.0.6.

## Có gì mới ở 1.0.4 (bản đã build và thử trên máy)

- **Đổi hẳn cơ chế móc: danh sách trắng cố định 21 hàm** thay cho dò theo mẫu của 1.0.3 (cơ chế cũ khớp chuỗi con "read" trong "thread/already/ready..." làm 877 hàm bị móc oan và Zalo văng ngay khi mở). 21 hàm phủ 3 lớp: quản lý + gửi (ChatSendSeenDataManager, 7 hàm), socket (ChatSocketCmdHelper: 2 hàm seen ACK, 4 hàm delivered, 2 hàm lấy danh sách đã xem), trạng thái trong máy (ConversationModel, 5 hàm), cộng 1 hàm đang nhập 5 tham số (sendStatusTyping — bị cổng kiểm tra mã kiểu từ chối nên chưa từng lắp được).
- Kết quả thử trên máy: hết văng khi mở app, nhưng **vẫn văng khi ấn vào một đoạn chat** và **chưa chặn được đã xem** — gốc của cả hai hoá ra là một: hàm thay thế tự retain tham số (xem mục 1.0.5).
- (Mục này trước đây mô tả một bản dự thảo 29 hàm kèm chốt tự bảo vệ — bản dự thảo đó chưa từng được build hay cài lên máy; đã huỷ bỏ.)



## Có gì mới ở 1.0.3

- Sửa lỗi gốc khiến tweak không bao giờ chạy: mã nhận diện của Zalo trên iOS là "vn.com.vng.zingalo" (theo đúng hồ sơ App Store của Apple), không phải "com.vng.zalo" (đó là mã của bản macOS). Bộ lọc chích đã sửa lại cho khớp — các bản trước lọc sai mã nên hệ thống không nạp tweak vào Zalo.


## Có gì mới ở 1.0.2

- Sửa lỗi trang Cài đặt báo thiếu file: file khai báo mục Cài đặt (PreferenceLoader) có một khoá icon rỗng mà các tweak đang chạy tốt không hề có — đã gỡ bỏ, đưa file về đúng khuôn mẫu.


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

Zalo là app đóng, không ai ngoài VNG biết chính xác hàm nào trong app phụ trách đánh dấu đã đọc. Bản này dùng cơ chế **danh sách trắng + chặn**: tweak chỉ móc đúng 27 hàm đã được kiểm chứng từ log máy thật (và đối chiếu bộ móc của một tweak cùng mục đích) — không quét, không khớp mẫu, không đụng vào bất kỳ hàm nào khác của Zalo. Hàm bị móc sẽ không được chạy khi tính năng đang bật — vì vậy trạng thái đã đọc không bị lật và máy chủ không nhận được sự kiện.

Mọi ứng viên tìm thấy, móc nào thành công, lần chặn nào xảy ra đều được ghi vào log `ZaloUnseen.log` trong thư mục Documents của Zalo (xem bằng Filza → Apps → Zalo → Documents). Nếu bản này chưa chặn trúng chỗ trên phiên bản Zalo của bạn, gửi file log đó lại — vòng sau chỉnh đúng tên hàm thật mà log đã phơi ra.

## Giới hạn thật

- Phải kiểm chứng bằng **2 tài khoản**: máy phụ gửi tin, máy này mở ra đọc — bên phụ vẫn chỉ thấy "đã nhận" và đoạn chat bên này vẫn chữ đậm là đạt.
- Nếu bạn **trả lời** tin nhắn thì Zalo tự đánh dấu đã xem lúc gửi — đúng bản chất, không giấu được.
- Chỉ có tác dụng trên điện thoại đã cài tweak. Mở Zalo trên máy tính hay thiết bị khác thì phía đó vẫn tính đã xem như bình thường.
- Zalo cập nhật phiên bản lớn có thể đổi tên hàm bên trong — khi đó gửi lại log, mình chỉnh theo.
- Tắt công tắc tổng trong Cài đặt là mọi hàm móc chạy lại y như gốc, không cần gỡ tweak.

## Cài đặt

Build bằng GitHub Actions (workflow trong `.github/workflows/build.yml`) hoặc up nguyên file zip nguồn lên repo đã cài sẵn workflow "mở zip" — Actions tự mở zip và build 3 bản. Cài bản rootless bằng Sileo, respring, mở Zalo dùng như bình thường.
