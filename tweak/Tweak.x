// ZaloUnseen 1.0.6 — đọc tin nhắn Zalo mà bên kia không thấy "đã xem", tắt "đang nhập...".
//
// SỬA GỐC VỤ VĂNG CỦA 1.0.4 (đã chứng minh ở mức lệnh máy từ file .ips và đúng
// file .deb đã cài): hàm thay thế chung ZUGenericHook khai tham số kiểu `id`,
// dưới ARC trình biên dịch tự chèn objc_retain cho CẢ hai tham số ngay khi vào
// hàm. Hàm đích nào có tham số thứ hai là SỐ NGUYÊN (ví dụ phần `type:` của
// ConversationModel.updateLastSeenWithMessage:type:) thì lệnh retain đó đọc
// con số như một địa chỉ bộ nhớ → EXC_BAD_ACCESS tại đúng giá trị của con số
// (0x20), trên hàng đợi của model nhóm, chết trước khi kịp chặn hay ghi log.
// 1.0.5: mọi hàm thay thế khai tham số là __unsafe_unretained / void* — ARC
// không retain bất cứ tham số nào nữa; chữ ký gọi bản gốc cũng khai tương ứng.
//
// Cơ chế DANH SÁCH TRẮNG (từ 1.0.4): chỉ móc đúng các hàm GỬI trạng thái
// đã xem / đang nhập đã được kiểm chứng — từ log máy thật của bản 1.0.3 và từ bộ
// móc của ZaloTools (BVN) mà Quoc đã thử trên đúng bản Zalo này: lớp màn hình chat
// (BaseChatTVC), lớp xử lý (BaseChatProcessor), lớp quản lý hàng đợi + gửi
// (ChatSendSeenDataManager, ChatDataManager), lớp socket (ChatSocketCmdHelper)
// và lớp trạng thái trong máy (ConversationModel); 1.0.6 thêm lớp dữ liệu
// (ChatDataManager, ChatDataFlow, InboxDataManager, ChatProcessor). Tổng 36 hàm.
// 1.0.5 bỏ hai hàm sendGetChatSeen/sendGetGroupSeen từng có trong danh sách dự
// thảo: hai hàm đó LẤY danh sách người đã xem tin của CHÍNH mình — không thuộc
// luồng cần chặn, móc chúng có nguy cơ làm hỏng mục "ai đã xem" trong nhóm.
// Thêm ghi nhận "lần đầu được gọi" cho từng cửa: vòng thử sau chỉ cần nhìn log
// là biết cửa nào thật sự chạy khi mở đoạn chat, kể cả cửa được chuyển tiếp.
//
// 1.0.6 — HAI THAY ĐỔI TỪ LOG MÁY THẬT CỦA 1.0.5 (phiên 01:20 ngày 11-24):
// (a) 1.0.5 HẾT VĂNG THẬT nhưng chữ vẫn mất đậm, dù log chứng minh cả 25 cửa
// lắp được đều chạy và bị chặn khi mở nhóm — kể cả setLastSeenObject: trong
// máy và forceSendSeenServer ra máy chủ. Kết luận: luồng đánh dấu đã đọc còn
// chạy qua LỚP DỮ LIỆU (ghi trạng thái đã xem vào giao diện + cơ sở dữ liệu)
// nằm ngoài 25 cửa. 1.0.6 thêm 9 cửa lớp dữ liệu (tổng 36): họ
// processUpdateStatus...withUI:withDB: của ChatDataManager / ChatDataFlow /
// InboxDataManager, processResetUnread... của ChatProcessor, và
// updateMaxSeenGlobalId: / checkSendClearUnreadType: của ChatDataManager —
// tên hàm lấy từ danh sách ứng viên trong chính bản Zalo của máy (log 1.0.3).
// (b) ĐANG NHẬP: log 1.0.5 ghi rõ mã kiểu — sendTyping... trả về B,
// sendStatusTyping... trả về Q. Nguyên nhân bị từ chối ở 1.0.4 KHÔNG phải ký
// tự định tính (giả thuyết cũ đã sai): cổng chỉ nhận hàm trả về void. 1.0.6
// nới cổng cho mọi kiểu trả về vô hướng/con trỏ và mọi hàm thay thế trả lại
// long long: chuyển tiếp thì trả nguyên giá trị gốc, chặn thì trả 0.
//
// Vì sao bỏ cơ chế dò theo mẫu của 1.0.0–1.0.3: log 1.0.3 cho thấy mẫu khớp theo
// chuỗi con đã nổ tung — chữ "read" nằm trong "thread", "already", "ready", "reader"
// nên 1.162 ứng viên lọt lưới, 877 hàm bị móc, phần lớn là hàm gán dữ liệu
// (setThreadId:...) khắp app. Chặn các hàm gán đó làm Zalo sập ngay khi mở.
// Từ 1.0.4: không quét, không khớp mẫu — danh sách cố định, hàm nào không thấy
// hoặc kiểu dữ liệu không khớp kỳ vọng thì ghi log và bỏ qua, tuyệt đối không
// đụng vào phần còn lại của app.

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "ZUShared.h"

