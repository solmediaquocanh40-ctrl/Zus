// ZaloUnseen 1.0.0 — đọc tin nhắn Zalo mà bên kia không thấy "đã xem", tắt "đang nhập...".
//
// Cơ chế (bản 1.0.0 là bản DÒ + CHẶN): Zalo là app đóng, không ai ngoài VNG biết
// chính xác hàm nào đánh dấu đã đọc. Tweak quét toàn bộ class nằm trong gói Zalo.app,
// tìm các hàm khớp mẫu "động từ + read/seen/typing" (mark…Read, send…Seen, set…Typing…),
// kiểm tra kiểu dữ liệu an toàn rồi mới móc bằng MSHookMessageEx. Khi tính năng bật,
// hàm bị móc KHÔNG được chạy bản gốc: đoạn chat không bị lật trạng thái (danh sách chat
// giữ chữ đậm như chưa đọc) và máy chủ không nhận được sự kiện đã xem.
// Mọi ứng viên, móc thành công hay bỏ qua, đều ghi vào log ZaloUnseen.log trong
// Documents của chính Zalo để vòng sau chỉnh đúng tên hàm thật nếu cần.

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

// ---------------- Nhận diện ứng viên ----------------
// Trả 0 = không phải, 1 = nhóm đã-xem, 2 = nhóm đang-nhập.
static int ZUCategorize(NSString *selName) {
    NSString *s = [selName lowercaseString];
    static NSArray *prefixSkip = nil, *excl = nil, *verbs = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        prefixSkip = @[@"get", @"is", @"has", @"can", @"should", @"will", @"did", @"on"];
        excl = @[@"request", @"fetch", @"load", @"download", @"upload", @"cell", @"layout",
                 @"draw", @"image", @"color", @"height", @"width", @"size", @"url", @"http",
                 @"pay", @"emoji", @"sticker", @"avatar", @"animat", @"gesture", @"keyboard",
                 @"scroll", @"reuse", @"init", @"dealloc"];
        verbs = @[@"mark", @"send", @"set", @"update", @"report", @"post", @"push", @"commit"];
    });
    for (NSString *p in prefixSkip) if ([s hasPrefix:p]) return 0;
    for (NSString *e in excl) if ([s containsString:e]) return 0;
    BOOL hasVerb = NO;
    for (NSString *v in verbs) if ([s containsString:v]) { hasVerb = YES; break; }
    if (!hasVerb) return 0;
    if ([s containsString:@"typing"] || [s containsString:@"chatstate"]) return 2;
    if ([s containsString:@"read"] || [s containsString:@"seen"]) return 1;
    return 0;
}

