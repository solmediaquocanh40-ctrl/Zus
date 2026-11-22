TARGET := iphone:clang:latest:15.0

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ZaloUnseen
ZaloUnseen_FILES = Tweak.x
ZaloUnseen_FRAMEWORKS = UIKit Foundation
ZaloUnseen_LIBRARIES = substrate
ZaloUnseen_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/tweak.mk