// ---------------- Cài đặt ----------------
static BOOL gEnabled = YES;
static BOOL gUnseen = YES;
static BOOL gHideTyping = YES;
static BOOL gDebug = YES;

static BOOL ZUReadBool(NSString *key, BOOL def) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)ZU_DOMAIN);
    if (!v) return def;
    BOOL r = def;
    if (CFGetTypeID(v) == CFBooleanGetTypeID()) r = CFBooleanGetValue((CFBooleanRef)v);
    else if (CFGetTypeID(v) == CFNumberGetTypeID()) { int n = 0; CFNumberGetValue((CFNumberRef)v, kCFNumberIntType, &n); r = (n != 0); }
    CFRelease(v);
    return r;
}

static void ZULoadPrefs(void) {
    CFPreferencesAppSynchronize((__bridge CFStringRef)ZU_DOMAIN);
    gEnabled = ZUReadBool(ZU_KEY_ENABLED, YES);
    gUnseen = ZUReadBool(ZU_KEY_UNSEEN, YES);
    gHideTyping = ZUReadBool(ZU_KEY_TYPING, YES);
    gDebug = ZUReadBool(ZU_KEY_DEBUG, YES);
}

static void ZUPrefsChanged(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    ZULoadPrefs();
}

// ---------------- Log ----------------
static NSString *gLogPath = nil;
static id gLogLock = nil;
static NSDateFormatter *gLogFmt = nil;

