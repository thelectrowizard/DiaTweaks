#import "Patches/KeepLastTab/KeepLastTab.h"
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/CommandBarOverlay.h"


static const NSEventModifierFlags DPMods = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;

static BOOL DPIsCloseTab(NSEvent *event) {
    NSMenuItem *item = DPMenuItemTitled(NSApp.mainMenu, @"Close Tab");
    return item.keyEquivalent.length && (event.modifierFlags & DPMods) == item.keyEquivalentModifierMask
        && [event.charactersIgnoringModifiers caseInsensitiveCompare:item.keyEquivalent] == NSOrderedSame;
}

static BOOL DPIsPinned(id tab) {
    @try { return [[tab valueForKey:@"isPinned"] boolValue]; } @catch (NSException *e) { return NO; }
}

// A tab showing a page, the window's only one. A new tab page, or the blank one the command bar leaves, has no URL.
static id DPLastTabWithPage(NSWindow *window) {
    id scriptWindow = DPScriptWindow(window);
    NSArray *tabs = [scriptWindow valueForKey:@"appleScriptTabs"];
    id tab = tabs.count == 1 ? tabs.firstObject : nil;
    if (!tab || DPIsPinned(tab) || ![[[tab valueForKey:@"URL"] description] length]) return nil;
    return tab;
}

// Whether it replaced the window's last tab, leaving nothing for Dia to close.
static BOOL DPReplaceLastTab(NSWindow *window) {
    if (!DPKeepLastTab.on || !window || DPGet(window, &DPOverlayKey)) return NO;
    id closing = DPLastTabWithPage(window);
    NSMenuItem *newTab = closing ? DPMenuItemTitled(NSApp.mainMenu, @"New Tab") : nil;
    if (!newTab) return NO;
    // With the command bar on, the replacement is left blank, as when Dia replaces a closed last tab.
    if (DPCommandBar.on) DPExpectLastTabReplacement(window);
    [newTab.menu performActionForItemAtIndex:[newTab.menu indexOfItem:newTab]];
    DPShowSidebarWhileEmpty(window);
    // Close the old tab once the new one is in front, so the window never runs out of tabs.
    NSString *closingID = DPTabID(closing);
    __weak NSWindow *weak = window;
    dispatch_async(dispatch_get_main_queue(), ^{
        id scriptWindow = DPScriptWindow(weak);
        id tab = DPScriptTabIn(scriptWindow, closingID);
        if (tab && ![DPActiveTabIDIn(scriptWindow) isEqual:closingID]) [tab performSelector:@selector(close:) withObject:nil];
    });
    return YES;
}

// Dia runs ⌘W ahead of its menus, so the key is caught here, and Close Tab chosen from the menu below.
static NSEvent *DPKeepLastTabKey(NSEvent *event) {
    return DPIsCloseTab(event) && DPReplaceLastTab(event.window) ? nil : event;
}

static __weak id DPCloseTabTarget;
static SEL DPCloseTabAction;

@interface DPCloseTabRelay : NSObject
@end

@implementation DPCloseTabRelay
- (void)closeTab:(NSMenuItem *)sender {
    if (DPReplaceLastTab(NSApp.keyWindow)) return;
    [NSApp sendAction:DPCloseTabAction to:DPCloseTabTarget from:sender];
}
@end

static void DPInstallKeepLastTab(void) {
    DPInstallSidebarLock();
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) { return DPKeepLastTabKey(event); }];
    static DPCloseTabRelay *relay;
    DPOnLaunch(^{
        NSMenuItem *item = DPMenuItemTitled(NSApp.mainMenu, @"Close Tab");
        if (!item.action || [item.target isKindOfClass:DPCloseTabRelay.class]) return;
        relay = [DPCloseTabRelay new];
        DPCloseTabTarget = item.target;
        DPCloseTabAction = item.action;
        item.target = relay;
        item.action = @selector(closeTab:);
    });
}

static NSString *DPVerifyKeepLastTab(DPPatch *patch) {
    if (!patch->on) return nil;
    if (!DPMenuItemTitled(NSApp.mainMenu, @"Close Tab")) return @"Dia has no Close Tab menu item";
    if (!DPMenuItemTitled(NSApp.mainMenu, @"New Tab")) return @"Dia has no New Tab menu item";
    return nil;
}

DP_PATCH(DPKeepLastTab) {
    .key = @"keepLastTab",
    .order = 86,
    .title = @"Keep Window Open on Last Tab",
    .detail = @"Closing a window’s last tab leaves a new tab page instead of closing the window, and closing that closes the window. With Open New Tabs in Command Bar on, it leaves an empty page instead, like Arc and Zen. The sidebar stays open until you open a page.",
    .symbol = @"macwindow.badge.plus macwindow",
    .tint = @"systemPinkColor",
    .section = @"Tabs",
    .classes = DPClasses(DPDiaNewTabPage),
    .install = DPInstallKeepLastTab,
    .verify = DPVerifyKeepLastTab,
};
