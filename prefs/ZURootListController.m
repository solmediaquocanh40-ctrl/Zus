// ZURootListController 1.0.5 — trang Cài đặt của ZaloUnseen.
#import "ZURootListController.h"
#import "ZUShared.h"

@implementation ZURootListController

- (NSArray *)specifiers {
    if (!_specifiers) {
        _specifiers = [self loadSpecifiersFromPlistName:@"Root" target:self];
    }
    return _specifiers;
}

static id ZUDiagValue(NSString *key) {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)key, (__bridge CFStringRef)ZU_DOMAIN);
    return (__bridge_transfer id)v;
}

- (void)showDiag {
    NSNumber *cand = ZUDiagValue(ZU_DIAG_CANDIDATES);
    NSNumber *hooked = ZUDiagValue(ZU_DIAG_HOOKED);
    NSNumber *skipped = ZUDiagValue(ZU_DIAG_SKIPPED);
    NSNumber *blockedRead = ZUDiagValue(ZU_DIAG_BLOCKED_READ);
    NSNumber *blockedType = ZUDiagValue(ZU_DIAG_BLOCKED_TYPE);
    NSString *last = ZUDiagValue(ZU_DIAG_LAST);
    NSString *scan = ZUDiagValue(ZU_DIAG_SCAN);
    NSString *ctor = ZUDiagValue(ZU_DIAG_CTOR);
    NSString *msg;
    if (!cand && !hooked) {
        if (ctor.length) {
            msg = [NSString stringWithFormat:
                @"Tweak ĐÃ nạp vào Zalo lúc %@ nhưng chưa quét được dữ liệu.\n\nMở app Zalo, vào một đoạn chat bất kỳ, đợi vài giây rồi quay lại đây kiểm tra.", ctor];
        } else {
            msg = @"Tweak CHƯA từng nạp vào Zalo (không có mốc nạp).\n\nMở app Zalo một lúc rồi quay lại đây kiểm tra. Nếu vẫn trống thì gửi mình file log trong Documents của Zalo (Filza → Apps → Zalo → Documents → ZaloUnseen.log).";
        }
    } else {
        msg = [NSString stringWithFormat:
            @"Đã nạp vào Zalo: %@\nLần quét gần nhất: %@\nỨng viên tìm thấy: %@\nĐã móc thành công: %@\nBỏ qua (kiểu dữ liệu không an toàn): %@\nĐã chặn 'đã xem': %@ lần\nĐã chặn 'đang nhập': %@ lần\nSự kiện gần nhất: %@",
            ctor.length ? ctor : @"—", scan ?: @"—", cand ?: @0, hooked ?: @0, skipped ?: @0,
            blockedRead ?: @0, blockedType ?: @0, last.length ? last : @"—"];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Trạng thái dò" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
