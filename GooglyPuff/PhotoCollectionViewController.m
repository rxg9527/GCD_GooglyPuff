//
//  PhotoCollectionViewController.m
//  GCDTutorial
//
//  Created by A Magical Unicorn on A Sunday Night.
//  Copyright (c) 2014 Derek Selander. All rights reserved.
//

@import AssetsLibrary;
#import "PhotoCollectionViewController.h"
#import "PhotoDetailViewController.h"
#import "ELCImagePickerController.h"

static const NSInteger kCellImageViewTag = 3;
static const CGFloat kBackgroundImageOpacity = 0.1f;

@interface PhotoCollectionViewController () <ELCImagePickerControllerDelegate,
UINavigationControllerDelegate,
UICollectionViewDataSource,
UIActionSheetDelegate>

@property (nonatomic, strong) ALAssetsLibrary *library;
@property (nonatomic, strong) UIPopoverController *popController;
@end

@implementation PhotoCollectionViewController

//*****************************************************************************/
#pragma mark - LifeCycle
//*****************************************************************************/

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    // 最好是在 DEBUG 模式下编译这些代码，因为这会给“有关方面（Interested Parties）”很多关于你应用的洞察
#if DEBUG
    // Just to mix things up，你创建了一个 dispatch_queue_t 实例变量而不是在参数上直接使用函数。当代码变长，分拆有助于可读性。
    dispatch_queue_t queue = dispatch_get_main_queue();
    
    // 你需要 source 在方法范围之外也可被访问，所以你使用了一个 static 变量
    static dispatch_source_t source = nil;
    
    // 使用 weakSelf 以确保不会出现保留环（Retain Cycle）
    __typeof(self) __weak weakSelf = self;
    
    // 确保只会执行一次 Dispatch Source 的设置
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 初始化 source 变量。你指明了你对信号监控感兴趣并提供了 SIGSTOP 信号作为第二个参数。进一步，你使用主队列处理接收到的事件——很快你就好发现为何要这样做
        source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGSTOP, 0, queue);
        
        // 如果你提供的参数不合格，那么 Dispatch Source 对象不会被创建。也就是说，在你开始在其上工作之前，你需要确保已有了一个有效的 Dispatch Source
        if (source)
        {
            // 当你收到你所监控的信号时，dispatch_source_set_event_handler 就会执行。之后你可以在其 Block 里设置合适的逻辑处理器（Logic Handler）
            dispatch_source_set_event_handler(source, ^{
                // 一个基本的 NSLog 语句，它将对象打印到控制台
                NSLog(@"Hi, I am: %@", weakSelf);
            });
            dispatch_resume(source); // 默认的，所有源都初始为暂停状态。如果你要开始监控事件，你必须告诉源对象恢复活跃状态。
        }
    });
#endif

    self.library = [[ALAssetsLibrary alloc] init];
    
    // Background image setup
    UIImageView *backgroundImageView = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"background"]];
    backgroundImageView.alpha = kBackgroundImageOpacity;
    backgroundImageView.contentMode = UIViewContentModeCenter;
    [self.collectionView setBackgroundView:backgroundImageView];
   
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentChangedNotification:)
                                                 name:kPhotoManagerContentUpdateNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(contentChangedNotification:) name:kPhotoManagerAddedContentNotification object:nil];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self showOrHideNavPrompt];
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

//*****************************************************************************/
#pragma mark - UICollectionViewDataSource Methods
//*****************************************************************************/

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section
{
    NSInteger count = [[[PhotoManager sharedManager] photos] count];
    return count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *cellIdentifier = @"photoCell";
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:cellIdentifier forIndexPath:indexPath];
    
    UIImageView *imageView = (UIImageView *)[cell viewWithTag:kCellImageViewTag];
    NSArray *photoAssets = [[PhotoManager sharedManager] photos];
    Photo *photo = photoAssets[indexPath.row];
    
    switch (photo.status) {
        case PhotoStatusGoodToGo:
            imageView.image = [photo thumbnail];
            break;
        case PhotoStatusDownloading:
            imageView.image = [UIImage imageNamed:@"photoDownloading"];
            break;
        case PhotoStatusFailed:
            imageView.image = [UIImage imageNamed:@"photoDownloadError"];
        default:
            break;
    }
    return cell;
}

