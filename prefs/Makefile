TARGET := iphone:clang:latest:15.0
ARCHS := arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ZaloUnseenPrefs
ZaloUnseenPrefs_FILES = ZURootListController.m
ZaloUnseenPrefs_INSTALL_PATH = /Library/PreferenceBundles
ZaloUnseenPrefs_FRAMEWORKS = UIKit
ZaloUnseenPrefs_CFLAGS = -fobjc-arc
ZaloUnseenPrefs_LDFLAGS = -undefined dynamic_lookup

include $(THEOS_MAKE_PATH)/bundle.mk
