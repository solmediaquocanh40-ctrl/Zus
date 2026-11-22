// ZUShared.h — hằng dùng chung cho tweak (chích vào Zalo) và gói Cài đặt.
// Hai bản giống hệt nhau nằm ở tweak/ và prefs/.
#ifndef ZU_SHARED_H
#define ZU_SHARED_H

#define ZU_DOMAIN @"com.anhdang.zalounseen"
// Tên thông báo Darwin ở dạng CFString sẵn (CFSTR) — KHÔNG để chuỗi C rồi __bridge
// sang CFStringRef: bản 1.0.0 build đầu chết đúng lỗi đó, còn làm clang sập.
#define ZU_NOTIFY CFSTR("com.anhdang.zalounseen/prefsChanged")

// Khoá cài đặt (khớp Root.plist)
#define ZU_KEY_ENABLED @"enabled"
#define ZU_KEY_UNSEEN  @"unseen"
#define ZU_KEY_TYPING  @"hideTyping"
#define ZU_KEY_DEBUG   @"debug"

// Khoá chẩn đoán: tweak ghi, trang Cài đặt đọc để hiện trạng thái dò.
#define ZU_DIAG_CANDIDATES   @"diag_candidates"
#define ZU_DIAG_HOOKED       @"diag_hooked"
#define ZU_DIAG_SKIPPED      @"diag_skipped"
#define ZU_DIAG_BLOCKED_READ @"diag_blockedRead"
#define ZU_DIAG_BLOCKED_TYPE @"diag_blockedTyping"
#define ZU_DIAG_LAST         @"diag_lastEvent"
#define ZU_DIAG_SCAN         @"diag_lastScan"
#define ZU_DIAG_CTOR         @"diag_ctor"

#endif
