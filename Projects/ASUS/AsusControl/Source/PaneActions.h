#import <AppKit/AppKit.h>
@protocol AsusPaneActions <NSObject>
- (void)changeSetting:(NSString *)key value:(id)value;
- (void)selectProfileMode:(NSInteger)mode;
- (void)retrySettings;
- (void)setTouchpadEnabled:(BOOL)enabled;
- (void)openSystemTool:(NSString *)tool;
@end
