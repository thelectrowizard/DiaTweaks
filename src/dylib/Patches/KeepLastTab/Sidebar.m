#import "Patches/KeepLastTab/KeepLastTab.h"
#import <QuartzCore/QuartzCore.h>
#import "Patches/CommandBar/Tabs.h"
#import "Patches/CommandBar/CommandBarOverlay.h"

#define DPDiaHoverableControl "_TtC5ARCUI16HoverableControl"

// Windows left empty by closing their last tab, with whether the sidebar was open before: the sidebar stays open
// while they're empty, its button can't close it, and once a tab has a page again it goes back to how it was.
static NSMapTable<NSWindow *, NSArray *> *DPEmptyWindows;  // [was open, when it emptied]
static NSTimer *DPEmptyWatch;
static char DPLockedKey;

static NSView *DPSidebarButton(NSWindow *window) {
    return DPFindView(window.contentView.superview, ^BOOL(NSView *view) { return DPHasLabel(view, @"Toggle sidebar"); });
}

static BOOL DPSidebarOpen(NSWindow *window) {
    NSView *header = DPFindView(window.contentView, ^BOOL(NSView *view) { return DPIsKind(view, DPDiaSidebarHeader); });
    return header && !header.isHiddenOrHasHiddenAncestor && NSMinX([header convertRect:header.bounds toView:nil]) >= 0;
}

static void DPLockButton(NSWindow *window, BOOL locked) {
    NSControl *button = (NSControl *)DPSidebarButton(window);
    if (!button) return;
    DPSet(button, &DPLockedKey, locked ? @YES : nil);
    if ([button respondsToSelector:@selector(setEnabled:)]) button.enabled = !locked;
    button.alphaValue = locked ? 0.3 : 1;
    button.toolTip = locked ? @"The sidebar stays open while the window has no tabs" : nil;
}

static void DPPressSidebarButton(NSWindow *window) {
    NSView *button = DPSidebarButton(window);
    id locked = DPGet(button, &DPLockedKey);
    DPSet(button, &DPLockedKey, nil);
    [button accessibilityPerformPress];
    DPSet(button, &DPLockedKey, locked);
}

static BOOL DPStillEmpty(NSWindow *window) {
    NSArray *tabs = [DPScriptWindow(window) valueForKey:@"appleScriptTabs"];
    return window.isVisible && tabs.count == 1 && ![[[tabs.firstObject valueForKey:@"URL"] description] length];
}

static void DPLeaveEmpty(NSWindow *window) {
    BOOL wasOpen = [[DPEmptyWindows objectForKey:window].firstObject boolValue];
    [DPEmptyWindows removeObjectForKey:window];
    DPLockButton(window, NO);
    if (!wasOpen && DPSidebarOpen(window)) DPPressSidebarButton(window);
}

static void DPCheckEmptyWindows(void) {
    for (NSWindow *window in DPEmptyWindows.keyEnumerator.allObjects) {
        // The closing tab takes a moment to go, so for the first second a second tab doesn't count.
        BOOL settling = CACurrentMediaTime() - [[DPEmptyWindows objectForKey:window].lastObject doubleValue] < 1;
        if (!DPKeepLastTab.on || !window.isVisible || (!settling && !DPStillEmpty(window))) DPLeaveEmpty(window);
        else if (!DPHasStrip(window)) {
            if (!DPSidebarOpen(window)) DPPressSidebarButton(window);
            DPLockButton(window, YES);  // Dia rebuilds the toolbar as it relays out, so this is reapplied.
        }
    }
    if (!DPEmptyWindows.count) {
        [DPEmptyWatch invalidate];
        DPEmptyWatch = nil;
    }
}

void DPShowSidebarWhileEmpty(NSWindow *window) {
    if (!window || DPHasStrip(window)) return;
    DPEmptyWindows = DPEmptyWindows ?: [NSMapTable weakToStrongObjectsMapTable];
    if (![DPEmptyWindows objectForKey:window]) [DPEmptyWindows setObject:@[ @(DPSidebarOpen(window)), @(CACurrentMediaTime()) ] forKey:window];
    if (!DPEmptyWatch) DPEmptyWatch = [NSTimer scheduledTimerWithTimeInterval:0.25 repeats:YES block:^(NSTimer *timer) { DPCheckEmptyWindows(); }];
}

BOOL DPSidebarLocked(NSWindow *window) { return [DPEmptyWindows objectForKey:window] != nil && DPKeepLastTab.on; }

// Clicks, presses and ⌘S on a locked button do nothing.
static void DPControl_mouseDown(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPGet(self, &DPLockedKey)) DPCallOriginal(DPControl_mouseDown, self, event);
}

static void DPControl_mouseUp(NSView *self, SEL _cmd, NSEvent *event) {
    if (!DPGet(self, &DPLockedKey)) DPCallOriginal(DPControl_mouseUp, self, event);
}

static BOOL DPControl_press(NSView *self, SEL _cmd) {
    return DPGet(self, &DPLockedKey) ? NO : DPCallOriginal(DPControl_press, self);
}

static BOOL DPIsSidebarShortcut(NSEvent *event) {
    NSMenuItem *item = DPMenuItemTitled(NSApp.mainMenu, @"Auto-Hide Tabs");
    NSEventModifierFlags mods = NSEventModifierFlagCommand | NSEventModifierFlagShift | NSEventModifierFlagOption | NSEventModifierFlagControl;
    return item.keyEquivalent.length && (event.modifierFlags & mods) == item.keyEquivalentModifierMask
        && [event.charactersIgnoringModifiers caseInsensitiveCompare:item.keyEquivalent] == NSOrderedSame;
}

void DPInstallSidebarLock(void) {
    DPHook(DPDiaHoverableControl, @selector(mouseDown:), (IMP)DPControl_mouseDown);
    DPHook(DPDiaHoverableControl, @selector(mouseUp:), (IMP)DPControl_mouseUp);
    DPHook(DPDiaHoverableControl, @selector(accessibilityPerformPress), (IMP)DPControl_press);
    [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
        return DPSidebarLocked(event.window) && DPIsSidebarShortcut(event) ? nil : event;
    }];
}
