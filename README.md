# GCD 深入理解

Ray Wenderlich 的GCD深入理解系列，文章译者 @nixzhu。这是示例工程，可以看 Git History。

本译文转自[nixzhu的GitHub](https://github.com/nixzhu/dev-blog/blob/master/2014-04-19-grand-central-dispatch-in-depth-part-1.md)

翻译自 [http://www.raywenderlich.com/60749/grand-central-dispatch-in-depth-part-1](http://www.raywenderlich.com/60749/grand-central-dispatch-in-depth-part-1)

原作者：[Derek Selander](http://www.raywenderlich.com/u/Lolgrep)

译者：[@nixzhu](https://twitter.com/nixzhu)

==========================================

虽然 GCD 已经出现过一段时间了，但不是每个人都明了其主要内容。这是可以理解的；并发一直很棘手，而 GCD 是基于 C 的 API ，它们就像一组尖锐的棱角戳进 Objective-C 的平滑世界。我们将分两个部分的教程来深入学习 GCD 。

在这两部分的系列中，第一个部分的将解释 GCD 是做什么的，并从许多基本的 GCD 函数中找出几个来展示。在[第二部分](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md)，你将学到几个 GCD 提供的高级函数。

## 什么是 GCD

GCD 是 `libdispatch` 的市场名称，而 libdispatch 作为 Apple 的一个库，为并发代码在多核硬件（跑 iOS 或 OS X ）上执行提供有力支持。它具有以下优点：

- GCD 能通过推迟昂贵计算任务并在后台运行它们来改善你的应用的响应性能。
- GCD 提供一个易于使用的并发模型而不仅仅只是锁和线程，以帮助我们避开并发陷阱。
- GCD 具有在常见模式（例如单例）上用更高性能的原语优化你的代码的潜在能力。

本教程假设你对 Block 和 GCD 有基础了解。如果你对 GCD 完全陌生，先看看 [iOS 上的多线程和 GCD 入门教程](http://www.raywenderlich.com/4295/multithreading-and-grand-central-dispatch-on-ios-for-beginners-tutorial) 学习其要领。

## GCD 术语

要理解 GCD ，你要先熟悉与线程和并发相关的几个概念。这两者都可能模糊和微妙，所以在开始 GCD 之前先简要地回顾一下它们。

#### Serial vs. Concurrent 串行 vs. 并发

这些术语描述当任务相对于其它任务被执行，任务串行执行就是每次只有一个任务被执行，任务并发执行就是在同一时间可以有多个任务被执行。

虽然这些术语被广泛使用，本教程中你可以将任务设定为一个 Objective-C 的 Block 。不明白什么是 Block ？看看 [iOS 5 教程中的如何使用 Block](http://www.raywenderlich.com/9328/creating-a-diner-app-using-blocks-part-1) 。实际上，你也可以在 GCD 上使用函数指针，但在大多数场景中，这实际上更难于使用。Block 就是更加容易些！

#### Synchronous vs. Asynchronous 同步 vs. 异步

在 GCD 中，这些术语描述当一个函数相对于另一个任务完成，此任务是该函数要求 GCD 执行的。一个_同步_函数只在完成了它预定的任务后才返回。

一个_异步_函数，刚好相反，会立即返回，预定的任务会完成但不会等它完成。因此，一个异步函数不会阻塞当前线程去执行下一个函数。

注意——当你读到同步函数“阻塞（Block）”当前线程，或函数是一个“阻塞”函数或阻塞操作时，不要被搞糊涂了！动词“阻塞”描述了函数如何影响它所在的线程而与名词“代码块（Block）”没有关系。代码块描述了用 Objective-C 编写的一个匿名函数，它能定义一个任务并被提交到 GCD 。

译者注：中文不会有这个问题，“阻塞”和“代码块”是两个词。

#### Critical Section 临界区

就是一段代码不能被并发执行，也就是，两个线程不能同时执行这段代码。这很常见，因为代码去操作一个共享资源，例如一个变量若能被并发进程访问，那么它很可能会变质（译者注：它的值不再可信）。

#### Race Condition 竞态条件

这种状况是指基于特定序列或时机的事件的软件系统以不受控制的方式运行的行为，例如程序的并发任务执行的确切顺序。竞态条件可导致无法预测的行为，而不能通过代码检查立即发现。

#### Deadlock 死锁

两个（有时更多）东西——在大多数情况下，是线程——所谓的死锁是指它们都卡住了，并等待对方完成或执行其它操作。第一个不能完成是因为它在等待第二个的完成。但第二个也不能完成，因为它在等待第一个的完成。

#### Thread Safe 线程安全

线程安全的代码能在多线程或并发任务中被安全的调用，而不会导致任何问题（数据损坏，崩溃，等）。线程不安全的代码在某个时刻只能在一个上下文中运行。一个线程安全代码的例子是 `NSDictionary` 。你可以在同一时间在多个线程中使用它而不会有问题。另一方面，`NSMutableDictionary` 就不是线程安全的，应该保证一次只能有一个线程访问它。

#### Context Switch 上下文切换

一个上下文切换指当你在单个进程里切换执行不同的线程时存储与恢复执行状态的过程。这个过程在编写多任务应用时很普遍，但会带来一些额外的开销。

### Concurrency vs Parallelism 并发与并行

并发和并行通常被一起提到，所以值得花些时间解释它们之间的区别。

并发代码的不同部分可以“同步”执行。然而，该怎样发生或是否发生都取决于系统。多核设备通过并行来同时执行多个线程；然而，为了使单核设备也能实现这一点，它们必须先运行一个线程，执行一个上下文切换，然后运行另一个线程或进程。这通常发生地足够快以致给我们并发执行地错觉，如下图所示：

![Concurrency_vs_Parallelism](http://cdn1.raywenderlich.com/wp-content/uploads/2014/01/Concurrency_vs_Parallelism.png)

虽然你可以编写代码在 GCD 下并发执行，但 GCD 会决定有多少并行的需求。并行_要求_并发，但并发并不能_保证_并行。

更深入的观点是并发实际上是关于_构造_。当你在脑海中用 GCD 编写代码，你组织你的代码来暴露能同时运行的多个工作片段，以及不能同时运行的那些。如果你想深入此主题，看看 [这个由Rob Pike做的精彩的讲座](http://vimeo.com/49718712) 。

### Queues 队列

GCD 提供有 `dispatch queues` 来处理代码块，这些队列管理你提供给 GCD 的任务并用 FIFO 顺序执行这些任务。这就保证了第一个被添加到队列里的任务会是队列中第一个开始的任务，而第二个被添加的任务将第二个开始，如此直到队列的终点。

所有的调度队列（dispatch queues）自身都是线程安全的，你能从多个线程并行的访问它们。当你了解了调度队列如何为你自己代码的不同部分提供线程安全后，GCD的优点就是显而易见的。关于这一点的关键是选择正确_类型_的调度队列和正确的_调度函数_来提交你的工作。

在本节你会看到两种调度队列，都是由 GCD 提供的，然后看一些描述如何用调度函数添加工作到队列的例子。

#### Serial Queues 串行队列

串行队列中的任务一次执行一个，每个任务只在前一个任务完成时才开始。而且，你不知道在一个 Block 结束和下一个开始之间的时间长度，如下图所示：

![Serial-Queue](http://cdn4.raywenderlich.com/wp-content/uploads/2014/01/Serial-Queue-480x272.png)

这些任务的执行时机受到 GCD 的控制；唯一能确保的事情是 GCD 一次只执行一个任务，并且按照我们添加到队列的顺序来执行。

由于在串行队列中不会有两个任务并发运行，因此不会出现同时访问临界区的风险；相对于这些任务来说，这就从竞态条件下保护了临界区。所以如果访问临界区的唯一方式是通过提交到调度队列的任务，那么你就不需要担心临界区的安全问题了。

#### Concurrent Queues 并发队列

在并发队列中的任务能得到的保证是它们会按照被添加的顺序开始执行，但这就是全部的保证了。任务可能以任意顺序完成，你不会知道何时开始运行下一个任务，或者任意时刻有多少 Block 在运行。再说一遍，这完全取决于 GCD 。

下图展示了一个示例任务执行计划，GCD 管理着四个并发任务：

![Concurrent-Queue](http://cdn3.raywenderlich.com/wp-content/uploads/2014/01/Concurrent-Queue-480x272.png)

注意 Block 1,2 和 3 都立马开始运行，一个接一个。在 Block 0 开始后，Block 1等待了好一会儿才开始。同样， Block 3 在 Block 2 之后才开始，但它先于 Block 2 完成。

何时开始一个 Block 完全取决于 GCD 。如果一个 Block 的执行时间与另一个重叠，也是由 GCD 来决定是否将其运行在另一个不同的核心上，如果那个核心可用，否则就用上下文切换的方式来执行不同的 Block 。

有趣的是， GCD 提供给你至少五个特定的队列，可根据队列类型选择使用。

#### Queue Types 队列类型

首先，系统提供给你一个叫做 `主队列（main queue）` 的特殊队列。和其它串行队列一样，这个队列中的任务一次只能执行一个。然而，它能保证所有的任务都在主线程执行，而主线程是唯一可用于更新 UI 的线程。这个队列就是用于发生消息给 `UIView` 或发送通知的。

系统同时提供给你好几个并发队列。它们叫做 `全局调度队列（Global Dispatch Queues）` 。目前的四个全局队列有着不同的优先级：`background`、`low`、`default` 以及 `high`。要知道，Apple 的 API 也会使用这些队列，所以你添加的任何任务都不会是这些队列中唯一的任务。

最后，你也可以创建自己的串行队列或并发队列。这就是说，至少有_五个_队列任你处置：主队列、四个全局调度队列，再加上任何你自己创建的队列。

以上是调度队列的大框架！

GCD 的“艺术”归结为选择合适的队列来调度函数以提交你的工作。体验这一点的最好方式是走一遍下边的列子，我们沿途会提供一些一般性的建议。

## 入门

既然本教程的目标是优化且安全的使用 GCD 调用来自不同线程的代码，那么你将从一个近乎完成的叫做 `GooglyPuff` 的项目入手。

GooglyPuff 是一个没有优化，线程不安全的应用，它使用 Core Image 的人脸检测 API 来覆盖一对曲棍球眼睛到被检测到的人脸上。对于基本的图像，可以从相机胶卷选择，或用预设好的URL从互联网下载。

[点击此处下载项目](http://cdn4.raywenderlich.com/wp-content/uploads/2014/01/GooglyPuff_Start_1.zip)

完成项目下载之后，将其解压到某个方便的目录，再用 Xcode 打开它并编译运行。这个应用看起来如下图所示：

![Workflow](http://cdn3.raywenderlich.com/wp-content/uploads/2014/01/Workflow1.png)

注意当你选择 `Le Internet` 选项下载图片时，一个 `UIAlertView` 过早地弹出。你将在本系列教程地第二部分修复这个问题。

这个项目中有四个有趣的类：

- PhotoCollectionViewController：它是应用开始的第一个视图控制器。它用缩略图展示所有选定的照片。
- PhotoDetailViewController：它执行添加曲棍球眼睛到图像上的逻辑，并用一个 UIScrollView 来显示结果图片。
- Photo：这是一个类簇，它根据一个 `NSURL` 的实例或一个 `ALAsset` 的实例来实例化照片。这个类提供一个图像、缩略图以及从 URL 下载的状态。
- PhotoManager：它管理所有 `Photo` 的实例.

## 用 dispatch_async 处理后台任务

回到应用并从你的相机胶卷添加一些照片或使用 `Le Internet` 选项下载一些。

注意在按下 `PhotoCollectionViewController` 中的一个 `UICollectionViewCell` 到生成一个新的 `PhotoDetailViewController` 之间花了多久时间；你会注意到一个明显的滞后，特别是在比较慢的设备上查看很大的图。

在重载 `UIViewController 的 viewDidLoad` 时容易加入太多杂乱的工作（too much clutter），这通常会引起视图控制器出现前更长的等待。如果可能，最好是卸下一些工作放到后台，如果它们不是绝对必须要运行在加载时间里。

这听起来像是 `dispatch_async` 能做的事情！

打开 `PhotoDetailViewController` 并用下面的实现替换 `viewDidLoad` ：

```Objective-C
- (void)viewDidLoad
{   
    [super viewDidLoad];
    NSAssert(_image, @"Image not set; required to use view controller");
    self.photoImageView.image = _image;
 
    //Resize if neccessary to ensure it's not pixelated
    if (_image.size.height <= self.photoImageView.bounds.size.height &&
        _image.size.width <= self.photoImageView.bounds.size.width) {
        [self.photoImageView setContentMode:UIViewContentModeCenter];
    }
 
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{ // 1
        UIImage *overlayImage = [self faceOverlayImageFromImage:_image];
        dispatch_async(dispatch_get_main_queue(), ^{ // 2
            [self fadeInNewImage:overlayImage]; // 3
        });
    });
}
```

下面来说明上面的新代码所做的事：

1. 你首先将工作从主线程移到全局线程。因为这是一个 `dispatch_async()` ，Block 会被异步地提交，意味着调用线程地执行将会继续。这就使得 `viewDidLoad` 更早地在主线程完成，让加载过程感觉起来更加快速。同时，一个人脸检测过程会启动并将在稍后完成。
2. 在这里，人脸检测过程完成，并生成了一个新的图像。既然你要使用此新图像更新你的 `UIImageView` ，那么你就添加一个新的 Block 到主线程。记住——你必须总是在主线程访问 UIKit 的类。
3. 最后，你用 `fadeInNewImage:` 更新 UI ，它执行一个淡入过程切换到新的曲棍球眼睛图像。

编译并运行你的应用；选择一个图像然后你会注意到视图控制器加载明显变快，曲棍球眼睛稍微在之后就加上了。这给应用带来了不错的效果，和之前的显示差别巨大。

进一步，如果你试着加载一个超大的图像，应用不会在加载视图控制器上“挂住”，这就使得应用具有很好伸缩性。

正如之前提到的， `dispatch_async` 添加一个 Block 到队列就立即返回了。任务会在之后由 GCD 决定执行。当你需要在后台执行一个基于网络或 CPU 紧张的任务时就使用 `dispatch_async` ，这样就不会阻塞当前线程。

下面是一个关于在 `dispatch_async` 上如何以及何时使用不同的队列类型的快速指导：

- 自定义串行队列：当你想串行执行后台任务并追踪它时就是一个好选择。这消除了资源争用，因为你知道一次只有一个任务在执行。注意若你需要来自某个方法的数据，你必须内联另一个 Block 来找回它或考虑使用 `dispatch_sync`。
- 主队列（串行）：这是在一个并发队列上完成任务后更新 UI 的共同选择。要这样做，你将在一个 Block 内部编写另一个 Block 。以及，如果你在主队列调用 `dispatch_async` 到主队列，你能确保这个新任务将在当前方法完成后的某个时间执行。
- 并发队列：这是在后台执行非 UI 工作的共同选择。

## 使用 dispatch_after 延后工作

稍微考虑一下应用的 UX 。是否用户第一次打开应用时会困惑于不知道做什么？你是这样吗？ :]

如果用户的 `PhotoManager` 里还没有任何照片，那么显示一个提示会是个好主意！然而，你同样要考虑用户的眼睛会如何在主屏幕上浏览：如果你太快的显示一个提示，他们的眼睛还徘徊在视图的其它部分上，他们很可能会错过它。

显示提示之前延迟一秒钟就足够捕捉到用户的注意，他们此时已经第一次看过了应用。

添加如下代码到到 PhotoCollectionViewController.m 中 showOrHideNavPrompt 的废止实现里：

```Objective-C
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
```

showOrHideNavPrompt 在 viewDidLoad 中执行，以及 UICollectionView 被重新加载的任何时候。按照注释数字顺序看看：

1. 你声明了一个变量指定要延迟的时长。
2. 然后等待 `delayInSeconds` 给定的时长，再异步地添加一个 Block 到主线程。

编译并运行应用。应该有一个轻微地延迟，这有助于抓住用户的注意力并展示所要做的事情。

`dispatch_after` 工作起来就像一个延迟版的 `dispatch_async` 。你依然不能控制实际的执行时间，且一旦 `dispatch_after` 返回也就不能再取消它。

不知道何时适合使用 `dispatch_after` ？

- 自定义串行队列：在一个自定义串行队列上使用 `dispatch_after` 要小心。你最好坚持使用主队列。
- 主队列（串行）：是使用 `dispatch_after` 的好选择；Xcode 提供了一个不错的自动完成模版。
- 并发队列：在并发队列上使用 `dispatch_after` 也要小心；你会这样做就比较罕见。还是在主队列做这些操作吧。

## 让你的单例线程安全

单例，不论喜欢还是讨厌，它们在 iOS 上的流行情况就像网上的猫。 :]

一个常见的担忧是它们常常不是线程安全的。这个担忧十分合理，基于它们的用途：单例常常被多个控制器同时访问。

单例的线程担忧范围从初始化开始，到信息的读和写。`PhotoManager` 类被实现为单例——它在目前的状态下就会被这些问题所困扰。要看看事情如何很快地失去控制，你将在单例实例上创建一个控制好的竞态条件。

导航到 `PhotoManager.m` 并找到 `sharedManager` ；它看起来如下：

```Objective-C
+ (instancetype)sharedManager    
{
    static PhotoManager *sharedPhotoManager = nil;
    if (!sharedPhotoManager) {
        sharedPhotoManager = [[PhotoManager alloc] init];
        sharedPhotoManager->_photosArray = [NSMutableArray array];
    }
    return sharedPhotoManager;
}
```

当前状态下，代码相当简单；你创建了一个单例并初始化一个叫做 `photosArray` 的 `NSMutableArray` 属性。

然而，`if` 条件分支不是[线程安全](http://www.raywenderlich.com/60749/grand-central-dispatch-in-depth-part-1#Terminology)的；如果你多次调用这个方法，有一个可能性是在某个线程（就叫它线程A）上进入 `if` 语句块并可能在 `sharedPhotoManager` 被分配内存前发生一个上下文切换。然后另一个线程（线程B）可能进入 `if` ，分配单例实例的内存，然后退出。

当系统上下文切换回线程A，你会分配另外一个单例实例的内存，然后退出。在那个时间点，你有了两个单例的实例——很明显这不是你想要的（译者注：这还能叫单例吗？）！

要强制这个（竞态）条件发生，替换 `PhotoManager.m` 中的 `sharedManager` 为下面的实现：

```Objective-C
+ (instancetype)sharedManager  
{
    static PhotoManager *sharedPhotoManager = nil;
    if (!sharedPhotoManager) {
        [NSThread sleepForTimeInterval:2];
        sharedPhotoManager = [[PhotoManager alloc] init];
        NSLog(@"Singleton has memory address at: %@", sharedPhotoManager);
        [NSThread sleepForTimeInterval:2];
        sharedPhotoManager->_photosArray = [NSMutableArray array];
    }
    return sharedPhotoManager;
}
```

上面的代码中你用 `NSThread 的 sleepForTimeInterval:` 类方法来强制发生一个上下文切换。

打开 `AppDelegate.m` 并添加如下代码到 `application:didFinishLaunchingWithOptions:` 的最开始处：

```Objective-C
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
    [PhotoManager sharedManager];
});
 
dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
    [PhotoManager sharedManager];
});
```

这里创建了多个异步并发调用来实例化单例，然后引发上面描述的竞态条件。

编译并运行项目；查看控制台输出，你会看到多个单例被实例化，如下所示：

![NSLog-Race-Condition](http://cdn2.raywenderlich.com/wp-content/uploads/2014/01/NSLog-Race-Condition-700x90.png)

注意到这里有好几行显示着不同地址的单例实例。这明显违背了单例的目的，对吧？:]

这个输出向你展示了临界区被执行多次，而它只应该执行一次。现在，固然是你自己强制这样的状况发生，但你可以想像一下这个状况会怎样在无意间发生。

>注意：基于其它你无法控制的系统事件，NSLog 的数量有时会显示多个。线程问题极其难以调试，因为它们往往难以重现。

要纠正这个状况，实例化代码应该只执行一次，并阻塞其它实例在 `if` 条件的临界区运行。这刚好就是 `dispatch_once` 能做的事。

在单例初始化方法中用 `dispatch_once` 取代 `if` 条件判断，如下所示：

```Objective-C
+ (instancetype)sharedManager
{
    static PhotoManager *sharedPhotoManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        [NSThread sleepForTimeInterval:2];
        sharedPhotoManager = [[PhotoManager alloc] init];
        NSLog(@"Singleton has memory address at: %@", sharedPhotoManager);
        [NSThread sleepForTimeInterval:2];
        sharedPhotoManager->_photosArray = [NSMutableArray array];
    });
    return sharedPhotoManager;
}
```

编译并运行你的应用；查看控制台输出，你会看到有且仅有一个单例的实例——这就是你对单例的期望！:]

现在你已经明白了防止竞态条件的重要性，从 `AppDelegate.m` 中移除 `dispatch_async` 语句，并用下面的实现替换 `PhotoManager` 单例的初始化：

```Objective-C
+ (instancetype)sharedManager
{
    static PhotoManager *sharedPhotoManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPhotoManager = [[PhotoManager alloc] init];
        sharedPhotoManager->_photosArray = [NSMutableArray array];
    });
    return sharedPhotoManager;
}
```

`dispatch_once()` 以线程安全的方式执行且仅执行其代码块一次。试图访问临界区（即传递给 `dispatch_once` 的代码）的不同的线程会在临界区已有一个线程的情况下被阻塞，直到临界区完成为止。

![Highlander_dispatch_once](http://cdn3.raywenderlich.com/wp-content/uploads/2014/01/Highlander_dispatch_once-480x274.png)

需要记住的是，这只是让访问共享实例线程安全。它绝对没有让类本身线程安全。类中可能还有其它竞态条件，例如任何操纵内部数据的情况。这些需要用其它方式来保证线程安全，例如同步访问数据，你将在下面几个小节看到。

## 处理读者与写者问题

线程安全实例不是处理单例时的唯一问题。如果单例属性表示一个可变对象，那么你就需要考虑是否那个对象自身线程安全。

如果问题中的这个对象是一个 Foundation 容器类，那么答案是——“很可能不安全”！Apple 维护一个[有用且有些心寒的列表](https://developer.apple.com/library/mac/documentation/cocoa/conceptual/multithreading/ThreadSafetySummary/ThreadSafetySummary.html)，众多的 Foundation 类都不是线程安全的。 `NSMutableArray`，已用于你的单例，正在那个列表里休息。

虽然许多线程可以同时读取 `NSMutableArray` 的一个实例而不会产生问题，但当一个线程正在读取时让另外一个线程修改数组就是不安全的。你的单例在目前的状况下不能预防这种情况的发生。

要分析这个问题，看看 `PhotoManager.m` 中的 `addPhoto:`，转载如下：

```Objective-C
- (void)addPhoto:(Photo *)photo
{
    if (photo) {
        [_photosArray addObject:photo];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self postContentAddedNotification];
        });
    }
}
```

这是一个`写`方法，它修改一个私有可变数组对象。

现在看看 `photos` ，转载如下：

```Objective-C
- (NSArray *)photos
{
  return [NSArray arrayWithArray:_photosArray];
}
```

这是所谓的`读`方法，它读取可变数组。它为调用者生成一个不可变的拷贝，防止调用者不当地改变数组，但这不能提供任何保护来对抗当一个线程调用读方法 `photos` 的同时另一个线程调用写方法 `addPhoto:` 。

这就是软件开发中经典的`读者写者问题`。GCD 通过用 `dispatch barriers` 创建一个`读者写者锁` 提供了一个优雅的解决方案。

Dispatch barriers 是一组函数，在并发队列上工作时扮演一个串行式的瓶颈。使用 GCD 的障碍（barrier）API 确保提交的 Block 在那个特定时间上是指定队列上唯一被执行的条目。这就意味着所有的先于调度障碍提交到队列的条目必能在这个 Block 执行前完成。

当这个 Block 的时机到达，调度障碍执行这个 Block 并确保在那个时间里队列不会执行任何其它 Block 。一旦完成，队列就返回到它默认的实现状态。 GCD 提供了同步和异步两种障碍函数。

下图显示了障碍函数对多个异步队列的影响：

![Dispatch-Barrier](http://cdn1.raywenderlich.com/wp-content/uploads/2014/01/Dispatch-Barrier-480x272.png)

注意到正常部分的操作就如同一个正常的并发队列。但当障碍执行时，它本质上就如同一个串行队列。也就是，障碍是唯一在执行的事物。在障碍完成后，队列回到一个正常并发队列的样子。

下面是你何时会——和不会——使用障碍函数的情况：

- 自定义串行队列：一个很坏的选择；障碍不会有任何帮助，因为不管怎样，一个串行队列一次都只执行一个操作。
- 全局并发队列：要小心；这可能不是最好的主意，因为其它系统可能在使用队列而且你不能垄断它们只为你自己的目的。
- 自定义并发队列：这对于原子或临界区代码来说是极佳的选择。任何你在设置或实例化的需要线程安全的事物都是使用障碍的最佳候选。

由于上面唯一像样的选择是自定义并发队列，你将创建一个你自己的队列去处理你的障碍函数并分开读和写函数。且这个并发队列将允许多个多操作同时进行。

打开 `PhotoManager.m`，添加如下私有属性到类扩展中：

```Objective-C
@interface PhotoManager ()
@property (nonatomic,strong,readonly) NSMutableArray *photosArray;
@property (nonatomic, strong) dispatch_queue_t concurrentPhotoQueue; ///< Add this
@end
```

找到 `addPhoto:` 并用下面的实现替换它：

```Objective-C
- (void)addPhoto:(Photo *)photo
{
    if (photo) { // 1
        dispatch_barrier_async(self.concurrentPhotoQueue, ^{ // 2 
            [_photosArray addObject:photo]; // 3
            dispatch_async(dispatch_get_main_queue(), ^{ // 4
                [self postContentAddedNotification]; 
            });
        });
    }
}
```

你新写的函数是这样工作的：

1. 在执行下面所有的工作前检查是否有合法的相片。
2. 添加写操作到你的自定义队列。当临界区在稍后执行时，这将是你队列中唯一执行的条目。
3. 这是添加对象到数组的实际代码。由于它是一个障碍 Block ，这个 Block 永远不会同时和其它 Block 一起在 concurrentPhotoQueue 中执行。
4. 最后你发送一个通知说明完成了添加图片。这个通知将在主线程被发送因为它将会做一些 UI 工作，所以在此为了通知，你异步地调度另一个任务到主线程。

这就处理了写操作，但你还需要实现 `photos` 读方法并实例化 `concurrentPhotoQueue` 。

在写者打扰的情况下，要确保线程安全，你需要在 `concurrentPhotoQueue` 队列上执行读操作。既然你需要从函数返回，你就不能异步调度到队列，因为那样在读者函数返回之前不一定运行。

在这种情况下，`dispatch_sync` 就是一个绝好的候选。

`dispatch_sync()` 同步地提交工作并在返回前等待它完成。使用 `dispatch_sync` 跟踪你的调度障碍工作，或者当你需要等待操作完成后才能使用 Block 处理过的数据。如果你使用第二种情况做事，你将不时看到一个 `__block` 变量写在 `dispatch_sync` 范围之外，以便返回时在 `dispatch_sync` 使用处理过的对象。

但你需要很小心。想像如果你调用 `dispatch_sync` 并放在你已运行着的当前队列。这会导致死锁，因为调用会一直等待直到 Block 完成，但 Block 不能完成（它甚至不会开始！），直到当前已经存在的任务完成，而当前任务无法完成！这将迫使你自觉于你正从哪个队列调用——以及你正在传递进入哪个队列。

下面是一个快速总览，关于在何时以及何处使用 `dispatch_sync` ：

- 自定义串行队列：在这个状况下要非常小心！如果你正运行在一个队列并调用 `dispatch_sync` 放在同一个队列，那你就百分百地创建了一个死锁。
- 主队列（串行）：同上面的理由一样，必须非常小心！这个状况同样有潜在的导致死锁的情况。
- 并发队列：这才是做同步工作的好选择，不论是通过调度障碍，或者需要等待一个任务完成才能执行进一步处理的情况。

继续在 `PhotoManager.m` 上工作，用下面的实现替换 `photos` ：

```Objective-C
- (NSArray *)photos
{
    __block NSArray *array; // 1
    dispatch_sync(self.concurrentPhotoQueue, ^{ // 2
        array = [NSArray arrayWithArray:_photosArray]; // 3
    });
    return array;
}
```

这就是你的读函数。按顺序看看编过号的注释，有这些：

1. `__block` 关键字允许对象在 Block 内可变。没有它，`array` 在 Block 内部就只是只读的，你的代码甚至不能通过编译。
2. 在 `concurrentPhotoQueue` 上同步调度来执行读操作。
3. 将相片数组存储在 `array` 内并返回它。

最后，你需要实例化你的 `concurrentPhotoQueue` 属性。修改 `sharedManager` 以便像下面这样初始化队列：

```Objective-C
+ (instancetype)sharedManager
{
    static PhotoManager *sharedPhotoManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedPhotoManager = [[PhotoManager alloc] init];
        sharedPhotoManager->_photosArray = [NSMutableArray array];
 
        // ADD THIS:
        sharedPhotoManager->_concurrentPhotoQueue = dispatch_queue_create("com.selander.GooglyPuff.photoQueue",
                                                    DISPATCH_QUEUE_CONCURRENT); 
    });
 
    return sharedPhotoManager;
}
```

这里使用 `dispatch_queue_create` 初始化 `concurrentPhotoQueue` 为一个并发队列。第一个参数是反向DNS样式命名惯例；确保它是描述性的，将有助于调试。第二个参数指定你的队列是串行还是并发。

>注意：当你在网上搜索例子时，你会经常看人们传递 `0` 或者 `NULL` 给 `dispatch_queue_create` 的第二个参数。这是一个创建串行队列的过时方式；明确你的参数总是更好。

恭喜——你的 `PhotoManager` 单例现在是线程安全的了。不论你在何处或怎样读或写你的照片，你都有这样的自信，即它将以安全的方式完成，不会出现任何惊吓。

## A Visual Review of Queueing 队列的虚拟回顾

依然没有 100% 地掌握 GCD 的要领？确保你可以使用 GCD 函数轻松地创建简单的例子，使用断点和 `NSLog` 语句保证自己明白当下发生的情况。

我在下面提供了两个 GIF动画来帮助你巩固对 `dispatch_async` 和 `dispatch_sync` 的理解。包含在每个 GIF 中的代码可以提供视觉辅助；仔细注意 GIF 左边显示代码断点的每一步，以及右边相关队列的状态。

### dispatch_sync 回顾

```Objective-C
- (void)viewDidLoad
{
  [super viewDidLoad];
 
  dispatch_sync(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
 
      NSLog(@"First Log");
 
  });
 
  NSLog(@"Second Log");
}
```

![dispatch_sync_in_action](http://cdn1.raywenderlich.com/wp-content/uploads/2014/01/dispatch_sync_in_action.gif)

下面是图中几个步骤的说明：

1. 主队列一路按顺序执行任务——接着是一个实例化 `UIViewController` 的任务，其中包含了 `viewDidLoad` 。
2. `viewDidLoad` 在主线程执行。
3. 主线程目前在 `viewDidLoad` 内，正要到达 `dispatch_sync` 。
4. `dispatch_sync` Block 被添加到一个全局队列中，将在稍后执行。进程将在主线程挂起直到该 Block 完成。同时，全局队列并发处理任务；要记得 Block 在全局队列中将按照 FIFO 顺序出列，但可以并发执行。
5. 全局队列处理 `dispatch_sync` Block 加入之前已经出现在队列中的任务。
6. 终于，轮到 `dispatch_sync` Block 。
7. 这个 Block 完成，因此主线程上的任务可以恢复。
8. `viewDidLoad` 方法完成，主队列继续处理其他任务。

`dispatch_sync` 添加任务到一个队列并等待直到任务完成。`dispatch_async` 做类似的事情，但不同之处是它不会等待任务的完成，而是立即继续“调用线程”的其它任务。

### dispatch_async 回顾

```Objective-C
- (void)viewDidLoad
{
  [super viewDidLoad];
 
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{
 
      NSLog(@"First Log");
 
  });
 
  NSLog(@"Second Log");
}
```

![dispatch_async_in_action](http://cdn1.raywenderlich.com/wp-content/uploads/2014/01/dispatch_async_in_action.gif)

1. 主队列一路按顺序执行任务——接着是一个实例化 `UIViewController` 的任务，其中包含了 `viewDidLoad` 。
2. `viewDidLoad` 在主线程执行。
3. 主线程目前在 `viewDidLoad` 内，正要到达 `dispatch_async` 。
4. `dispatch_async` Block 被添加到一个全局队列中，将在稍后执行。
5. `viewDidLoad` 在添加 `dispatch_async` 到全局队列后继续进行，主线程把注意力转向剩下的任务。同时，全局队列并发地处理它未完成地任务。记住 Block 在全局队列中将按照 FIFO 顺序出列，但可以并发执行。
6. 添加到 `dispatch_async` 的代码块开始执行。
7. `dispatch_async` Block 完成，两个 `NSLog` 语句将它们的输出放在控制台上。

在这个特定的实例中，第二个 `NSLog` 语句执行，跟着是第一个 `NSLog` 语句。并不总是这样——着取决于给定时刻硬件正在做的事情，而且你无法控制或知晓哪个语句会先执行。“第一个” `NSLog` 在某些调用情况下会第一个执行。

## 下一步怎么走？

在本教程中，你学习了如何让你的代码线程安全，以及在执行 CPU 密集型任务时如何保持主线程的响应性。
 
你可以下载[ GooglyPuff 项目](http://cdn2.raywenderlich.com/wp-content/uploads/2014/01/GooglyPuff_End_1.zip)，它包含了目前所有本教程中编写的实现。在本教程的[第二部分](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md)，你将继续改进这个项目。

如果你计划优化你自己的应用，那你应该用 `Instruments` 中的 `Time Profile` 模版分析你的工作。对这个工具的使用超出了本教程的范围，你可以看看 [如何使用Instruments](http://www.raywenderlich.com/23037/how-to-use-instruments-in-xcode) 来得到一个很好的概述。

同时请确保在真实设备上分析，而在模拟器上测试会对程序速度产生非常不准确的印象。

在教程的下一部分，你将更加深入到 GCD 的 API 中，做一些更 Cool 的东西。

如果你有任何问题或评论，可自由地加入下方的讨论！

============================

欢迎来到GCD深入理解系列教程的第二部分（也是最后一部分）。

在本系列的[第一部分](https://github.com/nixzhu/dev-blog/blob/master/2014-04-19-grand-central-dispatch-in-depth-part-1.md)中，你已经学到超过你想像的关于并发、线程以及GCD 如何工作的知识。通过在初始化时利用 `dispatch_once`，你创建了一个线程安全的 `PhotoManager` 单例，而且你通过使用 `dispatch_barrier_async` 和 `dispatch_sync` 的组合使得对 `Photos` 数组的读取和写入都变得线程安全了。

除了上面这些，你还通过利用 `dispatch_after` 来延迟显示提示信息，以及利用 `dispatch_async` 将 CPU 密集型任务从 ViewController 的初始化过程中剥离出来异步执行，达到了增强应用的用户体验的目的。

如果你一直跟着第一部分的教程在写代码，那你可以继续你的工程。但如果你没有完成第一部分的工作，或者不想重用你的工程，你可以[下载第一部分最终的代码](http://cdn2.raywenderlich.com/wp-content/uploads/2014/01/GooglyPuff_End_1.zip)。

那就让我们来更深入地探索 GCD 吧！

## [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#纠正过早弹出的提示)纠正过早弹出的提示

你可能已经注意到当你尝试用 Le Internet 选项来添加图片时，一个 `UIAlertView` 会在图片下载完成之前就弹出，如下如所示：

[![Premature Completion Block](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f53637265656e2d53686f742d323031342d30312d31372d61742d352e34392e35312d504d2d333038783530302e706e67.)](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f53637265656e2d53686f742d323031342d30312d31372d61742d352e34392e35312d504d2d333038783530302e706e67.)

问题的症结在 PhotoManagers 的 `downloadPhotoWithCompletionBlock:` 里，它目前的实现如下：

```source-objc
- (void)downloadPhotosWithCompletionBlock:(BatchPhotoDownloadingCompletionBlock)completionBlock
{
    __block NSError *error;

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

        Photo *photo = [[Photo alloc] initwithURL:url
                              withCompletionBlock:^(UIImage *image, NSError *_error) {
                                  if (_error) {
                                      error = _error;
                                  }
                              }];

        [[PhotoManager sharedManager] addPhoto:photo];
    }

    if (completionBlock) {
        completionBlock(error);
    }
}
```

在方法的最后你调用了 `completionBlock` ——因为此时你假设所有的照片都已下载完成。但很不幸，此时并不能保证所有的下载都已完成。

`Photo` 类的实例方法用某个 URL 开始下载某个文件并立即返回，但此时下载并未完成。换句话说，当 `downloadPhotoWithCompletionBlock:` 在其末尾调用 `completionBlock` 时，它就假设了它自己所使用的方法全都是同步的，而且每个方法都完成了它们的工作。

然而，`-[Photo initWithURL:withCompletionBlock:]` 是异步执行的，会立即返回——所以这种方式行不通。

因此，只有在所有的图像下载任务都调用了它们自己的 Completion Block 之后，`downloadPhotoWithCompletionBlock:` 才能调用它自己的 `completionBlock` 。问题是：你该如何监控并发的异步事件？你不知道它们何时完成，而且它们完成的顺序完全是不确定的。

或许你可以写一些比较 Hacky 的代码，用多个布尔值来记录每个下载的完成情况，但这样做就缺失了扩展性，而且说实话，代码会很难看。

幸运的是， 解决这种对多个异步任务的完成进行监控的问题，恰好就是设计 dispatch_group 的目的。

### [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#dispatch-groups调度组)Dispatch Groups（调度组）

Dispatch Group 会在整个组的任务都完成时通知你。这些任务可以是同步的，也可以是异步的，即便在不同的队列也行。而且在整个组的任务都完成时，Dispatch Group 可以用同步的或者异步的方式通知你。因为要监控的任务在不同队列，那就用一个 `dispatch_group_t` 的实例来记下这些不同的任务。

当组中所有的事件都完成时，GCD 的 API 提供了两种通知方式。

第一种是 `dispatch_group_wait` ，它会阻塞当前线程，直到组里面所有的任务都完成或者等到某个超时发生。这恰好是你目前所需要的。

打开 PhotoManager.m，用下列实现替换 `downloadPhotosWithCompletionBlock:`：

```source-objc
- (void)downloadPhotosWithCompletionBlock:(BatchPhotoDownloadingCompletionBlock)completionBlock
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^{ // 1

        __block NSError *error;
        dispatch_group_t downloadGroup = dispatch_group_create(); // 2

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

            dispatch_group_enter(downloadGroup); // 3
            Photo *photo = [[Photo alloc] initwithURL:url
                                  withCompletionBlock:^(UIImage *image, NSError *_error) {
                                      if (_error) {
                                          error = _error;
                                      }
                                      dispatch_group_leave(downloadGroup); // 4
                                  }];

            [[PhotoManager sharedManager] addPhoto:photo];
        }
        dispatch_group_wait(downloadGroup, DISPATCH_TIME_FOREVER); // 5
        dispatch_async(dispatch_get_main_queue(), ^{ // 6
            if (completionBlock) { // 7
                completionBlock(error);
            }
        });
    });
}
```

按照注释的顺序，你会看到：

1. 因为你在使用的是同步的 `dispatch_group_wait` ，它会阻塞当前线程，所以你要用 `dispatch_async` 将整个方法放入后台队列以避免阻塞主线程。
2. 创建一个新的 Dispatch Group，它的作用就像一个用于未完成任务的计数器。
3. `dispatch_group_enter` 手动通知 Dispatch Group 任务已经开始。你必须保证 `dispatch_group_enter` 和 `dispatch_group_leave` 成对出现，否则你可能会遇到诡异的崩溃问题。
4. 手动通知 Group 它的工作已经完成。再次说明，你必须要确保进入 Group 的次数和离开 Group 的次数相等。
5. `dispatch_group_wait` 会一直等待，直到任务全部完成或者超时。如果在所有任务完成前超时了，该函数会返回一个非零值。你可以对此返回值做条件判断以确定是否超出等待周期；然而，你在这里用 `DISPATCH_TIME_FOREVER` 让它永远等待。它的意思，勿庸置疑就是，永－远－等－待！这样很好，因为图片的创建工作总是会完成的。
6. 此时此刻，你已经确保了，要么所有的图片任务都已完成，要么发生了超时。然后，你在主线程上运行 `completionBlock` 回调。这会将工作放到主线程上，并在稍后执行。
7. 最后，检查 `completionBlock` 是否为 nil，如果不是，那就运行它。

编译并运行你的应用，尝试下载多个图片，观察你的应用是在何时运行 completionBlock 的。

> 注意：如果你是在真机上运行应用，而且网络活动发生得太快以致难以观察 completionBlock 被调用的时刻，那么你可以在 Settings 应用里的开发者相关部分里打开一些网络设置，以确保代码按照我们所期望的那样工作。只需去往 Network Link Conditioner 区，开启它，再选择一个 Profile，“Very Bad Network” 就不错。

如果你是在模拟器里运行应用，你可以使用 [来自 GitHub 的 Network Link Conditioner](http://nshipster.com/network-link-conditioner/) 来改变网络速度。它会成为你工具箱中的一个好工具，因为它强制你研究你的应用在连接速度并非最佳的情况下会变成什么样。

目前为止的解决方案还不错，但是总体来说，如果可能，最好还是要避免阻塞线程。你的下一个任务是重写一些方法，以便当所有下载任务完成时能异步通知你。

在我们转向另外一种使用 Dispatch Group 的方式之前，先看一个简要的概述，关于何时以及怎样使用有着不同的队列类型的 Dispatch Group ：

* 自定义串行队列：它很适合当一组任务完成时发出通知。
* 主队列（串行）：它也很适合这样的情况。但如果你要同步地等待所有工作地完成，那你就不应该使用它，因为你不能阻塞主线程。然而，异步模型是一个很有吸引力的能用于在几个较长任务（例如网络调用）完成后更新 UI 的方式。
* 并发队列：它也很适合 Dispatch Group 和完成时通知。

### [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#dispatch-group第二种方式)Dispatch Group，第二种方式

上面的一切都很好，但在另一个队列上异步调度然后使用 dispatch_group_wait 来阻塞实在显得有些笨拙。是的，还有另一种方式……

在 PhotoManager.m 中找到 `downloadPhotosWithCompletionBlock:` 方法，用下面的实现替换它：

```source-objc
- (void)downloadPhotosWithCompletionBlock:(BatchPhotoDownloadingCompletionBlock)completionBlock
{
    // 1
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
```

下面解释新的异步方法如何工作：

1. 在新的实现里，因为你没有阻塞主线程，所以你并不需要将方法包裹在 `async` 调用中。
2. 同样的 `enter` 方法，没做任何修改。
3. 同样的 `leave` 方法，也没做任何修改。
4. `dispatch_group_notify` 以异步的方式工作。当 Dispatch Group 中没有任何任务时，它就会执行其代码，那么 `completionBlock` 便会运行。你还指定了运行 `completionBlock` 的队列，此处，主队列就是你所需要的。

对于这个特定的工作，上面的处理明显更清晰，而且也不会阻塞任何线程。

## [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#太多并发带来的风险)太多并发带来的风险

既然你的工具箱里有了这些新工具，你大概做任何事情都想使用它们，对吧？

[![Thread_All_The_Code_Meme](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f5468726561645f416c6c5f5468655f436f64655f4d656d652e6a7067.)](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f5468726561645f416c6c5f5468655f436f64655f4d656d652e6a7067.)

看看 PhotoManager 中的 `downloadPhotosWithCompletionBlock` 方法。你可能已经注意到这里的 `for` 循环，它迭代三次，下载三个不同的图片。你的任务是尝试让 `for` 循环并发运行，以提高其速度。

`dispatch_apply` 刚好可用于这个任务。

`dispatch_apply` 表现得就像一个 `for` 循环，但它能并发地执行不同的迭代。这个函数是同步的，所以和普通的 `for` 循环一样，它只会在所有工作都完成后才会返回。

当在 Block 内计算任何给定数量的工作的最佳迭代数量时，必须要小心，因为过多的迭代和每个迭代只有少量的工作会导致大量开销以致它能抵消任何因并发带来的收益。而被称为`跨越式（striding）`的技术可以在此帮到你，即通过在每个迭代里多做几个不同的工作。

> 译者注：大概就能减少并发数量吧，作者是提醒大家注意并发的开销，记在心里！

那何时才适合用 `dispatch_apply` 呢？

* 自定义串行队列：串行队列会完全抵消 `dispatch_apply` 的功能；你还不如直接使用普通的 `for` 循环。
* 主队列（串行）：与上面一样，在串行队列上不适合使用 `dispatch_apply` 。还是用普通的 `for` 循环吧。
* 并发队列：对于并发循环来说是很好选择，特别是当你需要追踪任务的进度时。

回到 `downloadPhotosWithCompletionBlock:` 并用下列实现替换它：

```source-objc
- (void)downloadPhotosWithCompletionBlock:(BatchPhotoDownloadingCompletionBlock)completionBlock
{
    __block NSError *error;
    dispatch_group_t downloadGroup = dispatch_group_create();

    dispatch_apply(3, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^(size_t i) {

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

        dispatch_group_enter(downloadGroup);
        Photo *photo = [[Photo alloc] initwithURL:url
                              withCompletionBlock:^(UIImage *image, NSError *_error) {
                                  if (_error) {
                                      error = _error;
                                  }
                                  dispatch_group_leave(downloadGroup);
                              }];

        [[PhotoManager sharedManager] addPhoto:photo];
    });

    dispatch_group_notify(downloadGroup, dispatch_get_main_queue(), ^{
        if (completionBlock) {
            completionBlock(error);
        }
    });
}
```

你的循环现在是并行运行的了；在上面的代码中，在调用 `dispatch_apply` 时，你用第一次参数指明了迭代的次数，用第二个参数指定了任务运行的队列，而第三个参数是一个 Block。

要知道虽然你有代码保证添加相片时线程安全，但图片的顺序却可能不同，这取决于线程完成的顺序。

编译并运行，然后从 “Le Internet” 添加一些照片。注意到区别了吗？

在真机上运行新代码会稍微更快的得到结果。但我们所做的这些提速工作真的值得吗？

实际上，在这个例子里并不值得。下面是原因：

* 你创建并行运行线程而付出的开销，很可能比直接使用 `for` 循环要多。若你要以合适的步长迭代非常大的集合，那才应该考虑使用 `dispatch_apply`。
* 你用于创建应用的时间是有限的——除非实在太糟糕否则不要浪费时间去提前优化代码。如果你要优化什么，那去优化那些明显值得你付出时间的部分。你可以通过在 Instruments 里分析你的应用，找出最长运行时间的方法。看看 [如何在 Xcode 中使用 Instruments](http://www.raywenderlich.com/23037/how-to-use-instruments-in-xcode) 可以学到更多相关知识。
* 通常情况下，优化代码会让你的代码更加复杂，不利于你自己和其他开发者阅读。请确保添加的复杂性能换来足够多的好处。

记住，不要在优化上太疯狂。你只会让你自己和后来者更难以读懂你的代码。

## [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#gcd-的其他趣味)GCD 的其他趣味

等一下！还有更多！有一些额外的函数在不同的道路上走得更远。虽然你不会太频繁地使用这些工具，但在对的情况下，它们可以提供极大的帮助。

### [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#阻塞正确的方式)阻塞——正确的方式

这可能听起来像是个疯狂的想法，但你知道 Xcode 已有了测试功能吗？:] 我知道，虽然有时候我喜欢假装它不存在，但在代码里构建复杂关系时编写和运行测试非常重要。

Xcode 里的测试在 `XCTestCase` 的子类上执行，并运行任何方法签名以 `test` 开头的方法。测试在主线程运行，所以你可以假设所有测试都是串行发生的。

当一个给定的测试方法运行完成，XCTest 方法将考虑此测试已结束，并进入下一个测试。这意味着任何来自前一个测试的异步代码会在下一个测试运行时继续运行。

网络代码通常是异步的，因此你不能在执行网络获取时阻塞主线程。也就是说，整个测试会在测试方法完成之后结束，这会让对网络代码的测试变得很困难。也就是，除非你在测试方法内部阻塞主线程直到网络代码完成。

> 注意：有一些人会说，这种类型的测试不属于集成测试的首选集（Preferred Set）。一些人会赞同，一些人不会。但如果你想做，那就去做。

[![Gandalf_Semaphore](media/14796117251911/687474703a2f2f63646e312e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f47616e64616c665f53656d6170686f72652e706e67.)](media/14796117251911/687474703a2f2f63646e312e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f47616e64616c665f53656d6170686f72652e706e67.)

导航到 GooglyPuffTests.m 并查看 `downloadImageURLWithString:`，如下：

```source-objc
- (void)downloadImageURLWithString:(NSString *)URLString
{
    NSURL *url = [NSURL URLWithString:URLString];
    __block BOOL isFinishedDownloading = NO;
    __unused Photo *photo = [[Photo alloc]
                             initwithURL:url
                             withCompletionBlock:^(UIImage *image, NSError *error) {
                                 if (error) {
                                     XCTFail(@"%@ failed. %@", URLString, error);
                                 }
                                 isFinishedDownloading = YES;
                             }];

    while (!isFinishedDownloading) {}
}
```

这是一种测试异步网络代码的幼稚方式。 While 循环在函数的最后一直等待，直到 `isFinishedDownloading` 布尔值变成 True，它只会在 Completion Block 里发生。让我们看看这样做有什么影响。

通过在 Xcode 中点击 Product / Test 运行你的测试，如果你使用默认的键绑定，也可以使用快捷键 ⌘+U 来运行你的测试。

在测试运行时，注意 Xcode debug 导航栏里的 CPU 使用率。这个设计不当的实现就是一个基本的 [自旋锁](http://en.wikipedia.org/wiki/Spinlock) 。它很不实用，因为你在 While 循环里浪费了珍贵的 CPU 周期；而且它也几乎没有扩展性。

> 译者注：所谓自旋锁，就是某个线程一直抢占着 CPU 不断检查以等到它需要的情况出现。因为现代操作系统都是可以并发运行多个线程的，所以它所等待的那个线程也有机会被调度执行，这样它所需要的情况早晚会出现。

你可能需要使用前面提到的 Network Link Conditioner ，已便清楚地看到这个问题。如果你的网络太快，那么自旋只会在很短的时间里发生，难以观察。

> 译者注：作者反复提到网速太快，而我们还需要对付 GFW，简直泪流满面！

你需要一个更优雅、可扩展的解决方案来阻塞线程直到资源可用。欢迎来到信号量。

### [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#信号量)信号量

信号量是一种老式的线程概念，由非常谦卑的 Edsger W. Dijkstra 介绍给世界。信号量之所以比较复杂是因为它建立在操作系统的复杂性之上。

如果你想学到更多关于信号量的知识，看看这个链接[它更细致地讨论了信号量理论](http://greenteapress.com/semaphores/)。如果你是学术型，那可以看一个软件开发中经典的[哲学家进餐问题](http://zh.wikipedia.org/wiki/%E5%93%B2%E5%AD%A6%E5%AE%B6%E5%B0%B1%E9%A4%90%E9%97%AE%E9%A2%98)，它需要使用信号量来解决。

信号量让你控制多个消费者对有限数量资源的访问。举例来说，如果你创建了一个有着两个资源的信号量，那同时最多只能有两个线程可以访问临界区。其他想使用资源的线程必须在一个…你猜到了吗？…FIFO队列里等待。

让我们来使用信号量吧！

打开 GooglyPuffTests.m 并用下列实现替换 `downloadImageURLWithString:`：

```source-objc
- (void)downloadImageURLWithString:(NSString *)URLString
{
    // 1
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    NSURL *url = [NSURL URLWithString:URLString];
    __unused Photo *photo = [[Photo alloc]
                             initwithURL:url
                             withCompletionBlock:^(UIImage *image, NSError *error) {
                                 if (error) {
                                     XCTFail(@"%@ failed. %@", URLString, error);
                                 }

                                 // 2
                                 dispatch_semaphore_signal(semaphore);
                             }];

    // 3
    dispatch_time_t timeoutTime = dispatch_time(DISPATCH_TIME_NOW, kDefaultTimeoutLengthInNanoSeconds);
    if (dispatch_semaphore_wait(semaphore, timeoutTime)) {
        XCTFail(@"%@ timed out", URLString);
    }
}
```

下面来说明你代码中的信号量是如何工作的：

1. 创建一个信号量。参数指定信号量的起始值。这个数字是你可以访问的信号量，不需要有人先去增加它的数量。（注意到增加信号量也被叫做发射信号量）。译者注：这里初始化为0，也就是说，有人想使用信号量必然会被阻塞，直到有人增加信号量。
2. 在 Completion Block 里你告诉信号量你不再需要资源了。这就会增加信号量的计数并告知其他想使用此资源的线程。
3. 这会在超时之前等待信号量。这个调用阻塞了当前线程直到信号量被发射。这个函数的一个非零返回值表示到达超时了。在这个例子里，测试将会失败因为它以为网络请求不会超过 10 秒钟就会返回——一个平衡点！

再次运行测试。只要你有一个正常工作的网络连接，这个测试就会马上成功。请特别注意 CPU 的使用率，与之前使用自旋锁的实现作个对比。

关闭你的网络链接再运行测试；如果你在真机上运行，就打开飞行模式。如果你的在模拟器里运行，你可以直接断开 Mac 的网络链接。测试会在 10 秒后失败。这很棒，它真的能按照预想的那样工作！

还有一些琐碎的测试，但如果你与一个服务器组协同工作，那么这些基本的测试能够防止其他人就最新的网络问题对你说三道四。

### [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#使用-dispatch-source)使用 Dispatch Source

GCD 的一个特别有趣的特性是 Dispatch Source，它基本上就是一个低级函数的 grab-bag ，能帮助你去响应或监测 Unix 信号、文件描述符、Mach 端口、VFS 节点，以及其它晦涩的东西。所有这些都超出了本教程讨论的范围，但你可以通过实现一个 Dispatch Source 对象并以一个相当奇特的方式来使用它来品尝那些晦涩的东西。

第一次使用 Dispatch Source 可能会迷失在如何使用一个源，所以你需要知晓的第一件事是 `dispatch_source_create` 如何工作。下面是创建一个源的函数原型：

```source-objc
dispatch_source_t dispatch_source_create(
   dispatch_source_type_t type,
   uintptr_t handle,
   unsigned long mask,
   dispatch_queue_t queue);
```

第一个参数是 `dispatch_source_type_t` 。这是最重要的参数，因为它决定了 handle 和 mask 参数将会是什么。你可以查看 [Xcode 文档](https://developer.apple.com/library/mac/documentation/Performance/Reference/GCD_libdispatch_Ref/Reference/reference.html#//apple_ref/doc/constant_group/Dispatch_Source_Type_Constants) 得到哪些选项可用于每个 `dispatch_source_type_t` 参数。

下面你将监控 `DISPATCH_SOURCE_TYPE_SIGNAL` 。如[文档所显示的](https://developer.apple.com/library/mac/documentation/Performance/Reference/GCD_libdispatch_Ref/Reference/reference.html#//apple_ref/c/macro/DISPATCH_SOURCE_TYPE_SIGNAL%22)：

一个监控当前进程信号的 Dispatch Source。 handle 是信号编号，mask 未使用（传 0 即可）。

这些 Unix 信号组成的列表可在头文件 [signal.h](http://www.opensource.apple.com/source/xnu/xnu-1456.1.26/bsd/sys/signal.h) 中找到。在其顶部有一堆 `#define` 语句。你将监控此信号列表中的 `SIGSTOP`信号。这个信号将会在进程接收到一个无法回避的暂停指令时被发出。在你用 LLDB 调试器调试应用时你使用的也是这个信号。

去往 PhotoCollectionViewController.m 并添加如下代码到 `viewDidLoad` 的顶部，就在 `[super viewDidLoad]` 下面：

```source-objc
- (void)viewDidLoad
{
  [super viewDidLoad];

  // 1
  #if DEBUG
      // 2
      dispatch_queue_t queue = dispatch_get_main_queue();

      // 3
      static dispatch_source_t source = nil;

      // 4
      __typeof(self) __weak weakSelf = self;

      // 5
      static dispatch_once_t onceToken;
      dispatch_once(&onceToken, ^{
          // 6
          source = dispatch_source_create(DISPATCH_SOURCE_TYPE_SIGNAL, SIGSTOP, 0, queue);

          // 7
          if (source)
          {
              // 8
              dispatch_source_set_event_handler(source, ^{
                  // 9
                  NSLog(@"Hi, I am: %@", weakSelf);
              });
              dispatch_resume(source); // 10
          }
      });
  #endif

  // The other stuff
}
```

这些代码有点儿复杂，所以跟着注释一步步走，看看到底发生了什么：

1. 最好是在 DEBUG 模式下编译这些代码，因为这会给“有关方面（Interested Parties）”很多关于你应用的洞察。 :]
2. Just to mix things up，你创建了一个 `dispatch_queue_t` 实例变量而不是在参数上直接使用函数。当代码变长，分拆有助于可读性。
3. 你需要 `source` 在方法范围之外也可被访问，所以你使用了一个 static 变量。
4. 使用 `weakSelf` 以确保不会出现保留环（Retain Cycle）。这对 `PhotoCollectionViewController` 来说不是完全必要的，因为它会在应用的整个生命期里保持活跃。然而，如果你有任何其它会消失的类，这就能确保不会出现保留环而造成内存泄漏。
5. 使用 `dispatch_once` 确保只会执行一次 Dispatch Source 的设置。
6. 初始化 `source` 变量。你指明了你对信号监控感兴趣并提供了 `SIGSTOP` 信号作为第二个参数。进一步，你使用主队列处理接收到的事件——很快你就好发现为何要这样做。
7. 如果你提供的参数不合格，那么 Dispatch Source 对象不会被创建。也就是说，在你开始在其上工作之前，你需要确保已有了一个有效的 Dispatch Source 。
8. 当你收到你所监控的信号时，`dispatch_source_set_event_handler` 就会执行。之后你可以在其 Block 里设置合适的逻辑处理器（Logic Handler）。
9. 一个基本的 `NSLog` 语句，它将对象打印到控制台。
10. 默认的，所有源都初始为暂停状态。如果你要开始监控事件，你必须告诉源对象恢复活跃状态。

编译并运行应用；在调试器里暂停并立即恢复应用，查看控制台，你会看到这个来自黑暗艺术的函数确实可以工作。你看到的大概如下：

```
2014-03-29 17:41:30.610 GooglyPuff[8181:60b] Hi, I am:

```

你的应用现在具有调试感知了！这真是超级棒，但在真实世界里该如何使用它呢？

你可以用它去调试一个对象并在任何你想恢复应用的时候显示数据；你同样能给你的应用加上自定义的安全逻辑以便在恶意攻击者将一个调试器连接到你的应用上时保护它自己（或用户的数据）。

> 译者注：好像挺有用！

一个有趣的主意是，使用此方式的作为一个堆栈追踪工具去找到你想在调试器里操纵的对象。

[![What_Meme](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f576861745f4d656d652e6a7067.)](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f576861745f4d656d652e6a7067.)

稍微想想这个情况。当你意外地停止调试器，你几乎从来都不会在所需的栈帧上。现在你可以在任何时候停止调试器并在你所需的地方执行代码。如果你想在你的应用的某一点执行的代码非常难以从调试器访问的话，这会非常有用。有机会试试吧！

[![I_See_What_You_Did_Meme](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f495f5365655f576861745f596f755f4469645f4d656d652e706e67.)](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f495f5365655f576861745f596f755f4469645f4d656d652e706e67.)

将一个断点放在你刚添加在 viewDidLoad 里的事件处理器的 `NSLog` 语句上。在调试器里暂停，然后再次开始；应用会到达你添加的断点。现在你深入到你的 PhotoCollectionViewController 方法深处。你可以访问 PhotoCollectionViewController 的实例得到你关心的内容。非常方便！

> 注意：如果你还没有注意到在调试器里的是哪个线程，那现在就看看它们。主线程总是第一个被 libdispatch 跟随，它是 GCD 的坐标，作为第二个线程。之后，线程计数和剩余线程取决于硬件在应用到达断点时正在做的事情。

在调试器里，键入命令：`po [[weakSelf navigationItem] setPrompt:@"WOOT!"]`

然后恢复应用的执行。你会看到如下内容：

[![Dispatch_Sources_Xcode_Breakpoint_Console](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f44697370617463685f536f75726365735f58636f64655f427265616b706f696e745f436f6e736f6c652d363530783530302e706e67.)](media/14796117251911/687474703a2f2f63646e352e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f44697370617463685f536f75726365735f58636f64655f427265616b706f696e745f436f6e736f6c652d363530783530302e706e67.)

[![Dispatch_Sources_Debugger_Updating_UI](media/14796117251911/687474703a2f2f63646e332e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f44697370617463685f536f75726365735f44656275676765725f5570646174696e675f55492d333038783530302e706e67.)](media/14796117251911/687474703a2f2f63646e332e72617977656e6465726c6963682e636f6d2f77702d636f6e74656e742f75706c6f6164732f323031342f30312f44697370617463685f536f75726365735f44656275676765725f5570646174696e675f55492d333038783530302e706e67.)

使用这个方法，你可以更新 UI、查询类的属性，甚至是执行方法——所有这一切都不需要重启应用并到达某个特定的工作状态。相当优美吧！

> 译者注：发挥这一点，是可以做出一些调试库的吧？

## [](https://github.com/nixzhu/dev-blog/blob/master/2014-05-14-grand-central-dispatch-in-depth-part-2.md#之后又该往何处去)之后又该往何处去？

你可以[在此下载最终的项目](http://cdn3.raywenderlich.com/wp-content/uploads/2014/01/GooglyPuff-Final.zip)。

我讨厌再次提及此主题，但你真的要看看 [如何使用 Instruments](http://www.raywenderlich.com/23037/how-to-use-instruments-in-xcode) 教程。如果你计划优化你的应用，那你一定要学会使用它。请注意 Instruments 擅长于分析相对执行：比较哪些区域的代码相对于其它区域的代码花费了更长的时间。如果你尝试计算出某个方法实际的执行时间，那你可能需要拿出更多的自酿的解决方案（Home-brewed Solution）。

同样请看看 [如何使用 NSOperations 和 NSOperationQueues](http://www.raywenderlich.com/19788/how-to-use-nsoperations-and-nsoperationqueues) 吧，它们是建立在 GCD 之上的并发技术。大体来说，如果你在写简单的用过就忘的任务，那它们就是使用 GCD 的最佳实践，。NSOperations 提供更好的控制、处理大量并发操作的实现，以及一个以速度为代价的更加面向对象的范例。

记住，除非你有特别的原因要往下流走（译者的玩笑：即使用低级别 API），否则永远应尝试并坚持使用高级的 API。如果你想学到更多或想做某些非常非常“有趣”的事情，那你就应该冒险进入 Apple 的黑暗艺术。

祝你好运，玩得开心！有任何问题或反馈请在下方的讨论区贴出！

---

译者注：欢迎非商业转载，但请一定注明出处：[https://github.com/nixzhu/dev-blog](https://github.com/nixzhu/dev-blog) ！

欢迎转发此条微博 [http://weibo.com/2076580237/B4eHynxYo](http://weibo.com/2076580237/B4eHynxYo) 以分享给更多人！

如果你认为这篇翻译不错，也有闲钱，那你可以用支付宝随便捐助一点，以慰劳译者的辛苦：

[![nixzhu的支付宝二维码](media/14796117251911/nixzhu_alipay.png)](media/14796117251911/nixzhu_alipay.png)

版权声明：自由转载-非商用-非衍生-保持署名 | [Creative Commons BY-NC-ND 3.0](http://creativecommons.org/licenses/by-nc-nd/3.0/deed.zh)
