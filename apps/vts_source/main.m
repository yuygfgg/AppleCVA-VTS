#import "app_delegate.h"

#import <AppKit/AppKit.h>
#import <Foundation/Foundation.h>

int main(int argc, const char *argv[]) {
    (void)argc;
    (void)argv;
    @autoreleasepool {
        NSApplication *application = [NSApplication sharedApplication];
        VTSAppDelegate *delegate = [[VTSAppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
