//
//  GooglyPuffTests.m
//  GooglyPuffTests
//
//  Created by A Magical Unicorn on A Sunday Night.
//  Copyright (c) 2014 Derek Selander. All rights reserved.
//

#import <XCTest/XCTest.h>

const int64_t kDefaultTimeoutLengthInNanoSeconds = 10000000000; // 10 Seconds

@interface GooglyPuffNetworkIntegrationTests : XCTestCase
@end


@implementation GooglyPuffNetworkIntegrationTests

- (void)setUp
{
    [super setUp];
    // Put setup code here; it will be run once, before the first test case.
}

- (void)tearDown
{
    // Put teardown code here; it will be run once, after the last test case.
    [super tearDown];
}

- (void)testMikeAshImageURL
{
    [self downloadImageURLWithString:kLotsOfFacesURLString];
}

- (void)testMattThompsonImageURL
{
    [self downloadImageURLWithString:kSuccessKidURLString];
}

- (void)testAaronHillegassImageURL
{
    [self downloadImageURLWithString:kOverlyAttachedGirlfriendURLString];
}

- (void)downloadImageURLWithString:(NSString *)URLString
{
    // 1创建一个信号量。参数指定信号量的起始值。这个数字是你可以访问的信号量，不需要有人先去增加它的数量。（注意到增加信号量也被叫做发射信号量）。译者注：这里初始化为0，也就是说，有人想使用信号量必然会被阻塞，直到有人增加信号量。
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    
    NSURL *url = [NSURL URLWithString:URLString];
    __unused Photo *photo = [[Photo alloc]
                             initwithURL:url
                             withCompletionBlock:^(UIImage *image, NSError *error) {
                                 if (error) {
                                     XCTFail(@"%@ failed. %@", URLString, error);
                                 }
                                 
                                 // 2在 Completion Block 里你告诉信号量你不再需要资源了。这就会增加信号量的计数并告知其他想使用此资源的线程。
                                 dispatch_semaphore_signal(semaphore);
                             }];
    
    // 3
    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, kDefaultTimeoutLengthInNanoSeconds);
    if (dispatch_semaphore_wait(semaphore, timeoutTime)) {
        XCTFail(@"%@ timed out", URLString);
    }
}

@end
