//
//  ARCViewController.m
//  eventtracker-ios
//
//

#import "ARCViewController.h"
#import "EventTracker.h"

@interface ARCViewController ()
@property (weak, nonatomic) IBOutlet UITextField *numberOfEvents;

@end

@implementation ARCViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
	

}

-(IBAction)logEvents:(id)sender {
    
    
    int num = [self.numberOfEvents.text intValue];
    
    for (int i = 0; i < num; i++) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            NSLog(@"track event %d",i);
            [self trackEvent];
        });
    }
}

-(void)trackEvent
{
    // call new Arclight EventTracker service
    [EventTracker trackPlayEventWithRefID:@"777"
                             apiSessionID:@"111222333"
                                streaming:YES
                   mediaViewTimeInSeconds:10.0
             mediaEngagementOver75Percent:YES];
    
    
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