//*****************************************************************************/
#pragma mark - UICollectionViewDelegate
//*****************************************************************************/

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath
{
    NSArray *photos = [[PhotoManager sharedManager] photos];
    Photo *photo = photos[indexPath.row];
    
    switch (photo.status) {
        case PhotoStatusGoodToGo: {
            UIImage *image = [photo image];
            PhotoDetailViewController *photoDetailViewController = [self.storyboard instantiateViewControllerWithIdentifier:@"PhotoDetailViewController"];
            [photoDetailViewController setupWithImage:image];
            [self.navigationController pushViewController:photoDetailViewController animated:YES];
            break;
        }
        case PhotoStatusDownloading: {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Downloading"
                                                            message:@"The image is currently downloading"
                                                           delegate:nil
                                                  cancelButtonTitle:@"Ok"
                                                  otherButtonTitles:nil, nil];
            [alert show];
            break;
        }
        case PhotoStatusFailed: //Fall through to default
        default: {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Image Failed"
                                                            message:@"The image failed to be created"
                                                           delegate:nil
                                                  cancelButtonTitle:@"Ok"
                                                  otherButtonTitles:nil, nil];
            [alert show];
        }
    }
}

//*****************************************************************************/
#pragma mark - elcImagePickerControllerDelegate
//*****************************************************************************/

- (void)elcImagePickerController:(ELCImagePickerController *)picker didFinishPickingMediaWithInfo:(NSArray *)info
{
    for (NSDictionary *dictionary in info) {
        [self.library assetForURL:dictionary[UIImagePickerControllerReferenceURL] resultBlock:^(ALAsset *asset) {
            Photo *photo = [[Photo alloc] initWithAsset:asset];
            [[PhotoManager sharedManager] addPhoto:photo];
        } failureBlock:^(NSError *error) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Permission Denied"
                                                            message:@"To access your photos, please change the permissions in Settings"
                                                           delegate:nil
                                                  cancelButtonTitle:@"ok"
                                                  otherButtonTitles:nil, nil];
            [alert show];
        }];
    }
    
    if (isIpad()) {
        [self.popController dismissPopoverAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

- (void)elcImagePickerControllerDidCancel:(ELCImagePickerController *)picker
{
    if (isIpad()) {
        [self.popController dismissPopoverAnimated:YES];
    } else {
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

//*****************************************************************************/
#pragma mark - IBAction Methods
//*****************************************************************************/

/// The upper right UIBarButtonItem method
- (IBAction)addPhotoAssets:(id)sender
{
    UIActionSheet *actionSheet = [[UIActionSheet alloc] initWithTitle:@"Get Photos From:" delegate:self cancelButtonTitle:@"Cancel" destructiveButtonTitle:nil otherButtonTitles:@"Photo Library", @"Le Internet", nil];
    [actionSheet showInView:self.view];
}

//*****************************************************************************/
#pragma mark - UIActionSheetDelegate
//*****************************************************************************/

- (void)actionSheet:(UIActionSheet *)actionSheet clickedButtonAtIndex:(NSInteger)buttonIndex
{
    static const NSInteger kButtonIndexPhotoLibrary = 0;
    static const NSInteger kButtonIndexInternet = 1;
    if (buttonIndex == kButtonIndexPhotoLibrary) {
        ELCImagePickerController *imagePickerController = [[ELCImagePickerController alloc] init];
        [imagePickerController setImagePickerDelegate:self];
        
        if (isIpad()) {
            if (![self.popController isPopoverVisible]) {
                self.popController = [[UIPopoverController alloc] initWithContentViewController:imagePickerController];
                
                [self.popController presentPopoverFromBarButtonItem:self.navigationItem.rightBarButtonItem permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
            }
        } else {
            [self presentViewController:imagePickerController animated:YES completion:nil];
        }
    } else if (buttonIndex == kButtonIndexInternet) {
        [self downloadImageAssets];
    }
}

//*****************************************************************************/
#pragma mark - Private Methods
//*****************************************************************************/

- (void)contentChangedNotification:(NSNotification *)notification
{
    [self.collectionView reloadData];
    [self showOrHideNavPrompt];
}

- (void)showOrHideNavPrompt
{
    NSUInteger count = [[PhotoManager sharedManager] photos].count;
    double delayInSeconds = 1.0;
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delayInSeconds * NSEC_PER_SEC)); // 1
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){ // 2
        if (!count) {
            [self.navigationItem setPrompt:@"Add photos with faces to Googlyify them!"];
        } else {
            [self.navigationItem setPrompt:nil];
        }
    });
}

- (void)downloadImageAssets
{
    [[PhotoManager sharedManager] downloadPhotosWithCompletionBlock:^(NSError *error) {
        
        // This completion block currently executes at the wrong time
        NSString *message = error ? [error localizedDescription] : @"The images have finished downloading";
        UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:@"Download Complete"
                                                            message:message
                                                           delegate:nil
                                                  cancelButtonTitle:@"Ok"
                                                  otherButtonTitles:nil, nil];
        [alertView show];
    }];
}

@end