// Chỉ móc hàm trả về void, tối đa 2 tham số thật, kiểu tham số đều là con trỏ/số nguyên
// (đi qua thanh ghi, chuyển tiếp an toàn). Có float/struct là bỏ qua.
static BOOL ZUEncodingIsSafe(Method m) {
    const char *enc = method_getTypeEncoding(m);
    if (!enc || enc[0] != 'v') return NO;
    unsigned argc = method_getNumberOfArguments(m);
    if (argc < 2 || argc > 4) return NO;
    for (unsigned i = 2; i < argc; i++) {
        char t[64];
        method_getArgumentType(m, i, t, sizeof(t));
        char c = t[0];
        if (c == '@' || c == '#' || c == ':' || c == 'i' || c == 'I' || c == 's' || c == 'S' ||
            c == 'l' || c == 'L' || c == 'q' || c == 'Q' || c == 'c' || c == 'C' || c == 'B' ||
            c == '*' || c == '^') continue;
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
static void ZUFindOrigCat(id self, SEL _cmd, void **outOrig, int *outCat) {
    *outOrig = NULL; *outCat = 0;
    BOOL meta = class_isMetaClass(object_getClass(self));
    Class walk = meta ? (Class)self : object_getClass(self);
    while (walk) {
        NSString *k = ZUKeyFor(walk, _cmd, meta);
        NSValue *v = nil; NSNumber *c = nil;
        @synchronized (gOrigs) { v = gOrigs[k]; c = gCats[k]; }
        if (v) { *outOrig = [v pointerValue]; *outCat = [c intValue]; return; }
        walk = class_getSuperclass(walk);
    }
}

// Hàm thay thế chung cho mọi móc: bật tính năng thì chặn (không chạy gốc), tắt thì chạy gốc.
static void ZUGenericHook(id self, SEL _cmd, id a1, id a2) {
    void *orig = NULL; int cat = 0;
    ZUFindOrigCat(self, _cmd, &orig, &cat);
    BOOL active = gEnabled && ((cat == 1 && gUnseen) || (cat == 2 && gHideTyping));
    if (active) {
        NSString *desc = [NSString stringWithFormat:@"%@.%@", NSStringFromClass(object_getClass(self)), NSStringFromSelector(_cmd)];
        if (cat == 1) { gBlockedRead++; gLastEvent = [NSString stringWithFormat:@"chặn đã-xem: %@", desc]; }
        else { gBlockedTyping++; gLastEvent = [NSString stringWithFormat:@"chặn đang-nhập: %@", desc]; }
        ZULog(@"ĐÃ CHẶN %@", gLastEvent);
        ZUWriteDiagThrottled();
        return;
    }
    if (orig) ((void (*)(id, SEL, id, id))orig)(self, _cmd, a1, a2);
}

// ---------------- Quét và móc ----------------
static long gHookedTotal = 0;

static void ZUInstallHook(Class cls, Method m, BOOL isClass, int cat) {
    SEL sel = method_getName(m);
    NSString *key = ZUKeyFor(cls, sel, isClass);
    @synchronized (gOrigs) { if (gOrigs[key]) return; }
    Class target = isClass ? object_getClass(cls) : cls;
    void *orig = NULL;
    MSHookMessageEx(target, sel, (IMP)ZUGenericHook, (IMP *)&orig);
    if (!orig) {
        ZULog(@"móc HỎNG: %@ %@", NSStringFromClass(cls), NSStringFromSelector(sel));
        return;
    }
    @synchronized (gOrigs) {
        gOrigs[key] = [NSValue valueWithPointer:orig];
        gCats[key] = @(cat);
    }
    gHookedTotal++;
    ZULog(@"đã móc [%@] %@.%@", cat == 1 ? @"đã-xem" : @"đang-nhập", NSStringFromClass(cls), NSStringFromSelector(sel));
}

static void ZUScanClass(Class cls, BOOL isClass, long *candTotal, long *skipTotal) {
    Class target = isClass ? object_getClass(cls) : cls;
    unsigned mc = 0;
    Method *methods = class_copyMethodList(target, &mc);
    for (unsigned j = 0; j < mc; j++) {
        Method m = methods[j];
        NSString *name = NSStringFromSelector(method_getName(m));
        int cat = ZUCategorize(name);
        if (!cat) continue;
        (*candTotal)++;
        if (!ZUEncodingIsSafe(m)) {
            (*skipTotal)++;
            ZULog(@"ứng viên bỏ qua (kiểu dữ liệu không an toàn): %@.%@", NSStringFromClass(cls), name);
            continue;
        }
        ZUInstallHook(cls, m, isClass, cat);
    }
    free(methods);
}

static void ZUScanAndHook(void) {
    long candTotal = 0, skipTotal = 0;
    unsigned count = 0;
    Class *classes = objc_copyClassList(&count);
    for (unsigned i = 0; i < count; i++) {
        Class cls = classes[i];
        const char *img = class_getImageName(cls);
        if (!img || !strstr(img, "Zalo.app")) continue;
        ZUScanClass(cls, NO, &candTotal, &skipTotal);
        ZUScanClass(cls, YES, &candTotal, &skipTotal);
    }
    free(classes);
    ZULog(@"quét xong: %ld ứng viên, đã móc tổng %ld, bỏ qua vì kiểu dữ liệu %ld", candTotal, gHookedTotal, skipTotal);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_CANDIDATES, (__bridge CFPropertyListRef)@(candTotal), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_HOOKED, (__bridge CFPropertyListRef)@(gHookedTotal), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_SKIPPED, (__bridge CFPropertyListRef)@(skipTotal), (__bridge CFStringRef)ZU_DOMAIN);
    CFPreferencesSetAppValue((__bridge CFStringRef)ZU_DIAG_SCAN, (__bridge CFPropertyListRef)[gLogFmt stringFromDate:[NSDate date]], (__bridge CFStringRef)ZU_DOMAIN);
    ZUWriteDiag();
}

// ---------------- Điểm vào ----------------
%ctor {
    @autoreleasepool {
        gOrigs = [[NSMutableDictionary alloc] init];
        gCats = [[NSMutableDictionary alloc] init];
        gLogLock = [[NSObject alloc] init];
        gLogFmt = [[NSDateFormatter alloc] init];
        gLogFmt.dateFormat = @"MM-dd HH:mm:ss";
        NSString *docs = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
        gLogPath = [docs stringByAppendingPathComponent:@"ZaloUnseen.log"];
        ZULoadPrefs();
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), NULL, ZUPrefsChanged,
                                        ZU_NOTIFY, NULL, CFNotificationSuspensionBehaviorDeliverImmediately);
        ZULog(@"ZaloUnseen 1.0.0 nạp vào Zalo (bật=%d, unseen=%d, ẩn đang nhập=%d)", gEnabled, gUnseen, gHideTyping);
        // Quét nhiều nhịp: class chat của Zalo có thể nạp muộn sau khi mở app.
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ZUScanAndHook(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(12 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ZUScanAndHook(); });
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(30 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ZUScanAndHook(); });
    }
}
