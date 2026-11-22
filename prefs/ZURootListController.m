// ZURootListController 1.0.0 — trang Cài đặt của ZaloUnseen.
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
    NSString *msg;
    if (!cand && !hooked) {
        msg = @"Chưa có dữ liệu. Mở app Zalo một lúc rồi quay lại đây kiểm tra.\n\nNếu vẫn trống thì gửi mình file log trong Documents của Zalo (Filza → Apps → Zalo → Documents → ZaloUnseen.log).";
    } else {
        msg = [NSString stringWithFormat:
            @"Lần quét gần nhất: %@\nỨng viên tìm thấy: %@\nĐã móc thành công: %@\nBỏ qua (kiểu dữ liệu không an toàn): %@\nĐã chặn 'đã xem': %@ lần\nĐã chặn 'đang nhập': %@ lần\nSự kiện gần nhất: %@",
            scan ?: @"—", cand ?: @0, hooked ?: @0, skipped ?: @0,
            blockedRead ?: @0, blockedType ?: @0, last.length ? last : @"—"];
    }
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Trạng thái dò" message:msg preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

@end