static void ZULog(NSString *fmt, ...) {
    if (!gDebug) return;
    va_list ap; va_start(ap, fmt);
    NSString *msg = [[NSString alloc] initWithFormat:fmt arguments:ap];
    va_end(ap);
    NSLog(@"[ZaloUnseen] %@", msg);
    if (!gLogPath || !gLogLock) return;
    NSString *line = [NSString stringWithFormat:@"%@ %@\n", [gLogFmt stringFromDate:[NSDate date]], msg];
    @synchronized (gLogLock) {
        NSFileHandle *h = [NSFileHandle fileHandleForWritingAtPath:gLogPath];
        if (h) { [h seekToEndOfFile]; [h writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [h closeFile]; }
        else [line writeToFile:gLogPath atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// ---------------- Chẩn đoán (ghi vào kho cài đặt cho trang Cài đặt đọc) ----------------
static long gBlockedRead = 0;
static long gBlockedTyping = 0;
static NSString *gLastEvent = @"";
static NSTimeInterval gLastDiagWrite = 0;

static void ZUWriteDiag(void) {
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_BLOCKED_READ, (__bridge CFPropertyListRef)@(gBlockedRead), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_BLOCKED_TYPE, (__bridge CFPropertyListRef)@(gBlockedTyping), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_LAST, (__bridge CFPropertyListRef)gLastEvent, (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesAppSynchronize((__bridge CFStringRef)ZU_DOMAIN);
    gLastDiagWrite = [NSDate timeIntervalSinceReferenceDate];
}

static void ZUWriteDiagThrottled(void) {
    if ([NSDate timeIntervalSinceReferenceDate] - gLastDiagWrite < 2.0) return;
    ZUWriteDiag();
}

// ---------------- Kiểm tra kiểu dữ liệu ----------------
// Kiểu trả về an toàn cho hàm thay thế trả long long: void, BOOL, mọi số nguyên
// và mọi con trỏ/object đều về qua thanh ghi x0 (void thì nơi gọi bỏ qua x0),
// nên giá trị gốc được giữ nguyên bit khi chuyển tiếp, chặn thì trả 0.
// Loại trừ: float/double (về qua thanh ghi s/d riêng) và struct/mảng/hợp —
// cơ chế trả khác hẳn, gặp là bỏ qua cửa đó.
// Bài học từ log 1.0.5: hai hàm đang nhập trả về B và Q đã bị cổng cũ (chỉ nhận
// void) từ chối oan — đó là nguyên nhân thật của vụ từ chối ở 1.0.4, không phải
// các ký tự định tính như đã đoán trước đây.
static BOOL ZUReturnTypeIsSafe(const char *enc) {
    if (!enc) return NO;
    char c = enc[0];
    if (c == 'r' || c == 'n' || c == 'N' || c == 'o' || c == 'O' || c == 'R' || c == 'V') c = enc[1];
    return (c == 'v' || c == 'B' || c == 'c' || c == 'C' || c == 's' || c == 'S' ||
            c == 'i' || c == 'I' || c == 'l' || c == 'L' || c == 'q' || c == 'Q' ||
            c == '@' || c == '#' || c == ':' || c == '*' || c == '^');
}

// Hàm thường (tối đa 2 tham số thật): kiểu trả về phải qua được cổng trên và
// mọi tham số đều là con trỏ/số nguyên (đi qua thanh ghi, chuyển tiếp an toàn).
static BOOL ZUEncodingIsSafe(Method m) {
    const char *enc = method_getTypeEncoding(m);
    if (!ZUReturnTypeIsSafe(enc)) return NO;
    unsigned argc = method_getNumberOfArguments(m);
    if (argc < 2 || argc > 4) return NO;
    for (unsigned i = 2; i < argc; i++) {
        char t[64];
        method_getArgumentType(m, i, t, sizeof(t));
        char c = t[0];
        // Bỏ qua ký tự định tính của mã kiểu (const/in/out/byref...) nếu nó đứng
        // đầu mã kiểu của tham số: chúng chỉ là chú thích, không ảnh hưởng thanh ghi.
        if (c == 'r' || c == 'n' || c == 'N' || c == 'o' || c == 'O' || c == 'R' || c == 'V') c = t[1];
        if (c == '@' || c == '#' || c == ':' || c == 'i' || c == 'I' || c == 's' || c == 'S' ||
            c == 'l' || c == 'L' || c == 'q' || c == 'Q' || c == 'c' || c == 'C' || c == 'B' ||
            c == '*' || c == '^') continue;
        return NO;
    }
    return YES;
}

// Hàm nhiều tham số (3–6): trên ARM64 tham số nguyên/con trỏ đều nằm trọn
// trong thanh ghi 64-bit nên chuyển tiếp theo từng ô nhớ là an toàn — với điều kiện
// mã kiểu KHÔNG chứa float/double/struct/mảng/hợp/bitfield. Quét toàn bộ chuỗi mã
// kiểu: chỉ cho phép các ký tự của kiểu nguyên/con trỏ/chữ ký số, cộng '?' của
// tham số block (@?) — hai cửa lớp dữ liệu có tham số hoàn-tất dạng block.
static BOOL ZUEncodingIsSafeN(Method m, int n) {
    const char *enc = method_getTypeEncoding(m);
    if (!ZUReturnTypeIsSafe(enc)) return NO;
    if (method_getNumberOfArguments(m) != (unsigned)(n + 2)) return NO;
    for (const char *p = enc; *p; p++) {
        char c = *p;
        if (c == 'v' || c == '@' || c == ':' || c == '#' || c == 'i' || c == 'I' ||
            c == 's' || c == 'S' || c == 'l' || c == 'L' || c == 'q' || c == 'Q' ||
            c == 'c' || c == 'C' || c == 'B' || c == '*' || c == '^' || c == '?' ||
            c == 'r' || c == 'n' || c == 'N' || c == 'o' || c == 'O' || c == 'R' || c == 'V' ||
            (c >= '0' && c <= '9')) continue;
        return NO;
    }
    return YES;
}

// ---------------- Kho bản gốc ----------------
static NSMutableDictionary *gOrigs = nil; // "khoá" -> IMP gốc
static NSMutableDictionary *gCats = nil;  // "khoá" -> nhóm (1/2)

static NSString *ZUKeyFor(Class cls, SEL sel, BOOL isClass) {
    return [NSString stringWithFormat:@"%@%@|%@", isClass ? @"+" : @"-", NSStringFromClass(cls), NSStringFromSelector(sel)];
}

// Đi dọc chuỗi class cha để tìm bản gốc đã móc (self có thể là class con của class đã móc).
static NSMutableSet *gCalledOnce = nil; // khoá của các cửa đã ghi "lần đầu được gọi"

static void ZUFindOrigCat(id self, SEL _cmd, void **outOrig, int *outCat, NSString **outKey) {
    *outOrig = NULL; *outCat = 0;
    if (outKey) *outKey = nil;
    BOOL meta = class_isMetaClass(object_getClass(self));
    Class walk = meta ? (Class)self : object_getClass(self);
    while (walk) {
        NSString *k = ZUKeyFor(walk, _cmd, meta);
        NSValue *v = nil; NSNumber *c = nil;
        @synchronized (gOrigs) { v = gOrigs[k]; c = gCats[k]; }
        if (v) { *outOrig = [v pointerValue]; *outCat = [c intValue]; if (outKey) *outKey = k; return; }
        walk = class_getSuperclass(walk);
    }
}

// Ghi đúng một dòng cho lần đầu mỗi cửa thật sự được gọi trong phiên chạy này —
// bằng chứng cửa nào nằm trên luồng mở đoạn chat, kể cả khi cửa đó được chuyển tiếp.
static void ZUNoteCalledOnce(id self, SEL _cmd, NSString *key) {
    if (!key || !gCalledOnce) return;
    BOOL first = NO;
    @synchronized (gCalledOnce) {
        if (![gCalledOnce containsObject:key]) { [gCalledOnce addObject:key]; first = YES; }
    }
    if (first) ZULog(@"lần đầu được gọi: %@.%@", NSStringFromClass(object_getClass(self)), NSStringFromSelector(_cmd));
}

static void ZUNoteBlocked(id self, SEL _cmd, int cat) {
    NSString *desc = [NSString stringWithFormat:@"%@.%@", NSStringFromClass(object_getClass(self)), NSStringFromSelector(_cmd)];
    NSString *event = nil;
    // Các hàm bị móc chạy trên nhiều hàng đợi khác nhau (socket, model nhóm...):
    // bộ đếm và sự kiện gần nhất phải cập nhật trong khoá, tránh hai luồng cùng ghi.
    @synchronized (gOrigs) {
        if (cat == 1) { gBlockedRead++; gLastEvent = [NSString stringWithFormat:@"chặn đã-xem: %@", desc]; }
        else { gBlockedTyping++; gLastEvent = [NSString stringWithFormat:@"chặn đang-nhập: %@", desc]; }
        event = gLastEvent;
    }
    ZULog(@"ĐÃ CHẶN %@", event);
    ZUWriteDiagThrottled();
}

// Hàm thay thế chung cho các hàm tối đa 2 tham số: bật tính năng thì chặn
// (không chạy gốc, trả 0), tắt thì chạy gốc và trả NGUYÊN giá trị gốc.
// Từ 1.0.6 mọi hàm thay thế trả long long: hàm đích trả số nguyên/BOOL/con trỏ
// đều về qua x0 nên giữ nguyên bit; hàm trả void thì nơi gọi bỏ qua x0.
// QUAN TRỌNG (gốc vụ văng 1.0.4): tham số PHẢI khai __unsafe_unretained.
// Khai `id` thường thì ARC coi chúng là strong và tự chèn objc_retain cho từng
// tham số ngay khi vào hàm — hàm đích nào có tham số là số nguyên (không phải
// object) sẽ bị retain như một địa chỉ bộ nhớ và sập ngay tại cửa, trước khi
// kịp chặn hay ghi log (đã chứng minh ở mức lệnh máy từ file .ips của 1.0.4).
static long long ZUGenericHook(__unsafe_unretained id self, SEL _cmd, __unsafe_unretained id a1, __unsafe_unretained id a2) {
    void *orig = NULL; int cat = 0; NSString *key = nil;
    ZUFindOrigCat(self, _cmd, &orig, &cat, &key);
    ZUNoteCalledOnce(self, _cmd, key);
    BOOL active = gEnabled && ((cat == 1 && gUnseen) || (cat == 2 && gHideTyping));
    if (active) { ZUNoteBlocked(self, _cmd, cat); return 0; }
    if (orig) return ((long long (*)(__unsafe_unretained id, SEL, __unsafe_unretained id, __unsafe_unretained id))orig)(self, _cmd, a1, a2);
    return 0;
}

// Hàm thay thế cho các hàm 5 tham số nguyên/con trỏ (sendStatusTyping trả về Q;
// từ 1.0.6 thêm cửa lớp dữ liệu 5 tham số thuộc nhóm đã-xem — điều kiện kích
// hoạt phải xét cả hai nhóm như các hàm thay thế khác, nếu chỉ xét nhóm
// đang-nhập như trước đây thì cửa đã-xem 5 tham số sẽ không bao giờ bị chặn).
static long long ZUHook5(__unsafe_unretained id self, SEL _cmd, void *a1, void *a2, void *a3, void *a4, void *a5) {
    void *orig = NULL; int cat = 0; NSString *key = nil;
    ZUFindOrigCat(self, _cmd, &orig, &cat, &key);
    ZUNoteCalledOnce(self, _cmd, key);
    BOOL active = gEnabled && ((cat == 1 && gUnseen) || (cat == 2 && gHideTyping));
    if (active) { ZUNoteBlocked(self, _cmd, cat); return 0; }
    if (orig) return ((long long (*)(__unsafe_unretained id, SEL, void *, void *, void *, void *, void *))orig)(self, _cmd, a1, a2, a3, a4, a5);
    return 0;
}

// Hàm thay thế cho các hàm 3 tham số nguyên/con trỏ (cùng nguyên tắc thanh ghi).
static long long ZUHook3(__unsafe_unretained id self, SEL _cmd, void *a1, void *a2, void *a3) {
    void *orig = NULL; int cat = 0; NSString *key = nil;
    ZUFindOrigCat(self, _cmd, &orig, &cat, &key);
    ZUNoteCalledOnce(self, _cmd, key);
    BOOL active = gEnabled && ((cat == 1 && gUnseen) || (cat == 2 && gHideTyping));
    if (active) { ZUNoteBlocked(self, _cmd, cat); return 0; }
    if (orig) return ((long long (*)(__unsafe_unretained id, SEL, void *, void *, void *))orig)(self, _cmd, a1, a2, a3);
    return 0;
}

// Hàm thay thế cho các hàm 4 tham số nguyên/con trỏ (gửi đang nhập ở ChatDataManager).
static long long ZUHook4(__unsafe_unretained id self, SEL _cmd, void *a1, void *a2, void *a3, void *a4) {
    void *orig = NULL; int cat = 0; NSString *key = nil;
    ZUFindOrigCat(self, _cmd, &orig, &cat, &key);
    ZUNoteCalledOnce(self, _cmd, key);
    BOOL active = gEnabled && ((cat == 1 && gUnseen) || (cat == 2 && gHideTyping));
    if (active) { ZUNoteBlocked(self, _cmd, cat); return 0; }
    if (orig) return ((long long (*)(__unsafe_unretained id, SEL, void *, void *, void *, void *))orig)(self, _cmd, a1, a2, a3, a4);
    return 0;
}

// Hàm thay thế cho các hàm 6 tham số nguyên/con trỏ (mới ở 1.0.6, cho cửa lớp
// dữ liệu InboxDataManager.processUpdateStatusInboxEntityThreadId:msgType:
// newStatus:seenTime:updateUI:updateDB:). 6 tham số thật vẫn nằm trọn trong
// thanh ghi x2–x7; từ 7 tham số trở lên tham số tràn xuống ngăn xếp nên KHÔNG
// dùng mẫu này — đó là lý do cửa 7 tham số của InboxDataManager tạm chưa móc.
static long long ZUHook6(__unsafe_unretained id self, SEL _cmd, void *a1, void *a2, void *a3, void *a4, void *a5, void *a6) {
    void *orig = NULL; int cat = 0; NSString *key = nil;
    ZUFindOrigCat(self, _cmd, &orig, &cat, &key);
    ZUNoteCalledOnce(self, _cmd, key);
    BOOL active = gEnabled && ((cat == 1 && gUnseen) || (cat == 2 && gHideTyping));
    if (active) { ZUNoteBlocked(self, _cmd, cat); return 0; }
    if (orig) return ((long long (*)(__unsafe_unretained id, SEL, void *, void *, void *, void *, void *, void *))orig)(self, _cmd, a1, a2, a3, a4, a5, a6);
    return 0;
}

// ---------------- Danh sách trắng (log máy thật 1.0.3 + điểm móc ZaloTools đã kiểm chứng) ----------------
// cat: 1 = đã-xem, 2 = đang-nhập. argc = số tham số thật kỳ vọng (không tính self/_cmd).
typedef struct {
    const char *cls;
    const char *sel;
    int cat;
    int argc;
} ZUEntry;

static const ZUEntry kZUWhitelist[] = {
    // Lớp màn hình chat: điểm phát sinh "đã xem" khi mở đoạn chat
    { "BaseChatTVC", "sendSeenInfoInboxEntity:", 1, 1 },
    { "BaseChatTVC", "sendSeenForLastReadMessage", 1, 0 },
    { "BaseChatTVC", "sendSeenMessageWithChatEntity:", 1, 1 },
    { "BaseChatTVC", "sendSeenMessageWithTalkTableItem:", 1, 1 },
    // Lớp xử lý chat
    { "BaseChatProcessor", "sendSeenMessages:messageDict:incomingData:", 1, 3 },
    // Lớp quản lý hàng đợi + gửi "đã xem" lên máy chủ
    { "ChatSendSeenDataManager", "sendSeenWithChatEntity:", 1, 1 },
    { "ChatSendSeenDataManager", "addChatSeenWithLastChatEntity:", 1, 1 },
    { "ChatSendSeenDataManager", "_sendSeenMessageWithSeenData:messageType:", 1, 2 },
    { "ChatSendSeenDataManager", "sendSeenLastMessageWithThreadIds:withMessageType:", 1, 2 },
    { "ChatSendSeenDataManager", "sendSeenServer", 1, 0 },
    { "ChatSendSeenDataManager", "forceSendSeenServer", 1, 0 },
    { "ChatSendSeenDataManager", "sendSeenServerPeriodicallyIfNeeded", 1, 0 },
    { "ChatSendSeenDataManager", "sendAllFailedSeenMessage", 1, 0 },
    // Lớp socket: xác nhận đã nhận/đã xem đi thẳng ra đường truyền
    { "ChatSocketCmdHelper", "sendSeenChatACK:withSubCommandType:", 1, 2 },
    { "ChatSocketCmdHelper", "sendSeenGroupChatACKByData:withSubCommandType:", 1, 2 },
    { "ChatSocketCmdHelper", "sendSingleChatDeliveredMessages:isSeen:", 1, 2 },
    { "ChatSocketCmdHelper", "sendE2eeSingleChatDeliveredMessages:isSeen:", 1, 2 },
    { "ChatSocketCmdHelper", "sendGroupChatDeliveredMessages:isSeen:", 1, 2 },
    { "ChatSocketCmdHelper", "sendE2eeGroupChatDeliveredMessages:isSeen:", 1, 2 },
    { "ChatSocketCmdHelper", "sendChatDeliveredMessages:isSeen:commandType:", 1, 3 },
    // Lớp cập nhật trạng thái đã xem ngay trong máy (giữ chữ đậm trong danh sách chat)
    { "ConversationModel", "updateLastSeenWithMessage:type:", 1, 2 },
    { "ConversationModel", "_updateLastSeenWithMessage:type:", 1, 2 },
    { "ConversationModel", "updateLocalLastSeenMessageWithDelay", 1, 0 },
    { "ConversationModel", "clearMentionAndUpdateLastSeenWithDelay:", 1, 1 },
    { "ConversationModel", "setLastSeenObject:", 1, 1 },
    // Lớp dữ liệu: ghi trạng thái đã xem thẳng vào giao diện + cơ sở dữ liệu —
    // đường rò mà log 1.0.5 đã chứng minh (cả 25 cửa trên đều chặn mà chữ vẫn
    // mất đậm). Tên hàm lấy từ danh sách ứng viên trong chính bản Zalo của máy
    // (log 1.0.3). Cửa InboxDataManager 7 tham số (processUpdateStatusInbox-
    // EntityForThreadId:globalId:clientId:messageType:newStatus:updateUI:
    // updateDB:) tạm chưa móc — xem ghi chú ở ZUHook6.
    { "ChatDataManager", "processUpdateStatusChatSeenChatGroup:withNewStatusSeen:withUI:withDB:", 1, 4 },
    { "ChatDataFlow", "processUpdateStatusSeenChatGroup:withNewStatusSeen:withUI:withDB:", 1, 4 },
    { "InboxDataManager", "processUpdateStatusInboxEntityThreadId:msgType:withNewStatus:withUI:withDB:", 1, 5 },
    { "InboxDataManager", "processUpdateStatusInboxEntityThreadId:msgType:newStatus:seenTime:updateUI:updateDB:", 1, 6 },
    { "InboxDataManager", "processDecreaseUnreadOfThread:withType:shouldUpdateDB:shouldUpdateUI:", 1, 4 },
    { "ChatProcessor", "processResetUnreadWithSeenData:msgType:withCompletion:", 1, 3 },
    { "ChatProcessor", "processResetUnreadOfThread:msgType:msgMarker:", 1, 3 },
    { "ChatDataManager", "updateMaxSeenGlobalId:withMessageType:withCompletion:", 1, 3 },
    { "ChatDataManager", "checkSendClearUnreadType:withInboxEntity:messageType:withToUserId:", 1, 4 },
    // Lớp gửi "đang nhập..."
    { "ChatDataManager", "sendTypingWithType:toUserId:messageType:isE2eeChat:", 2, 4 },
    { "ChatSocketCmdHelper", "sendStatusTyping:withCommand:withSubCommand:withDestType:withGlobalMessageId:", 2, 5 },
};
static const unsigned kZUWhitelistCount = sizeof(kZUWhitelist) / sizeof(kZUWhitelist[0]);

// ---------------- Lắp móc theo danh sách ----------------
static long gHookedTotal = 0;

static void ZUInstallHook(Class cls, Method m, BOOL isClass, int cat, IMP repl) {
    SEL sel = method_getName(m);
    NSString *key = ZUKeyFor(cls, sel, isClass);
    @synchronized (gOrigs) { if (gOrigs[key]) return; }
    Class target = isClass ? object_getClass(cls) : cls;
    void *orig = NULL;
    MSHookMessageEx(target, sel, repl, (IMP *)&orig);
    if (!orig) {
        ZULog(@"móc HỎNG: %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    @synchronized (gOrigs) {
        gOrigs[key] = [NSValue valueWithPointer:orig];
        gCats[key] = @(cat);
    }
    gHookedTotal++;
    ZULog(@"đã móc [%@] %@.%@ enc=%s", cat == 1 ? @"đã-xem" : @"đang-nhập", NSStringFromClass(cls), NSStringFromSelector(sel), method_getTypeEncoding(m));
}

static void ZUInstallWhitelist(void) {
    for (unsigned i = 0; i < kZUWhitelistCount; i++) {
        const ZUEntry *e = &kZUWhitelist[i];
        Class cls = objc_getClass(e->cls);
        if (!cls) {
            ZULog(@"chưa thấy class %s (mục %s)", e->cls, e->sel);
            continue;
        }
        SEL sel = sel_registerName(e->sel);
        Method m = class_getInstanceMethod(cls, sel);
        BOOL isClass = NO;
        if (!m) { m = class_getClassMethod(cls, sel); isClass = YES; }
        if (!m) {
            ZULog(@"không thấy hàm %s.%s", e->cls, e->sel);
            continue;
        }
        if ((int)method_getNumberOfArguments(m) - 2 != e->argc) {
            ZULog(@"bỏ qua (số tham số khác kỳ vọng): %s.%s", e->cls, e->sel);
            continue;
        }
        BOOL safe; IMP repl;
        if (e->argc <= 2)      { safe = ZUEncodingIsSafe(m);        repl = (IMP)ZUGenericHook; }
        else if (e->argc == 3) { safe = ZUEncodingIsSafeN(m, 3);    repl = (IMP)ZUHook3; }
        else if (e->argc == 4) { safe = ZUEncodingIsSafeN(m, 4);    repl = (IMP)ZUHook4; }
        else if (e->argc == 5) { safe = ZUEncodingIsSafeN(m, 5);    repl = (IMP)ZUHook5; }
        else                   { safe = ZUEncodingIsSafeN(m, 6);    repl = (IMP)ZUHook6; }
        if (!safe) {
            ZULog(@"bỏ qua (kiểu dữ liệu không an toàn): %s.%s enc=%s", e->cls, e->sel, method_getTypeEncoding(m));
            continue;
        }
        ZUInstallHook(cls, m, isClass, e->cat, repl);
    }
    ZULog(@"danh sách trắng: %u mục, đã móc tổng %ld", kZUWhitelistCount, gHookedTotal);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_CANDIDATES, (__bridge CFPropertyListRef)@(kZUWhitelistCount), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_HOOKED, (__bridge CFPropertyListRef)@(gHookedTotal), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_SKIPPED, (__bridge CFPropertyListRef)@((long)kZUWhitelistCount - gHookedTotal), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_SCAN, (__bridge CFPropertyListRef)[gLogFmt stringFromDate:[NSDate date]], (__bridge CFStringRef)ZU_DOMAIN);
    ZUWriteDiag();
}

// ---------------- Điểm vào ----------------
%ctor {
    @autoreleasepool {
        gOrigs = [[NSMutableDictionary alloc] init];
        gCats = [[NSMutableDictionary alloc] init];
        gCalledOnce = [[NSMutableSet alloc] init];
        gLogLock = [[NSObject alloc] init];
        gLogFmt = [[NSDateFormatter alloc] init];
        gLogFmt.dateFormat = @"MM-dd HH:mm:ss";
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        gLogPath = [docs stringByAppendingPathComponent:@"ZaloUnseen.log"];
        ZULoadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, ZUPrefsChanged,
                                        ZU_NOTIFY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        ZULog(@"ZaloUnseen 1.0.6 nạp vào Zalo (bật=%d, unseen=%d, ẩn đang nhập=%d)", gEnabled, gUnseen, gHideTyping);
        // Mốc "đã nạp" ghi thẳng vào kho prefs ngay khi ctor chạy (thêm ở 1.0.1):
        // bằng chứng tweak có chạy trong Zalo hay không, đọc được ở trang Cài đặt
        // lẫn file /var/mobile/Library/Preferences/com.anhdang.zalounseen.plist —
        // không phụ thuộc file log trong Documents của Zalo như bản 1.0.0.
        CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_CTOR,
                                 (__bridge CFPropertyListRef)[gLogFmt stringFromDate:[NSDate date]],
                                 (__bridge CFStringRef)ZU_DOMAIN);
        CFPreferencesAppSynchronize((__bridge CFStringRef)ZU_DOMAIN);
        // Lắp móc theo danh sách trắng sau 1 giây (thử lại 7 giây sau đó cho mục
        // nào class nạp muộn; hàm đã móc rồi thì tự bỏ qua).
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            ZUInstallWhitelist();
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(7 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ZUInstallWhitelist(); });
        });
    }
}
