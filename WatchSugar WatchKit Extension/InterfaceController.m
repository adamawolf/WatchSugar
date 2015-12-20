//
//  InterfaceController.m
//  WatchSugar WatchKit Extension
//
//  Created by Adam A. Wolf on 12/14/15.
//  Copyright © 2015 Flairify. All rights reserved.
//

#import "InterfaceController.h"
#import "ExtensionDelegate.h"

@interface InterfaceController()

@end


@implementation InterfaceController

- (void)awakeWithContext:(id)context {
    [super awakeWithContext:context];

    NSLog(@"watch awakeWithContext");
}

- (void)willActivate
{
    [super willActivate];
    
    [self updateDisplay];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(handleBloodSugarDataChanged:) name:WSNotificationBloodSugarDataChanged object:nil];
}

- (void)didDeactivate
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    [super didDeactivate];
}

- (void)updateDisplay
{
    ExtensionDelegate *extensionDelegate = (ExtensionDelegate *)[WKExtension sharedExtension].delegate;
    
    if (extensionDelegate.bloodSugarValues.count) {
        NSDictionary *mostRecent = extensionDelegate.bloodSugarValues[0];
        
        int mostRecentValue = [mostRecent[@"value"] intValue];
        self.bloodSugarLabel.text = [NSString stringWithFormat:@"%d", mostRecentValue];
        
        NSTimeInterval epoch = [mostRecent[@"timestamp"] doubleValue] / 1000.00; //dexcom dates include milliseconds
        NSString *agoString = [InterfaceController humanHourMinuteSecondStringFromTimeInterval:[[NSDate date] timeIntervalSince1970] - epoch];
        self.agoLabel.text = [NSString stringWithFormat:@"%@ ago", agoString];
        
        self.trendLabel.text = [NSString stringWithFormat:@"Trend %d", [mostRecent[@"trend"] intValue]];
    } else {
        self.bloodSugarLabel.text = @"--";
        self.agoLabel.text = @"";
        self.trendLabel.text = @"";
    }
}

#pragma mark - Notification handler methods

- (void)handleBloodSugarDataChanged:(NSNotification *)notification
{
    [self updateDisplay];
}

//TODO DRY
+ (NSString *) humanHourMinuteSecondStringFromTimeInterval: (NSTimeInterval) timeInterval;
{
    NSString * ret = nil;
    
    if (timeInterval < 60)
    {
        ret = [NSString stringWithFormat:@"%ds", (int)timeInterval];
    }
    else if (timeInterval < 60 * 60)
    {
        NSInteger minutes = (NSInteger)(timeInterval / 60);
        timeInterval -= minutes * 60;
        NSInteger seconds = (NSInteger)(timeInterval);
        ret = [NSString stringWithFormat:@"%dm", (int)minutes];
        if (seconds)
        {
            ret = [NSString stringWithFormat:@"%@ %ds", ret, (int)seconds];
        }
    }
    else if (timeInterval < 60 * 60 * 24)
    {
        NSInteger hours = (NSInteger)(timeInterval / (60 * 60));
        ret = [NSString stringWithFormat:@"%dh", (int)hours];
        timeInterval -= hours * 60 * 60;
        NSInteger minutes = (NSInteger)(timeInterval / 60);
        if (minutes)
        {
            ret = [NSString stringWithFormat:@"%@%dm", ret, (int)minutes];
        }
    }
    else
    {
        NSInteger days = (NSInteger)(timeInterval / (24 * 60 * 60));
        ret = [NSString stringWithFormat:@"%dd", (int)days];
        timeInterval -= days * 24 * 60 * 60;
        NSInteger hours = (NSInteger)(timeInterval / (60 * 60));
        if (hours)
        {
            ret = [NSString stringWithFormat:@"%@%dh", ret, (int)hours];
        }
    }
    
    return ret;
}

@end
