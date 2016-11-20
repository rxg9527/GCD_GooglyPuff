//  PhotoManager.m
//  PhotoFilter
//
//  Created by A Magical Unicorn on A Sunday Night.
//  Copyright (c) 2014 Derek Selander. All rights reserved.
//

@import CoreImage;
@import AssetsLibrary;
#import "PhotoManager.h"

@interface PhotoManager ()
@property (nonatomic, strong) NSMutableArray *photosArray;
@property (nonatomic, strong) dispatch_queue_t concurrentPhotoQueue;
@end

@implementation PhotoManager

+ (instancetype)sharedManager
{
    /**
     https://github.com/nixzhu/dev-blog/blob/master/2014-04-19-grand-central-dispatch-in-depth-part-1.md
     if 条件分支不是线程安全的；如果你多次调用这个方法，有一个可能性是在某个线程（就叫它线程A）上进入 if 语句块并可能在 sharedPhotoManager 被分配内存前发生一个上下文切换。然后另一个线程（线程B）可能进入 if ，分配单例实例的内存，然后退出。
     Context Switch 上下文切换（单核设备使用并发操作的实质-『伪并行』）
     
     一个上下文切换指当你在单个进程里切换执行不同的线程时存储与恢复执行状态的过程。这个过程在编写多任务应用时很普遍，但会带来一些额外的开销。
     */
    static PhotoManager *sharedPhotoManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPhotoManager = [[PhotoManager alloc] init];
        sharedPhotoManager->_photosArray = [NSMutableArray array];
        
        sharedPhotoManager->_concurrentPhotoQueue = dispatch_queue_create("com.selander.GooglyPuff.photoQueue", DISPATCH_QUEUE_CONCURRENT);
    });
    return sharedPhotoManager;
}

//*****************************************************************************/
#pragma mark - Unsafe Setter/Getters
//*****************************************************************************/

/*
 读方法，它读取可变数组。它为调用者生成一个不可变的拷贝，防止调用者不当地改变数组，但这不能提供任何保护来对抗当一个线程调用读方法 photos 的同时另一个线程调用写方法 addPhoto:
 */
- (NSArray *)photos
{
    __block NSArray *array;
    dispatch_sync(self.concurrentPhotoQueue, ^{ // 在 concurrentPhotoQueue 上同步调度来执行读操作。
        array = [NSArray arrayWithArray:_photosArray]; 
    });
    return array;
}

/*
 许多线程可以同时读取 NSMutableArray 的一个实例而不会产生问题，但当一个线程正在读取时让另外一个线程修改数组就是不安全的。
 */
- (void)addPhoto:(Photo *)photo
{
    /*
     if (photo) {
     [_photosArray addObject:photo];
     dispatch_async(dispatch_get_main_queue(), ^{
     [self postContentAddedNotification];
     });
     }
     */
    if (photo) { // 在执行下面所有的工作前检查是否有合法的相片。
        dispatch_barrier_async(self.concurrentPhotoQueue, ^{ // 添加写操作到你的自定义队列。当临界区在稍后执行时，这将是你队列中唯一执行的条目。
            [_photosArray addObject:photo]; // 这是添加对象到数组的实际代码。由于它是一个障碍 Block ，这个 Block 永远不会同时和其它 Block 一起在 concurrentPhotoQueue 中执行。
            dispatch_async(dispatch_get_main_queue(), ^{ // 最后你发送一个通知说明完成了添加图片。这个通知将在主线程被发送因为它将会做一些 UI 工作，所以在此为了通知，你异步地调度另一个任务到主线程。
                [self postContentAddedNotification];
            });
        });
    }
}

//*****************************************************************************/
#pragma mark - Public Methods
//*****************************************************************************/
/*
 dispatch_group_notify 以异步的方式工作。当 Dispatch Group 中没有任何任务时，它就会执行其代码，那么 completionBlock 便会运行。你还指定了运行 completionBlock 的队列，此处，主队列就是你所需要的。
 */
- (void)downloadPhotosWithCompletionBlock:(BatchPhotoDownloadingCompletionBlock)completionBlock
{
    __block NSError *error;
    dispatch_group_t downloadGroup = dispatch_group_create();
    
    for (NSInteger i = 0; i < 3; i++) {
        NSURL *url;
        switch (i) {
            case 0:
                url = [NSURL URLWithString:kOverlyAttachedGirlfriendURLString];
                break;
            case 1:
                url = [NSURL URLWithString:kSuccessKidURLString];
                break;
            case 2:
                url = [NSURL URLWithString:kLotsOfFacesURLString];
                break;
            default:
                break;
        }
        
        dispatch_group_enter(downloadGroup); // 2
        Photo *photo = [[Photo alloc] initwithURL:url
                              withCompletionBlock:^(UIImage *image, NSError *_error) {
                                  if (_error) {
                                      error = _error;
                                  }
                                  dispatch_group_leave(downloadGroup); // 3
                              }];
        
        [[PhotoManager sharedManager] addPhoto:photo];
    }
    
    dispatch_group_notify(downloadGroup, dispatch_get_main_queue(), ^{ // 4
        if (completionBlock) {
            completionBlock(error);
        }
    });
}

//*****************************************************************************/
#pragma mark - Private Methods
//*****************************************************************************/

- (void)postContentAddedNotification
{
    static NSNotification *notification = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        notification = [NSNotification notificationWithName:kPhotoManagerAddedContentNotification object:nil];
    });
    
    [[NSNotificationQueue defaultQueue] enqueueNotification:notification postingStyle:NSPostASAP coalesceMask:NSNotificationCoalescingOnName forModes:nil];
}

@end
