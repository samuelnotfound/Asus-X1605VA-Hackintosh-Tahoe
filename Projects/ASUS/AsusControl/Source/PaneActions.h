#import <AppKit/AppKit.h>
@protocol AsusPaneActions <NSObject>
- (void)changeSetting:(NSString *)key value:(id)value;
- (void)retrySettings;
- (void)setTouchpadEnabled:(BOOL)enabled;
@end
