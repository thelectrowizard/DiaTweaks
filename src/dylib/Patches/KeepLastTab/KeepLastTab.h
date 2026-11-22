#import "StdPatch/StdPatch.h"

extern DPPatch DPKeepLastTab;

// Sidebar.m: while a window is empty after closing its last tab, its sidebar stays open and its button is locked.
void DPShowSidebarWhileEmpty(NSWindow *window);
void DPInstallSidebarLock(void);
