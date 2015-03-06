//
//  TestViewController.m
//  IAP Tester
//
//  Created by Ben Kennedy on 2013-03-22.
//  Copyright (c) 2013 Kashoo Inc. All rights reserved.
//

#import "TestViewController.h"
@import StoreKit;
@import AVFoundation;

@interface TestViewController() <SKProductsRequestDelegate, SKPaymentTransactionObserver, UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) IBOutlet UITableView *purchaseTableView;

- (void)applicationDidFinishLaunching:(NSNotification *)notification;

- (IBAction)restorePurchasesAction:(id)sender;
- (IBAction)oinkAction:(id)sender;

@property (nonatomic, strong) NSArray *products;
@property (nonatomic, strong) SKPaymentQueue *paymentQueue;
@property (nonatomic, strong) AVAudioPlayer *oinkPlayer;

@end


@implementation TestViewController

- (instancetype)initWithCoder:(NSCoder *)decoder
{
    if ((self = [super initWithCoder:decoder]))
    {
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidFinishLaunching:) name:UIApplicationDidFinishLaunchingNotification object:nil];
    }

    return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    NSURL *oinkURL = [NSURL URLWithString:@"http://www.freesoundeffects.com/sounds1/pigs/pig.wav"];
    NSURL *localOinkURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:@"oink.wav"]];
    [[NSData dataWithContentsOfURL:oinkURL] writeToURL:localOinkURL options:NSDataWritingAtomic error:nil];

    self.oinkPlayer = [[AVAudioPlayer alloc] initWithContentsOfURL:localOinkURL error:nil];
    [self.oinkPlayer prepareToPlay];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation
{
    return YES;
}


#pragma mark -

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Load our candidate product identifiers from ProductIdentifiers.plist.  There is no way to fetch a "full active set" from the store.
    NSArray *productIdentifiers = [NSArray arrayWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"ProductIdentifiers" withExtension:@"plist"]];
    
    SKProductsRequest *productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
    productsRequest.delegate = self;
    [productsRequest start];

    self.paymentQueue = [SKPaymentQueue defaultQueue];
    [self.paymentQueue addTransactionObserver:self];

    return;
}


- (void)restorePurchasesAction:(id)sender
{
    NSLog(@"Restoring completed transactions...");
    [self.paymentQueue restoreCompletedTransactions];
    
    return;
}


- (void)oinkAction:(id)sender
{
    [self.oinkPlayer play];
}

#pragma mark UITableView data source and delegate

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    if (tableView == self.purchaseTableView)
    {
        return 1;
    }
    else
    {
        return 0;
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    if (tableView == self.purchaseTableView)
    {
        return self.products.count;
    }
    else
    {
        return 0;
    }
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *kPurchaseCellIdentifier = @"PurchaseCell";
    UITableViewCell *cell = nil;
    
    if (tableView == self.purchaseTableView)
    {
        if (!(cell = [tableView dequeueReusableCellWithIdentifier:kPurchaseCellIdentifier]))
        {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:kPurchaseCellIdentifier];
        }
        
        cell.textLabel.text = [self.products[indexPath.row] localizedTitle];
        cell.detailTextLabel.text = [self.products[indexPath.row] localizedDescription];
    }
    
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    SKProduct *product;
    SKPayment *payment;
    
    if (![SKPaymentQueue canMakePayments])
    {
        NSLog(@"The payment queue cannot currently accept payments.");
        return;
    }

    product = self.products[indexPath.row];

    NSLog(@"Initiating a purchase for %@...", product.productIdentifier);
    
    payment = [SKPayment paymentWithProduct:product];
    [self.paymentQueue addPayment:payment];
    
    return;
}


#pragma mark StoreKit delegate methods

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
    if (response.invalidProductIdentifiers.count)
    {
        NSLog(@"This ain't no good; StoreKit failed to validate %d product identifiers: %@", response.invalidProductIdentifiers.count, response.invalidProductIdentifiers);
    }
    else
    {
        self.products = response.products;
    }
    
    [self.purchaseTableView reloadData];
    
    return;
}


- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions
{
    for (SKPaymentTransaction *transaction in transactions)
    {
        NSString *messageTitle = nil, *messageBody = nil;
        
        switch (transaction.transactionState)
        {
            case SKPaymentTransactionStatePurchasing:
                break;

            case SKPaymentTransactionStatePurchased:
            {
                messageTitle = @"Purchase Completed";
                NSLog(@"Completed transaction %@ with a %d-byte receipt.", transaction.transactionIdentifier, transaction.transactionReceipt.length);

                if (transaction.originalTransaction)
                {
                    NSLog(@"This transaction relates to original transaction %@.", transaction.originalTransaction.transactionIdentifier);
                    messageBody = [NSString stringWithFormat:@"Transaction %@ is actually a restoration of previous transaction %@.", transaction.transactionIdentifier, transaction.originalTransaction.transactionIdentifier];
                }
                else
                {
                    messageBody = [NSString stringWithFormat:@"Transaction %@ is a fresh new purchase.", transaction.transactionIdentifier];
                }

                NSLog(@"Here's the receipt:\n%@", transaction.transactionReceipt);

                break;
            }

            case SKPaymentTransactionStateFailed:
            {
                if (transaction.error.code == SKErrorPaymentCancelled)
                {
                    NSLog(@"User canceled the purchase.");
                }
                else
                {
                    messageTitle = transaction.error.localizedDescription;
                    messageBody = transaction.error.localizedFailureReason;
                    NSLog(@"Transaction %@ failed: %@", transaction.transactionIdentifier, transaction.error);
                }
                break;
            }
                
            case SKPaymentTransactionStateRestored:
            {
                messageTitle = @"Restored Transaction";
                messageBody = [NSString stringWithFormat:@"Transaction %@ represents restoration of previous transaction %@ for %@.", transaction.transactionIdentifier, transaction.originalTransaction.transactionIdentifier, transaction.payment.productIdentifier];
                NSLog(@"Restored transaction %@; original transaction %@", transaction, transaction.originalTransaction);
                break;
            }
            
            case SKPaymentTransactionStateDeferred:
            {
                messageTitle = @"Deferred Transaction";
                messageBody = [NSString stringWithFormat:@"Transaction %@ is a deferred purchase.", transaction.transactionIdentifier];
                NSLog(@"Deferred transaction %@", transaction.transactionIdentifier);
            }
        }

        if (transaction.transactionState != SKPaymentTransactionStatePurchasing)
        {
            [self.paymentQueue finishTransaction:transaction];
        }

        if (messageTitle)
        {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:messageTitle message:messageBody delegate:nil cancelButtonTitle:@"OK" otherButtonTitles:nil];
            [alert show];
        }
    }

    NSIndexPath *selectedIndex;
    if ((selectedIndex = self.purchaseTableView.indexPathForSelectedRow))
    {
        [self.purchaseTableView deselectRowAtIndexPath:self.purchaseTableView.indexPathForSelectedRow animated:YES];
    }
    
    return;
}


- (void)paymentQueueRestoreCompletedTransactionsFinished:(SKPaymentQueue *)queue
{
    NSLog(@"The payment queue has finished restoring transactions.");
}


@end
